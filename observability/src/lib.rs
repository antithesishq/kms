// Links the Antithesis coverage shim into every binary that uses this crate.
#[cfg(antithesis)]
use antithesis_instrumentation as _;

pub mod conf;
pub mod grpc;
pub mod health;
pub mod metrics;
pub mod metrics_names;
pub mod sys_metrics;
pub mod telemetry;
