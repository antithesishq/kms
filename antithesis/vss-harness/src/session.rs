//! Runs one VSS session with every party in this process and collects what each party saw.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use algebra::structure_traits::ErrorCorrect;
use rand::SeedableRng;
use serde_json::json;
use threshold_execution::communication::broadcast::SyncReliableBroadcast;
use threshold_execution::large_execution::vss::{SecureVss, Vss};
use threshold_execution::large_execution::vss_observer::{VssEvent, set_observer};
use threshold_execution::malicious_execution::large_execution::fuzzed_vss::FuzzedVss;
use threshold_execution::runtime::sessions::base_session::GenericBaseSessionHandles;
use threshold_execution::runtime::test_runtime::{DistributedTestRuntime, generate_fixed_roles};
use threshold_types::network::{NetworkMode, Networking, RoundClock};
use threshold_types::rng::AesRng;
use threshold_types::role::Role;
use threshold_types::session_id::SessionId;
use tracing::field::{Field, Visit};
use tracing_subscriber::layer::{Context, Layer};

use crate::decisions::LiarDecisions;
use crate::sdk::random_u64;
use crate::sometimes;

/// The parameters of one session, drawn by the main loop.
pub struct SessionConfig {
    pub session_id: u128,
    pub num_parties: usize,
    pub threshold: usize,
    pub batch_size: usize,
    pub liars: BTreeSet<Role>,
    pub round_timeout: Duration,
    /// For a batch of one secret: honest parties call [`Vss::execute`] instead of
    /// [`Vss::execute_many`], as coinflip does.
    pub single_execute: bool,
}

/// What one session produced. All maps are keyed by honest roles only.
pub struct Observed<Z> {
    pub honest: BTreeSet<Role>,
    pub liars: BTreeSet<Role>,
    pub threshold: usize,
    /// The input secrets of every party, liars included.
    pub secrets: HashMap<Role, Vec<Z>>,
    pub outputs: HashMap<Role, Result<Vec<Vec<Z>>, String>>,
    pub corrupt: HashMap<Role, HashSet<Role>>,
    pub events: HashMap<Role, Vec<VssEvent>>,
    /// `(sender, receiver)` pairs of honest parties where the receiver timed out.
    pub honest_timeouts: Vec<(Role, Role)>,
    /// True if every honest party finished within the session budget.
    pub finished: bool,
    pub liar_deviations: u64,
    pub elapsed: Duration,
}

/// The liars of the session that runs now. The observer reads it to place reach claims.
static CURRENT_LIARS: Mutex<BTreeSet<Role>> = Mutex::new(BTreeSet::new());
static EVENTS: Mutex<Vec<(SessionId, Role, VssEvent)>> = Mutex::new(Vec::new());
/// Timeouts of the session that runs now, as `(sender, receiver)`.
static TIMEOUTS: Mutex<Vec<(u64, u64)>> = Mutex::new(Vec::new());

/// Installs the VSS observer. Call once at startup.
pub fn install_observer() -> anyhow::Result<()> {
    set_observer(Box::new(|session_id, role, event| {
        let liars = CURRENT_LIARS.lock().expect("liars lock").clone();
        if !liars.contains(&role) {
            mid_session_claims(&liars, role, &event);
        }
        EVENTS
            .lock()
            .expect("events lock")
            .push((session_id, role, event));
    }))
}

/// Reach claims that fire while the session runs, so that Antithesis can branch from the
/// moment a rare state appears.
fn mid_session_claims(liars: &BTreeSet<Role>, role: Role, event: &VssEvent) {
    match event {
        VssEvent::Round3 {
            unhappy, corrupt, ..
        } => {
            let unhappy_with_surviving_liar = liars.iter().any(|dealer| {
                !corrupt.contains(dealer)
                    && unhappy[dealer.one_based() - 1]
                        .iter()
                        .any(|party| !liars.contains(party))
            });
            sometimes!(
                unhappy_with_surviving_liar,
                "VSS: an honest party is unhappy with a lying dealer that survives round 3",
                json!({ "observer": role.one_based() })
            );
        }
        VssEvent::Round4Vote {
            dealer,
            unhappy_party,
            voters,
            ..
        } => {
            let corrupt_after_round_3 = EVENTS
                .lock()
                .expect("events lock")
                .iter()
                .rev()
                .find_map(|(_, r, e)| match e {
                    VssEvent::Round3 { corrupt, .. } if *r == role => Some(corrupt.clone()),
                    _ => None,
                })
                .unwrap_or_default();
            let details = json!({
                "observer": role.one_based(),
                "dealer": dealer.one_based(),
                "unhappy_party": unhappy_party.one_based(),
            });
            sometimes!(
                voters.iter().any(|v| liars.contains(v)),
                "VSS: a liar is counted as a round-4 voter",
                details.clone()
            );
            sometimes!(
                voters.iter().any(|v| corrupt_after_round_3.contains(v)),
                "VSS: a party marked corrupt in round 3 is counted as a round-4 voter",
                details
            );
        }
        VssEvent::Round2 { .. } | VssEvent::Round4 { .. } => {}
    }
}

/// A tracing layer that records the "Sender X timed out when sending to Y" warnings of
/// `threshold_execution::communication::p2p`.
pub struct TimeoutLayer;

#[derive(Default)]
struct MessageVisitor(String);

impl Visit for MessageVisitor {
    fn record_debug(&mut self, field: &Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0 = format!("{value:?}");
        }
    }
}

impl<S: tracing::Subscriber> Layer<S> for TimeoutLayer {
    fn on_event(&self, event: &tracing::Event<'_>, _ctx: Context<'_, S>) {
        if *event.metadata().level() != tracing::Level::WARN {
            return;
        }
        let mut visitor = MessageVisitor::default();
        event.record(&mut visitor);
        let parsed = visitor
            .0
            .strip_prefix("Sender ")
            .and_then(|rest| rest.split_once(" timed out when sending to "))
            .and_then(|(sender, receiver)| Some((sender.parse().ok()?, receiver.parse().ok()?)));
        if let Some(pair) = parsed {
            TIMEOUTS.lock().expect("timeouts lock").push(pair);
        }
    }
}

/// Runs one VSS session over the ring `Z` and returns what the honest parties saw.
pub async fn run<Z, const EXTENSION_DEGREE: usize>(
    config: &SessionConfig,
    liar_decisions: &HashMap<Role, Arc<LiarDecisions>>,
    secrets: HashMap<Role, Vec<Z>>,
) -> Observed<Z>
where
    Z: ErrorCorrect,
{
    let start = Instant::now();
    let roles = generate_fixed_roles(config.num_parties);
    let honest: BTreeSet<Role> = roles
        .difference(&config.liars.iter().copied().collect())
        .copied()
        .collect();
    *CURRENT_LIARS.lock().expect("liars lock") = config.liars.clone();
    TIMEOUTS.lock().expect("timeouts lock").clear();
    let session_id = SessionId::from(config.session_id);

    let runtime = DistributedTestRuntime::<Z, Role, EXTENSION_DEGREE>::new(
        roles.clone(),
        config.threshold as u8,
        NetworkMode::Sync,
        None,
    );
    // All parties share one round clock that starts now, with the configured round timeout.
    let clock = RoundClock {
        init_time: Instant::now(),
        round: 0,
        max_elapsed_time: Duration::ZERO,
        current_network_timeout: config.round_timeout,
        next_network_timeout: config.round_timeout,
    };
    for net in runtime.user_nets.values() {
        net.restore_round_clock(clock).await;
    }

    let mut honest_tasks = tokio::task::JoinSet::new();
    let mut task_roles = HashMap::new();
    let mut liar_tasks = Vec::new();
    for role in roles.iter().copied() {
        let mut session = runtime.base_session_for_party(
            session_id,
            role,
            Some(AesRng::seed_from_u64(random_u64())),
        );
        let my_secrets = secrets[&role].clone();
        match liar_decisions.get(&role) {
            Some(decisions) => {
                let vss = FuzzedVss::new(&SyncReliableBroadcast::default(), decisions.clone());
                liar_tasks.push(tokio::spawn(async move {
                    let _ = vss.execute_many(&mut session, &my_secrets).await;
                }));
            }
            None => {
                let single = config.single_execute && my_secrets.len() == 1;
                let handle = honest_tasks.spawn(async move {
                    let vss = SecureVss::default();
                    let result = if single {
                        vss.execute(&mut session, &my_secrets[0])
                            .await
                            .map(|shares| shares.into_iter().map(|share| vec![share]).collect())
                    } else {
                        vss.execute_many(&mut session, &my_secrets).await
                    };
                    (
                        role,
                        result.map_err(|e| format!("{e:?}")),
                        session.corrupt_roles().clone(),
                    )
                });
                task_roles.insert(handle.id(), role);
            }
        }
    }

    // A session never needs more than its worst-case round count of timeouts. The slack
    // covers the extra round-0 timeout and scheduling.
    let rounds = SecureVss::num_rounds(config.num_parties, config.threshold) as u32;
    let budget = config.round_timeout * (rounds + 3);
    let mut outputs = HashMap::new();
    let mut corrupt = HashMap::new();
    let finished = tokio::time::timeout(budget, async {
        while let Some(joined) = honest_tasks.join_next().await {
            match joined {
                Ok((role, result, corrupt_roles)) => {
                    outputs.insert(role, result);
                    corrupt.insert(role, corrupt_roles);
                }
                // A panic of an honest party counts as an output error of that party.
                Err(e) => {
                    tracing::error!("honest VSS task failed: {e}");
                    if let Some(role) = task_roles.get(&e.id()) {
                        outputs.insert(*role, Err(format!("task failed: {e}")));
                    }
                }
            }
        }
    })
    .await
    .is_ok();
    honest_tasks.abort_all();
    for task in liar_tasks {
        task.abort();
    }

    let mut events: HashMap<Role, Vec<VssEvent>> = HashMap::new();
    EVENTS
        .lock()
        .expect("events lock")
        .retain(|(sid, role, event)| {
            if *sid == session_id && honest.contains(role) {
                events.entry(*role).or_default().push(event.clone());
            }
            false
        });
    let honest_ids: HashSet<u64> = honest.iter().map(|r| r.one_based() as u64).collect();
    let honest_timeouts = TIMEOUTS
        .lock()
        .expect("timeouts lock")
        .iter()
        .filter(|(sender, receiver)| honest_ids.contains(sender) && honest_ids.contains(receiver))
        .map(|(sender, receiver)| {
            (
                Role::indexed_from_one(*sender as usize),
                Role::indexed_from_one(*receiver as usize),
            )
        })
        .collect();

    Observed {
        honest,
        liars: config.liars.clone(),
        threshold: config.threshold,
        secrets,
        outputs,
        corrupt,
        events,
        honest_timeouts,
        finished,
        liar_deviations: liar_decisions.values().map(|d| d.deviations()).sum(),
        elapsed: start.elapsed(),
    }
}

/// Returns the ring elements a secret is drawn from: zero, one, or a random element.
pub fn draw_secret<Z: ErrorCorrect>(rng: &mut AesRng) -> Z {
    match crate::sdk::index(3) {
        0 => Z::ZERO,
        1 => Z::ONE,
        _ => Z::sample(rng),
    }
}

/// Returns a fresh random generator for the session's secrets.
pub fn secrets_rng() -> AesRng {
    AesRng::seed_from_u64(random_u64())
}
