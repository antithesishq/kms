---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: https://docs.zama.org/protocol/protocol/overview/kms
    why: "guaranteed output delivery even if some nodes are offline or misbehaving"
  - path: /home/exedev/kms/advanced_k8s_test.md
    why: how pod faults, quiet windows and $ANTITHESIS_STOP_FAULTS behave in the launcher
---

# recovers-after-faults

Checks [Guarantee 2](../guarantees.md#guarantee-2) (the cluster serves decryptions again after
faults stop). Catalog entry: [property-catalog.md](../property-catalog.md#recovers-after-faults).

## Evidence trail

- **Claim.** "It supports guaranteed output delivery even if some nodes are offline or misbehaving"
  (KMS overview). "When a threshold node restarts, it will automatically use init material it finds
  on disk. This allows failing nodes to re-join an existing set of nodes, without running `init`
  again" ([kms-server-bin.md](../../../docs/guides/kms-server-bin.md), line 271).
- **No documented recovery time.** Neither the docs nor the chart give a failover or rejoin time.
  The guarantee's 300 s comes from the deployed `network_timeout`. The pieces below are the
  timeouts that actually govern recovery.
- **Documented limit.** "If one party is very late however, and does not catchup before the 3 other
  parties finish running the protocol, then this late party will never be able to catchup for this
  specific request" ([common-errors.md](../../../docs/operations/advanced/common-errors.md), lines
  75-77). That's per request; a **new** request after recovery must still succeed everywhere.
- **History.** #887 (September 2026) added HTTP/2 keepalive because a running party couldn't reach a
  restarted one over a dead connection.

## What recovery takes, step by step

After the last fault, a killed or stopped core goes through these steps. Timeouts are from the
manifests at `harness_commit` and the code at `commit`.

| Step | Bound | Source |
|---|---|---|
| A `pod_stop` that began just before faults stopped: SIGTERM, graceful shutdown waits for in-flight tasks, then SIGKILL | ≤ 30 s (`terminationGracePeriodSeconds` unset → 30 s) | `31-kms-core-1.yaml` (no field); `core/service/src/engine/threshold/threshold_kms.rs:117-150`; `core/service/src/engine/server.rs:36-62` (SIGTERM handled) |
| StatefulSet recreates the pod (same name, same MPC identity) | seconds | `31-kms-core-1.yaml:68-92` (`replicas: 1`, `podManagementPolicy: Parallel`, one StatefulSet per party) |
| Init container `kms-core-init-load-env`: lists and fetches the four peer CA certificates from MinIO with `curl -s` (no timeout, no retry), then `envsubst` | seconds if MinIO answers; ~2 min per curl if SYNs are dropped; **broken config if a list returns nothing** | `31-kms-core-1.yaml:107-191` (same logic as the chart's mock-enclave branch, `charts/kms-core/templates/_helpers.tpl:321-324`) |
| Init container `kms-core-init-gen-keys` (`kms-gen-keys`, a no-op when keys exist) | seconds | `31-kms-core-1.yaml:221-264` |
| `kms-server` boot: re-store the default context, read **every** key share of every epoch and every `EpochData` from MinIO, verify public storage (repair from peers if needed), start the MPC and service servers | unmeasured; grows with the number of reshared epochs | `kms_impl.rs:512-662`, `:852`; `epoch_manager.rs:456` |
| A storage error during boot ends the process; Kubernetes restarts the container with back-off 10 s, 20 s, … capped at 300 s | up to 300 s per restart | `kms_impl.rs:549-555` (`?` on reads); Kubernetes `CrashLoopBackOff` |
| Startup probe: 60 × 10 s; liveness: 10 failures × 10 s | 600 s boot budget before the container is killed | `31-kms-core-1.yaml:326-347` |
| Readiness: gRPC `readiness` service = initialized, live, not shutting down. It does **not** check peer connectivity | 10 s initial delay, then every 5 s | `31-kms-core-1.yaml:326-332`; `observability/src/health.rs:1-90` |
| Peers' HTTP/2 channels to the old pod are dead; keepalive ping every 15 s, 30 s to answer, then the channel closes and the next send reconnects (connect timeout 5 s) | ≤ 45 s + 5 s | `core/threshold-networking/src/constants.rs:65-72`; `sending_service/service.rs:145-147, 168-170, 435-449` |
| A message send retries with exponential back-off: 100 ms initial, ×2, capped at 60 s per interval, given up after 300 s | ≤ 60 s for the next retry | `31-kms-core-1.yaml:405-408` (`multiplier = 2`, `max_interval = 60`, `max_elapsed_time = 300`, `initial_interval_ms = 100`) |
| A decryption session waits for a missing party's messages for up to `discard_inactive_sessions_interval` (Async mode), not `network_timeout` | 900 s, for sessions that started during faults | `sending_service/session.rs:378-382`; `31-kms-core-1.yaml:416` |
| Partitions: no pod restart; after healing, the same keepalive (≤ 45 s) and back-off (≤ 60 s) apply | ≤ ~105 s | as above |

A new request started after recovery opens fresh sessions, so the 900 s and 300 s session waits
apply only to requests that were in flight during faults. They don't block new requests unless the
meta store fills (`dec_capacity − min_dec_cache` = 4000 pending entries) or the rate limiter runs out
(bucket 51000, cost 1 per decryption): neither is close at the workload's rate.

## Client timeouts the checker must respect

- **The CLI needs every core up before it sends anything.** It connects to all four cores
  (`core-client/src/lib.rs:2029, 2038`; seven attempts 100 ms apart, `lib.rs:81-97`, no connect
  timeout). A core with no ready pod → connection refused → exit 1 at once. So "all four cores
  accept connections" is directly observable: it's the first point at which a probe can get past
  connect.
- **Polling:** `GetPublicDecryptionResult` blocks up to 60 s server-side while pending
  (`consts.rs:66`), then `Unavailable`; the CLI sleeps 500 ms and retries up to `--max-iter` times
  (`decrypt.rs:956-1000`). With `-a`, it needs all four OK responses; one `NotFound`, `Internal` or
  `Aborted` fails the run.
- **No gRPC deadlines** on the CLI's calls; the server cuts any call at `timeout_secs + 300` =
  660 s (`server.rs:121-128`).
- **Per-attempt bound.** Wrap each probe in `timeout 90` with `--max-iter 60`, and sleep 10 s between
  attempts (no busy-waiting). With `Test` parameters a healthy decryption takes seconds (to be
  confirmed in the first run).

## Is 300 s safe?

**Not when measured from the moment faults stop.** The SUT's own recovery path fits easily: pod
recreation and init (~10 s) + boot (unmeasured) + readiness (≤ 15 s) + keepalive (≤ 45 s) + back-off
(≤ 60 s) + probe (~10 s) ≈ 140 s plus boot. Two things outside the SUT's protocol can exceed it:

1. **Kubernetes back-off.** A core whose container crashed repeatedly during faults (for example,
   boot failing while MinIO was cut off) can be waiting out a `CrashLoopBackOff` of up to 300 s when
   faults stop. That alone uses the whole window, before boot starts.
2. **A pod stop landing just before faults stop** adds up to 30 s, and a slow boot can use up to the
   600 s startup budget legitimately.

**Recommendation (adopted in the catalog's Invariant):** keep the guarantee's 300 s, but start the
clock when all four cores accept connections again, and bound that wait separately at 600 s after
faults stop (300 s back-off cap + boot + readiness). Report both bounds through the one `Always`.
The quiet window must cover both: open it with `$ANTITHESIS_STOP_FAULTS 900`, or run the check as an
`eventually_` command (confirm in the Test Composer docs that faults are paused for it). The
simpler alternative is a single 600 s window from fault stop; it can't tell a slow Kubernetes
restart from slow MPC recovery, so the split is better for triage.

## Failure scenarios the property catches

- A restarted core boots and passes readiness, but peers never reconnect to it (dead channel not
  detected, back-off stuck), so every `-a` decryption times out on its share.
- A core comes back with its epoch or key missing (it answers `NotFound`), or refuses to serve after
  boot-time verification of public storage fails (#910-style digest mismatch after a reshare).
- A core wedged by clock jitter (timers that never fire) answers `Unavailable` forever.

## Known false-positive risks

- **The init container's CA fetch** (see
  [deployment-topology.md](../deployment-topology.md#known-deployment-hazards)): in the chart, a
  core pod started while MinIO is unreachable writes an invalid config and crash-loops until the
  pod is deleted again. The harness now retries the fetch (up to 600 s, then exits non-zero so
  kubelet retries). If a core still never comes back, check its init container's log for
  "no CA certificate for parties" before calling a failure.
- **Two overlapping pod faults** (more than t) are fine for this property, since it only judges the
  time after faults stop, but they make the 600 s readiness bound more likely to be tight.
- **The workload pod itself** must not be stopped or killed: its `/tmp` state is lost and the probe
  dies (excluded in the deployment roles).

## Implementation notes

- Key: the one `first_generate_key.sh` published; epoch: kms-init's (`DEFAULT_EPOCH_ID`), so a failed
  reshare can't make the probe fail.
- Readiness of the cores is probed by the CLI itself (a run that gets past connect). A cheap
  alternative is the `grpc_health_probe` binary in the `core-service-probe` image, which the
  client image may not have.
- `Sometimes(first attempt failed and a later one succeeded, …)` is the marker that a real
  recovery was exercised; without it, a passing `Always` may only mean nothing was broken.

## Instrumentation status

| Assertion | Location | Status |
|---|---|---|
| `Always(connected, "every core accepts client connections within 600 s after faults stop")` | [eventually_recovers_after_faults.sh](../../test/v1/public_decrypt/eventually_recovers_after_faults.sh) | present |
| `Always(ok, "public decryption answered by all four cores succeeds within 300 s of every core accepting connections")` | same | present |
| `Sometimes(rejoined, "a core the client could not connect to after faults stopped accepted connections again")` | same | present |
| `Sometimes(ok, "public decryption answered by all four cores succeeded after a failed first attempt once faults stopped")` | same | present |

Every assertion is in workload code (the control guarantee: no SUT patch), written with the
fallback SDK, and carries `{"guarantee": "guarantee-2", "property": "recovers-after-faults"}`.

- **Quiet period.** It is an `eventually_` command. The Test Composer reference
  (`/docs/product/writing_tests/test_templates/test_composer_reference/`, "Eventually command")
  says "All faults stop across all containers when an eventually command starts", other commands
  are killed and nothing runs alongside. The command also calls `$ANTITHESIS_STOP_FAULTS 1020`
  (`/docs/product/writing_tests/controlling_faults/pause_faults/`), in case the launcher's pod-fault
  injector doesn't follow the eventually phase; the two merge.
- **Probe.** `kms-core-client -l -a public-decrypt from-args` with the pod's four-core config, the
  workload's key (from `first_generate_key.sh`'s record, else MinIO) and the kms-init epoch; a
  fresh value of a random type per attempt, batch 1 or 2, async or `--sync`, `--max-iter 60`.
  Attempts are bounded by `timeout 90` (or the time left) and are 10 s apart.
- **Connect bound.** "Every core accepts connections" is the CLI getting through its connect to
  all four (it logs `Threshold Client setup done.` with `-l`). Measured from the command's start
  with `/proc/uptime`, which clock faults don't move. A core still down at 600 s fails it.
- **Decrypt bound.** 300 s from the start of the first attempt that connected (that attempt's
  connect happens within about a second of its start). A cluster that accepts connections but
  can't answer fails it, as does a core that goes down again and stays down.
- **Ambiguous outcomes.** A failed or timed-out attempt may still complete on the cores; nothing
  depends on it, and each attempt is a new request. A wrong result or failed authentication is
  reported through Guarantee 1's assertions and doesn't count as a success here.
- **Local check (no faults):** first attempt succeeds at +0 s. With core 3 scaled to 0 and back
  after 25 s: four attempts couldn't connect to party 3, the fifth (+46 s) connected and
  succeeded, and both `Sometimes` fired.
- **Harness fix for the CA-fetch hazard.** The core pods' init container now retries the peer CA
  fetch until it has all four certificates, so a core started while MinIO is unreachable no longer
  crash-loops with an empty certificate (see
  [deployment-topology.md](../deployment-topology.md#known-deployment-hazards)).

## Known closed issues

None recorded yet. Candidates from [system-brief.md](../system-brief.md#known-bugs-and-fixes): #887
(running party couldn't reach a restarted peer; keepalive added), #388 (instability when parties got
out of sync; active-session timeout added), #658 (networking deadlock), #834 (idle active sessions
evicted).
