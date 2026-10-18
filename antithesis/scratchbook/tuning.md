---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# Tuning

Class-level tuning of the KMS for testing, as `workload-guidance.md` (section 4) asks. Every row
applies identically to the current and the pre-fix version. "Production default" is the upstream
Helm chart's value (`charts/kms-core/values.yaml`, `templates/kms-core-configmap.yaml`) where the
chart sets one, else the code default (`core/threshold-networking/src/constants.rs`,
`core/service/src/consts.rs`). Test values are from
[31-kms-core-1.yaml](../config/manifests/31-kms-core-1.yaml) (identical for all four cores) and
[40-kms-core-init.yaml](../config/manifests/40-kms-core-init.yaml).

No row here was chosen for a specific known bug. The known bug for the positive control isn't
picked yet; the "Touches" column names the fixes whose code a row's behaviour class covers, so
that check can be made once it is.

## Already tuned (in the manifests and the workload)

| Setting | Test value | Production default | Behaviour class | Source | Touches |
|---|---|---|---|---|---|
| Cluster size (`threshold`, `[[threshold.peers]]`) | n = 4, t = 1 | n = 13, t = 4 (`thresholdValue: 4`) | smallest cluster with n > 3t, so one failure is survivable | project's own test topology (4-party tests and k3s scripts) | — |
| FHE parameters (client `fhe_params`, keygen) | `Test` (`PARAMS_TEST_BK_SNS`, zero noise) | `Default` (`kmsCoreClient.fhe_parameter`) | every FHE operation fast enough for many per timeline; no noise-induced false positives | project test value | — |
| Key generation | `insecure-preproc-key-gen` + `insecure-key-gen` (`first_generate_key.sh`) | distributed preprocessing and keygen (hours) | get a key in seconds so decryption and resharing run; DKG itself isn't exercised | project `insecure` feature for tests | #885 not exercised |
| Build and attestation | `insecure` feature, `mock_enclave = true`, `trusted_releases = []` | Nitro enclave, PCR allowlist | run without AWS Nitro | project dev configuration | — |
| `client num_majority` / `num_reconstruct` | 2 / 3 | 5 / 9 (for n = 13) | scaled to n = 4: t + 1 and 2t + 1 | derived from n, t | — |
| `num_sessions_preproc` | 2 | 100 ("number of vCPUs") | preprocessing parallelism sized to the test VM | earlier harness choice | — |
| `num_rayon_threads` / `num_tokio_threads` | 8 / 2 | 40 / 10 | CPU sized to the test VM | earlier harness choice | — |
| `rate_limiter_conf.bucket_size` | 51000 | 50000 | lets one preprocessing (cost 50000) and one keygen (1000) hold tokens together | earlier harness choice | #229 (rate limiter) |
| Core resources | requests 100m / 2 Gi, limits 8 Gi | none set | fits Antithesis's 1 CPU / 10 Gi request cap; memory leaks surface as OOM kills | earlier harness choice | — |
| Workload timeouts | decrypt `timeout 300`, `--max-iter 120`; reshare `timeout 900`, `--max-iter 1200` | CLI default `--max-iter 30`, no timeout | bound each test command | our choice | — |

## Same as production (deliberately not tuned)

| Setting | Value | Code default | Why left alone |
|---|---|---|---|
| `network_timeout` / `_bk` / `_bk_sns` | 300 / 300 / 1200 s | 120 / 300 / 1200 s | chart values; Sync-mode wait per message |
| `multiplier`, `max_interval`, `max_elapsed_time`, `initial_interval_ms` | 2, 60 s, 300 s, 100 ms | 1.1, 60 s, 90 s, 100 ms | chart values; send back-off |
| keepalive interval / timeout | 15 s / 30 s (unset) | 15 s / 30 s | already on the fault timescale; it's the #887 fix, so tuning it would aim at that bug |
| `session_update_interval_secs` | 60 s | 60 s | — |
| `max_opened_inactive_sessions_per_party` | 1000 | 2000 | chart value |
| `max_waiting_time_for_message_queue` | 60 s | 60 s | — |
| `timeout_secs` (gRPC) | 360 s (+300 s server-side) | chart `grpcTimeout: 360` | — |
| `decryption_mode` | `NoiseFloodSmall` | `NoiseFloodSmall` | — |
| Probes | readiness 30 × 5 s, startup 60 × 10 s, liveness 10 × 10 s | same in the chart | conservative, as Antithesis recommends |
| `terminationGracePeriodSeconds` | unset (30 s) | unset in the chart | — |
| Launcher `cpu_pressure` | off | — | interacts with the KMS's own timeouts; an experiment, not a default |

## Proposed (not applied; the manifests are unchanged)

| Setting | Proposed value | Current = production | Behaviour class | Source | Touches |
|---|---|---|---|---|---|
| `session_cleanup_interval_secs` | 600 s | 86400 s | **proposed:** completed MPC sessions are forgotten within a test, so the cleanup path runs and a request ID can be reused after cleanup (redo of a failed attempt, Guarantee 5) | our choice ("background jobs every minute instead of every day") | session-store cleanup task (#834 area) |
| `discard_inactive_sessions_interval` | 300 s | 900 s | **proposed:** buffered messages for unknown sessions are dropped, and an Async decryption gives up on a missing party (this value is its per-message wait), on the timescale of faults and of Guarantee 2's window | our choice | session-store cleanup task (#834 area), late-party handling |
| `dec_capacity` / `min_dec_cache` | 200 / 100 | 10000 / 6000 | **proposed:** the decryption meta stores fill and evict completed entries within a run, so a resend of an evicted ID (answered as new) is reached for Guarantee 5. Allows 100 pending decryptions per core; more get `ResourceExhausted`, which is retryable | our choice | meta-store eviction (#58 area) |
| `custom.pod_fault_interval_seconds` | 600 s for hunts at first | 300 s (launcher) | **proposed:** fewer overlapping pod faults (more than t) until the recovery times are measured | already in the "network+kill" fault level | — |

## Harness proposals (environment, not tuning)

- Make the core pods' `kms-core-init-load-env` init container retry until all four peer CA
  certificates are fetched, and exit non-zero otherwise. Today a core pod that starts while MinIO
  is unreachable writes an invalid config and stays down
  ([deployment-topology.md](deployment-topology.md#known-deployment-hazards)).
- For [Guarantee 2](guarantees.md#guarantee-2), open the quiet window with
  `$ANTITHESIS_STOP_FAULTS 900` (or use an `eventually_` command) so both of its bounds fit
  ([details](properties/recovers-after-faults.md#is-300-s-safe)).
