//! Reports the sets that a party computes during [`super::vss`] to an installed observer.
//!
//! The VSS dispute resolution decides who is unhappy, who votes and who is corrupt from
//! broadcast data, so all honest parties must compute the same sets. A test harness that runs
//! every party in one process installs an observer to compare these views across parties.
//! Without an installed observer, [`emit`] does nothing.

use std::collections::{BTreeSet, HashSet};
use std::sync::OnceLock;

use threshold_types::role::Role;
use threshold_types::session_id::SessionId;

use crate::runtime::sessions::base_session::BaseSessionHandles;

/// A set computation of one party during a VSS. A party emits the events in round order.
#[derive(Clone, Debug)]
pub enum VssEvent {
    /// The corrupt set at the end of round 2.
    Round2 { corrupt: HashSet<Role> },
    /// The disputed `(dealer, Pi, Pj)` triples, the unhappy set of each dealer (indexed by the
    /// zero-based dealer index) and the corrupt set at the end of round 3.
    Round3 {
        potentially_unhappy: HashSet<(Role, Role, Role)>,
        unhappy: Vec<HashSet<Role>>,
        corrupt: HashSet<Role>,
    },
    /// The round-4 vote on the conflict between `dealer` and `unhappy_party`.
    /// `voters` are the parties whose values were counted, and `yes_voters` are the voters whose
    /// value matched the row that the dealer broadcast. The dealer always counts one vote for
    /// itself, which `yes_voters` does not include.
    Round4Vote {
        dealer: Role,
        unhappy_party: Role,
        voters: BTreeSet<Role>,
        yes_voters: BTreeSet<Role>,
        dealer_thrown_out: bool,
    },
    /// The corrupt set at the end of round 4, and the dealers for which the party took its
    /// share from the round-4 broadcast instead of round 1.
    Round4 {
        corrupt: HashSet<Role>,
        repaired_from: BTreeSet<Role>,
    },
}

/// The function that receives every [`VssEvent`], with the session and the emitting party.
pub type VssObserver = Box<dyn Fn(SessionId, Role, VssEvent) + Send + Sync>;

static OBSERVER: OnceLock<VssObserver> = OnceLock::new();

/// Installs `observer` for the lifetime of the process.
///
/// Returns an error if an observer is already installed.
pub fn set_observer(observer: VssObserver) -> anyhow::Result<()> {
    OBSERVER
        .set(observer)
        .map_err(|_| anyhow::anyhow!("a VSS observer is already installed"))
}

/// Passes the event that `event` builds to the installed observer.
/// It builds the event only if an observer is installed.
pub(crate) fn emit<S: BaseSessionHandles>(session: &S, event: impl FnOnce() -> VssEvent) {
    if let Some(observer) = OBSERVER.get() {
        observer(session.session_id(), session.my_role(), event());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::large_execution::vss::{SecureVss, Vss};
    use crate::runtime::test_runtime::{DistributedTestRuntime, generate_fixed_roles};
    use algebra::galois_rings::degree_4::ResiduePolyF4Z64;
    use algebra::structure_traits::{One, Ring};
    use std::sync::Mutex;
    use threshold_types::network::NetworkMode;

    /// Other tests of the crate run VSS sessions concurrently, so the observer keeps only the
    /// events of this session.
    const SESSION: u128 = 0x0b5e_55ed;
    static EVENTS: Mutex<Vec<(Role, VssEvent)>> = Mutex::new(Vec::new());

    #[tokio::test]
    async fn observer_receives_rounds_2_3_and_4_of_every_party() {
        set_observer(Box::new(|session_id, role, event| {
            if session_id == SessionId::from(SESSION) {
                EVENTS.lock().unwrap().push((role, event));
            }
        }))
        .unwrap();
        assert!(set_observer(Box::new(|_, _, _| {})).is_err());

        let roles = generate_fixed_roles(4);
        let runtime = DistributedTestRuntime::<
            ResiduePolyF4Z64,
            Role,
            { ResiduePolyF4Z64::EXTENSION_DEGREE },
        >::new(roles.clone(), 1, NetworkMode::Sync, None);
        let mut tasks = tokio::task::JoinSet::new();
        for role in roles.iter() {
            let mut session = runtime.base_session_for_party(SessionId::from(SESSION), *role, None);
            tasks.spawn(async move {
                SecureVss::default()
                    .execute_many(&mut session, &[ResiduePolyF4Z64::ONE])
                    .await
                    .unwrap()
            });
        }
        tasks.join_all().await;

        let events = EVENTS.lock().unwrap();
        for role in roles {
            let rounds: Vec<&str> = events
                .iter()
                .filter(|(r, _)| *r == role)
                .map(|(_, event)| match event {
                    VssEvent::Round2 { .. } => "round 2",
                    VssEvent::Round3 { .. } => "round 3",
                    VssEvent::Round4Vote { .. } => "vote",
                    VssEvent::Round4 { .. } => "round 4",
                })
                .collect();
            // An honest execution has no conflicts, so there is no vote.
            assert_eq!(rounds, ["round 2", "round 3", "round 4"], "party {role}");
        }
    }
}
