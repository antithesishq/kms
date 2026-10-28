//! Antithesis harness for the VSS protocol of `threshold-execution`.
//!
//! Each iteration runs one VSS session with all parties in this process, over the local
//! network of the test runtime. Up to t parties are liars: they run
//! [`FuzzedVss`](threshold_execution::malicious_execution::large_execution::fuzzed_vss::FuzzedVss),
//! whose choices come from Antithesis randomness. The honest parties run the production
//! [`SecureVss`](threshold_execution::large_execution::vss::SecureVss) and report the sets
//! they compute through the VSS observer. After each session, [`checks::check`] asserts the
//! properties. See `antithesis/feature-workloads/vss/analysis.md`.
//!
//! Environment:
//! - `VSS_ITERATIONS`: number of sessions. Unset means forever inside Antithesis and 20 locally.
//! - `VSS_ROUND_TIMEOUT_MS`: network timeout of one round (default 3000).
//! - `VSS_LOG`: log level of the VSS code (default `error`).
//! - `VSS_SEED`: seed of the local random generator. Antithesis supplies its own randomness.

mod checks;
mod decisions;
mod sdk;
mod session;

use std::collections::{BTreeSet, HashMap};
use std::sync::Arc;
use std::time::Duration;

use algebra::galois_rings::degree_4::{ResiduePolyF4Z64, ResiduePolyF4Z128};
use algebra::structure_traits::{ErrorCorrect, Ring};
use serde_json::json;
use threshold_types::role::Role;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::prelude::*;

use crate::decisions::LiarDecisions;
use crate::sdk::{in_antithesis, index, pick};
use crate::session::{SessionConfig, TimeoutLayer};

/// The (n, t) menu: the production n = 4, the tight n = 3t + 1 bound up to t = 4, and two
/// sizes with spare honest parties. n = 4 appears twice to weight it.
const SIZES: [(usize, usize); 7] = [(4, 1), (4, 1), (5, 1), (7, 2), (8, 2), (10, 3), (13, 4)];
/// The largest batch the harness runs, which bounds the time of one session.
const MAX_BATCH: usize = 20;

fn env_parse<T: std::str::FromStr>(name: &str) -> Option<T> {
    std::env::var(name).ok().and_then(|v| v.parse().ok())
}

/// Returns the batch size of a PRSS setup: `ceil(binom(n, t) / (n - t))`, capped at [`MAX_BATCH`].
fn prss_batch(n: usize, t: usize) -> usize {
    num_integer::binomial(n, t).div_ceil(n - t).min(MAX_BATCH)
}

fn init_tracing() {
    let level = std::env::var("VSS_LOG").unwrap_or_else(|_| "error".to_string());
    let level: LevelFilter = level.parse().unwrap_or(LevelFilter::ERROR);
    tracing_subscriber::registry()
        .with(TimeoutLayer.with_filter(LevelFilter::WARN))
        .with(
            tracing_subscriber::fmt::layer()
                .with_ansi(false)
                .with_filter(level),
        )
        .init();
}

async fn run_one(iteration: u64, round_timeout: Duration) {
    let (n, t) = pick(&SIZES);
    let num_liars = pick(&[t, t, t, 1 + index(t), 0]);
    let mut candidates: Vec<usize> = (1..=n).collect();
    let mut liars = BTreeSet::new();
    for _ in 0..num_liars {
        liars.insert(Role::indexed_from_one(
            candidates.swap_remove(index(candidates.len())),
        ));
    }
    let batch_size = pick(&[1, 2, prss_batch(n, t)]);
    let decisions: HashMap<Role, Arc<LiarDecisions>> = liars
        .iter()
        .map(|role| (*role, Arc::new(LiarDecisions::draw(*role, n))))
        .collect();
    let config = SessionConfig {
        session_id: (u128::from(iteration) << 64) | u128::from(sdk::random_u64()),
        num_parties: n,
        threshold: t,
        batch_size,
        liars,
        round_timeout,
        single_execute: index(2) == 0,
    };
    let z128 = index(2) == 1;
    println!(
        "{}",
        json!({
            "event": "session_start",
            "iteration": iteration,
            "n": n,
            "t": t,
            "batch_size": batch_size,
            "single_execute": config.single_execute && batch_size == 1,
            "ring": if z128 { "ResiduePolyF4Z128" } else { "ResiduePolyF4Z64" },
            "liars": config.liars.iter().map(|r| r.one_based()).collect::<Vec<_>>(),
            "profiles": decisions.values().map(|d| d.describe()).collect::<Vec<_>>(),
        })
    );
    if z128 {
        run_ring::<ResiduePolyF4Z128, { ResiduePolyF4Z128::EXTENSION_DEGREE }>(&config, &decisions)
            .await
    } else {
        run_ring::<ResiduePolyF4Z64, { ResiduePolyF4Z64::EXTENSION_DEGREE }>(&config, &decisions)
            .await
    }
}

async fn run_ring<Z: ErrorCorrect, const EXTENSION_DEGREE: usize>(
    config: &SessionConfig,
    decisions: &HashMap<Role, Arc<LiarDecisions>>,
) {
    let mut rng = session::secrets_rng();
    let secrets: HashMap<Role, Vec<Z>> = (1..=config.num_parties)
        .map(|i| {
            let secrets = (0..config.batch_size)
                .map(|_| session::draw_secret::<Z>(&mut rng))
                .collect();
            (Role::indexed_from_one(i), secrets)
        })
        .collect();
    let observed = session::run::<Z, EXTENSION_DEGREE>(config, decisions, secrets).await;
    checks::check(&observed, config.num_parties, config.batch_size);
    let corrupt = observed
        .corrupt
        .values()
        .next()
        .map(|set| {
            let mut ids: Vec<usize> = set.iter().map(|r| r.one_based()).collect();
            ids.sort();
            ids
        })
        .unwrap_or_default();
    println!(
        "{}",
        json!({
            "event": "session_end",
            "finished": observed.finished,
            "corrupt": corrupt,
            "liar_deviations": observed.liar_deviations,
            "honest_timeouts": observed.honest_timeouts.len(),
            "elapsed_ms": observed.elapsed.as_millis() as u64,
        })
    );
}

fn main() -> anyhow::Result<()> {
    antithesis_sdk::antithesis_init();
    init_tracing();
    session::install_observer()?;

    let iterations: Option<u64> =
        env_parse("VSS_ITERATIONS").or(if in_antithesis() { None } else { Some(20) });
    let round_timeout = Duration::from_millis(env_parse("VSS_ROUND_TIMEOUT_MS").unwrap_or(3000));
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    antithesis_sdk::lifecycle::setup_complete(&json!({ "harness": "vss" }));
    let mut iteration = 0;
    while iterations.is_none_or(|max| iteration < max) {
        runtime.block_on(run_one(iteration, round_timeout));
        iteration += 1;
    }

    let violations = sdk::summary();
    if violations > 0 {
        anyhow::bail!("{violations} property violations");
    }
    Ok(())
}
