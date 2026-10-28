//! Assertions and randomness that work both inside Antithesis and locally.
//!
//! Inside Antithesis (`ANTITHESIS_OUTPUT_DIR` is set), the SDK reports assertions and supplies
//! the randomness. Locally, the SDK assertions do nothing, so the macros here also count
//! violations and reach claims, and [`summary`] prints them at the end of a run. Local
//! randomness comes from a seeded generator, so `VSS_SEED` reproduces a local run.

use std::collections::BTreeMap;
use std::sync::{Mutex, OnceLock};

use rand::{Rng, SeedableRng, rngs::StdRng};

/// Returns true inside Antithesis.
pub fn in_antithesis() -> bool {
    std::env::var_os("ANTITHESIS_OUTPUT_DIR").is_some()
}

fn local_rng() -> &'static Mutex<StdRng> {
    static RNG: OnceLock<Mutex<StdRng>> = OnceLock::new();
    RNG.get_or_init(|| {
        let seed = std::env::var("VSS_SEED")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or_else(rand::random);
        eprintln!("local mode: VSS_SEED={seed}");
        Mutex::new(StdRng::seed_from_u64(seed))
    })
}

/// Returns a random `u64` from Antithesis, or from the local generator.
pub fn random_u64() -> u64 {
    if in_antithesis() {
        antithesis_sdk::random::get_random()
    } else {
        local_rng().lock().expect("local rng lock").r#gen()
    }
}

/// Returns a random index below `len`, with `len > 0`.
pub fn index(len: usize) -> usize {
    (random_u64() % len as u64) as usize
}

/// Returns a random element of `items`, which must not be empty.
pub fn pick<T: Copy>(items: &[T]) -> T {
    items[index(items.len())]
}

/// Returns true with probability `p`.
pub fn chance(p: f64) -> bool {
    p > 0.0 && (random_u64() as f64 / u64::MAX as f64) < p
}

#[derive(Default)]
struct LocalTally {
    violations: BTreeMap<&'static str, u64>,
    /// For each reach claim: (evaluations, evaluations that were true).
    reach: BTreeMap<&'static str, (u64, u64)>,
}

fn tally() -> &'static Mutex<LocalTally> {
    static TALLY: OnceLock<Mutex<LocalTally>> = OnceLock::new();
    TALLY.get_or_init(Default::default)
}

/// Records one evaluation of an invariant for the local summary.
pub fn record_always(cond: bool, name: &'static str, details: &serde_json::Value) {
    if !cond {
        eprintln!("VIOLATION: {name}: {details}");
        *tally()
            .lock()
            .expect("tally lock")
            .violations
            .entry(name)
            .or_default() += 1;
    }
}

/// Records one evaluation of a reach claim for the local summary.
pub fn record_sometimes(cond: bool, name: &'static str) {
    let mut tally = tally().lock().expect("tally lock");
    let entry = tally.reach.entry(name).or_default();
    entry.0 += 1;
    if cond {
        entry.1 += 1;
    }
}

/// Prints the local summary and returns the number of violations.
pub fn summary() -> u64 {
    let tally = tally().lock().expect("tally lock");
    eprintln!("--- reach claims (true / evaluated) ---");
    for (name, (evaluated, hit)) in tally.reach.iter() {
        let mark = if *hit == 0 { "NOT REACHED" } else { "ok" };
        eprintln!("{mark:>12}  {hit:>6} / {evaluated:<6} {name}");
    }
    eprintln!("--- violations ---");
    for (name, count) in tally.violations.iter() {
        eprintln!("{count:>6}  {name}");
    }
    tally.violations.values().sum()
}

/// Asserts an invariant with the SDK and records it locally.
/// The name must be a string literal, so that Antithesis catalogs the assertion.
#[macro_export]
macro_rules! always {
    ($cond:expr, $name:literal, $details:expr) => {{
        let cond: bool = $cond;
        let details: serde_json::Value = $details;
        antithesis_sdk::assert_always!(cond, $name, &details);
        $crate::sdk::record_always(cond, $name, &details);
    }};
}

/// Asserts a reach claim with the SDK and records it locally.
/// The name must be a string literal, so that Antithesis catalogs the assertion.
#[macro_export]
macro_rules! sometimes {
    ($cond:expr, $name:literal, $details:expr) => {{
        let cond: bool = $cond;
        let details: serde_json::Value = $details;
        antithesis_sdk::assert_sometimes!(cond, $name, &details);
        $crate::sdk::record_sometimes(cond, $name);
    }};
}

/// Marks a reachable point with the SDK and records it locally.
/// The name must be a string literal, so that Antithesis catalogs the assertion.
#[macro_export]
macro_rules! reachable {
    ($name:literal, $details:expr) => {{
        let details: serde_json::Value = $details;
        antithesis_sdk::assert_reachable!($name, &details);
        $crate::sdk::record_sometimes(true, $name);
    }};
}
