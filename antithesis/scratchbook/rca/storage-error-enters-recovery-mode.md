# A storage outage at boot leaves a core in recovery mode, refusing every decryption

- **Finding name:** `storage-error-enters-recovery-mode`
- **Guarantee:** [Guarantee 2](../../../zama-kms/speedrun-report.md#guarantee-2): "the cluster serves decryptions again after faults stop"
- **Version:** Zama KMS v0.15.0-1 (`kms-server`), upstream [`4a644c85`](https://github.com/zama-ai/kms/commit/4a644c8546abc8b002b7e45c19bf195996e7d229) with Antithesis coverage instrumentation added (the tested build)
- **Summary in the report:** [the finding](../../../zama-kms/speedrun-report.md#storage-error-enters-recovery-mode)
- **The proposed fix:** [storage-error-enters-recovery-mode.patch](../../fixes/storage-error-enters-recovery-mode.patch) ([Fix](#fix))
- **Evidence:** [the failure write-up](../violations/storage-error-enters-recovery-mode.md), [the adversarial review](../adversarial/storage-error-enters-recovery-mode.md)

**Where it failed.** One failing timeline in run [`4e338bff`](https://zama.antithesis.com/report/z0DpS4BEFi0AtQY_3k2xQYil/WNeeUiIs3qYUlUd7UAiS1YdNQh8HKvhl2ofzq82Afa8.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA3OjA0OjQzLjEwMjAyODEzMloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV05lZVVpSXMzcVlVbFVkN1VBaVMxWWROUWg4SEt2aGwyb2Z6cTgyQWZhOC5odG1sIiwicmVwb3J0X2lkIjoiejBEcFM0QkVGaTBBdFFZXzNrMnhRWWlsIn19fZI8ndKJGsf6_PbNOmcRvP7XRP6CnD-8mfcqZYL0UYS8iuH35ePerg9wy7HvBDKR8Y_jV7R5W-saZjsBZoGotAo) ([run digest](../runs/hunt-current-3.md)).
The same boot-time decision appears once more in an earlier run of the same build (see
[across the runs](#across-the-runs)). The log links open the Antithesis logs explorer at that
moment of that timeline.

| Timeline | Core in recovery mode | Failure | Log |
|---|---|---|---|
| [Timeline A](#timeline-a) | kms-core-2 (party 2), after a kill and a reboot under network faults | "public decryption answered by all four cores succeeds within 300 s of every core accepting connections", at vtime 1405.56 | [log][a] |

The property's other counterexamples in this run come from one other checker execution, in which
the test machine stalled while the client was still encrypting its input, before it had contacted
any core. That one isn't a KMS failure
([review](../false-positives.md#recovery-check-attempt-outlives-timeout)), and recovery mode
doesn't appear in its history.

## Symptom

The checker's 27 attempts after faults stopped all failed with one of these two errors (the sync
or the async endpoint), and its summary was:

```text
1126.47  kms-core-client  Error: Only got 3/4 sync public decrypt responses, need at least 4
1147.10  kms-core-client  Error: Only 3/4 public decrypt requests succeeded, need at least 4
1405.56  kms-core-client  recovery: all cores accepted connections after 0 s; decryption ok=false after 27 attempt(s)
```

Each time, kms-core-2 refused the request outright:

```text
1126.14  kms-core-2  ERROR … kms_lib::engine::utils: core/service/src/engine/utils.rs:425: gRPC request failed
                     request_id=32ef25cb… operation="public_decrypt_request" code=The system is not in a state
                     required for the operation's execution error=Signing key is not present. This should only
                     happen when server is booted in recovery mode: No signing key available
1126.14  kms-core-2  ERROR … kms_lib::engine::server: core/service/src/engine/server.rs:114: Grpc error from KMS Core server: Code: 9
```

All four cores accepted connections within 14 s of faults stopping, and three of them decrypted and
signed every request. kms-core-2 answered every request with `FAILED_PRECONDITION` (code 9)
because it had booted in **recovery mode**, the state meant for a node that has lost its private
key material and is being restored from custodian backups. Its signing key was in fact in its
private storage the whole time. The node stayed in that state for the full 300 s window and would
have stayed there until someone restarted it, so any operation that needs all four parties (as the
checker's does) could not succeed, and the cluster was running one failure away from losing its
threshold.

## How the tests got there

In [Timeline A](#timeline-a):

| vtime | What happened | Command |
|---|---|---|
| 227.09–228.10 | The workload records the FHE key the probe uses (`96c7027d…`). | [`first_generate_key.sh`](../../../zama-kms/speedrun-tests.md#first_generate_key) |
| 228.10–1100.67 | Network partitions and clogs every few seconds (Stopped, Jammed, or Slowed by 1.6–2.6 s), clock jitter of about 0.5 s, and a pod fault about every 300 s. | fault injector |
| 690.62 | Kill kms-core-2. | fault injector |
| 691.85–862.89 | kms-core-2's replacement pod runs its init containers (`kms-gen-keys` finds the signing keys already there at 862.61) and starts `kms-server` at 862.89. | kms-core-2 |
| 914.44–921.96 | kms-core-2's boot reads its `SigningKey` and `SigningSeed` from MinIO without error (the 0.15 migration step). | kms-core-2 |
| 1047.6–1089.6 | Partitions separating kms-core-2 from MinIO at 1053.09, 1067.74, 1073.32, 1074.92, 1079.90 and 1085.75 (the last one separates all four cores from MinIO for up to 6.7 s), plus clogs on kms-core-2. | fault injector |
| 1089.59–1089.64 | The boot's listing of the `SigningKey` folder fails with "dispatch failure", and `kms-server` enters recovery mode. | kms-core-2 |
| 1100.66–1100.67 | The checker starts and faults stop. | [`eventually_recovers_after_faults.sh`](../../../zama-kms/speedrun-tests.md#eventually_recovers_after_faults) |
| 1100.77–1100.82 | kms-core-2 finishes booting without a signing key, reads its `SigningKey` without error while verifying its context, and starts serving. | kms-core-2 |
| 1100.69–1395.55 | 27 decryption attempts, 10 s apart; kms-core-2 refuses all 27 with code 9. | [`eventually_recovers_after_faults.sh`](../../../zama-kms/speedrun-tests.md#eventually_recovers_after_faults) |
| 1405.56 | The `Always` fails and the checker exits 1. | [`eventually_recovers_after_faults.sh`](../../../zama-kms/speedrun-tests.md#eventually_recovers_after_faults) |

## What the logs show

<a id="timeline-a"></a>
### Timeline A: kms-core-2 boots in recovery mode after a network error on its signing-key read

[Timeline A in the logs explorer][a], at the failing check.

```text
 690.62  fault_injector  kill kms-core-2-core-2
 862.61  kms-core-2 (kms-core-init-gen-keys)  WARN kms_gen_keys: core/service/src/bin/kms-gen-keys.rs:477:
                         Signing keys already exist, skipping generation
 914.44  kms-core-2  INFO …s3.rs:111: Checking if object exists in bucket kms-private under key PRIV-p2/SigningKey/60b7070a…
 919.25  kms-core-2  INFO …s3.rs:247: Reading object from bucket kms-private under key PRIV-p2/SigningKey/60b7070a…
 921.96  kms-core-2  INFO …s3.rs:247: Reading object from bucket kms-private under key PRIV-p2/SigningSeed/60b7070a…
1047.61  kms-core-2  INFO …s3.rs:111: Checking if object exists in bucket kms-public under key PUB-p2/VerfAddress/60b7070a…
1085.75  fault_injector  partition, Stopped, asymmetric: {kms-core-1…4, client} | {minio, …}, up to 6.7 s
1089.59  kms-core-2  WARN kms_lib: core/service/src/lib.rs:73: Warning in core/service/src/vault/storage/crypto_material/utils.rs:403:13:
                     Failed to read SigningKey from "S3 storage with bucket kms-private": Getting all ids failed: dispatch failure
1089.63  kms-core-2  WARN kms_lib::engine::backup_operator: core/service/src/engine/backup_operator.rs:860: Error loading signing key: …
1089.64  kms-core-2  WARN kms_lib::engine::backup_operator: core/service/src/engine/backup_operator.rs:861:
                     SIGNING KEY NOT AVAILABLE, ENTERING RECOVERY MODE!!!!
1089.65  kms-core-2  INFO …s3.rs:247: Reading object from bucket kms-public under key PUB-p2/VerfKey/60b7070a…
1100.67  fault_injector  restore; paused: true
1100.77  kms-core-2  WARN kms_lib::engine::base: core/service/src/engine/base.rs:1131: Initializing KMS without a signing key.
                     ONLY BACKUP RECOVERY OPERATIONS WILL BE POSSIBLE.
1100.77  kms-core-2  WARN kms_server: core/service/src/bin/kms-server.rs:638: No TLS identity - using plaintext communication between MPC nodes
1100.81  kms-core-2  WARN …kms_impl.rs:670: No signing key available (recovery mode): skipping private storage verification, the
                     public material sync from peers, and public material and recovery validation material verification
1100.82  kms-core-2  INFO …s3.rs:247: Reading object from bucket kms-private under key PRIV-p2/SigningKey/60b7070a…
1100.82  kms-core-2  INFO …s3.rs:247: Reading object from bucket kms-private under key PRIV-p2/SigningSeed/60b7070a…
1100.82  kms-core-2  INFO kms_lib::engine::server: core/service/src/engine/server.rs:139: Starting KMS core on socket 0.0.0.0:50100
1126.14  kms-core-2  ERROR …utils.rs:425: gRPC request failed … error=Signing key is not present. This should only happen when
                     server is booted in recovery mode: No signing key available
1126.44  kms-core-1  INFO kms_lib::engine::base: core/service/src/engine/base.rs:1023: Signing public decryption result for 1 plaintexts
                     and 1 external handles                                    (the same on kms-core-3 and kms-core-4)
1126.47  client      Error: Only got 3/4 sync public decrypt responses, need at least 4
   …     (26 more attempts, the same on every core, the last at 1395.55)
1360.69  kms-core-1  ERROR …sending_service/service.rs:272: No more listeners on SingleSet(2), everything failed, 1 errors,
                     shutting down network task
1405.56  client      recovery: all cores accepted connections after 0 s; decryption ok=false after 27 attempt(s)
```

What this shows:
- **The key was never lost.** The same `kms-server` process read `PRIV-p2/SigningKey` and
  `SigningSeed` without error at 919.25–921.96, and read them again at 1100.82, 11 s after it had
  decided it had no signing key (this second read is the context verification at startup). The
  init container had also found the keys at 862.61.
- **The read failed because MinIO was unreachable.** After the previous storage call at 1047.61,
  the next one, the listing of the `SigningKey` folder, failed at 1089.59 with "dispatch failure"
  (the S3 client could not get the request through). In the meantime six partitions had separated
  kms-core-2 from MinIO, the last at 1085.75.
- **The server took a storage error for a lost key.** It logged the error (1089.63) and entered
  recovery mode at once (1089.64): no retry and no exit. Public storage answered a few ms later
  (1089.65), so the recovery-mode boot completed. kms-core-2 stayed at restart_count 0, in recovery
  mode, until the end of the timeline. It also dropped the TLS identity configured for
  party-to-party traffic: its "No TLS identity" line at 1100.77 is the only one in the history.
- **Recovery mode looks healthy from outside.** kms-core-2 served on 0.0.0.0:50100 from 1100.82 and
  passed readiness, so the checker's connection check passed as soon as the last core was up
  (within 14 s of faults stopping), and Kubernetes had no reason to restart it. It then refused all 27 requests with code 9
  (1126.14–1395.52), while kms-core-1, -3 and -4 each signed 27 results.
- **The peers give up on party 2.** kms-core-1, -3 and -4 log 7 "No more listeners on
  SingleSet(2)" lines between 1360.69 and 1405.11, as their sends to party 2 time out.

<a id="across-the-runs"></a>
**Across the runs.** Searches for the failed signing-key read ("Failed to read SigningKey") over
every timeline of this run and of an earlier 4-hour run of the same build without timing fuzzing
([run `8196fb3c`](https://zama.antithesis.com/report/RQ8Cbp-xGNyv2LzRK7QJhdaS/Q4j24Mga4r9vKq6G1GGKGJhmWP0f7ZtlCtPmgF4J-dU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUTRqMjRNZ2E0cjl2S3E2RzFHR0tHSmhtV1AwZjdadGxDdFBtZ0Y0Si1kVS5odG1sIiwicmVwb3J0X2lkIjoiUlE4Q2JwLXhHTnl2Mkx6Uks3UUpoZGFTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjUyOjUyLjkwNzU2NjUzOVoiffXOyyh90TorAK1eQ08RnDaqV3Hiuf4ZXbyxANa4Qh-8Ku_qk3g7JPpHFH0alZBWKDgpmQ1bzWKzpgv7_81JSwI))
show the read failing at boot in five boots, always with "dispatch failure" while the key was in
storage. What the server did depended only on where in the boot the read happened:

| Run | Core, vtime | Where the read failed | What the server did |
|---|---|---|---|
| `4e338bff` | kms-core-4, 1278.14–1280.35 (in several branches) | the 0.15 migration step ("Could not complete migration", `kms-server.rs:536`) | exited ("Error: …"), restarted by Kubernetes |
| `4e338bff` | kms-core-2, 1089.59 (Timeline A) | `boot_base_kms` | entered recovery mode |
| `8196fb3c` | kms-core-2, 549.38–549.61 | the migration step ("Unencrypted load failed: dispatch failure") | exited, restarted |
| `8196fb3c` | kms-core-1, 640.78 | the migration step | exited, restarted |
| `8196fb3c` | kms-core-1, 912.49 ([logs explorer][b]) | `boot_base_kms` ("Getting all ids failed: dispatch failure") | entered recovery mode |

- Both times the read failed in `boot_base_kms`, the server entered recovery mode. Neither run has
  any other "Error loading signing key" or "ENTERING RECOVERY MODE" event.
- Other boot-time storage errors end the process instead, and Kubernetes restarts it: this run
  has 2,275 `kms-core` container exits with code 1, the outcome of a failed boot. In run `8196fb3c`'s history, kms-core-2 exited on a failed key-share
  read ("Error: reading failed for FheKeyInfo … streaming error") at 909.53, three seconds before
  kms-core-1 entered recovery mode.
- In run `8196fb3c` no request was refused for a missing signing key (0 "Signing key is not
  present" events). The history the search found ends at 912.49, and no later request reached that core
  while it was in recovery mode. In this run, all 331 such refusals are on kms-core-2, between 1121.9 and 1395.5.

## Root cause

At boot, `kms-server` loads its signing key from private storage (here S3 on MinIO). If that load
fails **for any reason**, the server concludes that the node has lost its key and boots in
recovery mode. That includes a network error on the listing or on the read, not just an empty
`SigningKey` folder. Recovery mode is meant for an operator restoring a wiped node from custodian
backups: the node has no signing identity, refuses every operation that signs (public and user
decryption among them), skips its storage verification and the peer sync, and loads its identity
only at boot, so it stays in recovery mode until it restarts ([backup.md](../../../docs/guides/backup.md), line 253).
The process stays up and passes readiness, so nothing restarts it. A few seconds of storage outage
at the wrong moment of a boot therefore takes a healthy party out of every signing operation
indefinitely. Other boot-time reads, including the same signing-key read a few steps earlier,
fail the boot and get retried by Kubernetes, which recovers.

Precisely, at the tested commit:

1. `kms-server` boots through [`boot_base_kms`](../../../core/service/src/bin/kms-server.rs#L599-L607).
2. [`boot_base_kms`](../../../core/service/src/engine/backup_operator.rs#L850-L872) matches on
   [`get_core_signing_identity`](../../../core/service/src/engine/backup_operator.rs#L857) and puts
   **every** error in the recovery-mode arm
   ([lines 859–869](../../../core/service/src/engine/backup_operator.rs#L859-L869)): it logs
   "Error loading signing key", then "ENTERING RECOVERY MODE", and boots with
   `BaseKmsStruct::new_no_signing_key`.
3. [`get_core_signing_identity`](../../../core/service/src/vault/storage/crypto_material/utils.rs#L433-L449)
   reads the key through [`get_unique`](../../../core/service/src/vault/storage/crypto_material/utils.rs#L392-L421),
   which calls [`read_all_data_versioned`](../../../core/service/src/vault/storage/mod.rs#L762-L784):
   list the folder ([line 769](../../../core/service/src/vault/storage/mod.rs#L769)), then read each
   entry. A failed listing ("Getting all ids failed", [vault/mod.rs:338-341](../../../core/service/src/vault/mod.rs#L338-L341)),
   a failed read ("Unencrypted load failed", [vault/mod.rs:312-316](../../../core/service/src/vault/mod.rs#L312-L316)),
   a failed seed read, and an empty folder ("should contain exactly one entry, but contains 0
   entries", [utils.rs:410-417](../../../core/service/src/vault/storage/crypto_material/utils.rs#L410-L417))
   all come back as the same `anyhow::Error`. `boot_base_kms` cannot tell "absent" from
   "unreadable", and does not try.
4. [`recovery_mode_verf_key`](../../../core/service/src/engine/backup_operator.rs#L817-L843) only
   needs public storage to answer once (it did, at 1089.65), so the boot completes in recovery
   mode.
5. From then on, every signing request goes through
   [`signing_identity_for`](../../../core/service/src/engine/utils.rs#L154-L180), which turns
   [`BaseKmsStruct::signing_identity`](../../../core/service/src/engine/base.rs#L1148-L1153)'s
   "No signing key available" into `FAILED_PRECONDITION`. Threshold startup
   [skips the private-storage verification and the peer sync](../../../core/service/src/engine/threshold/service/kms_impl.rs#L669-L675),
   and `kms-server` [builds no TLS identity](../../../core/service/src/bin/kms-server.rs#L607)
   for party-to-party traffic.
6. By contrast, the 0.15 migration that runs earlier in the same boot
   ([migration.rs:242-252](../../../core/service/src/engine/migration.rs#L242-L252)) first asks
   whether the key exists and propagates every storage error with `?`. `kms-server`
   [returns the error](../../../core/service/src/bin/kms-server.rs#L529-L536) and the process
   exits, which is the outcome in three of the five boots above. The operations guide also
   describes recovery mode as what happens when the `SigningKey` "is absent"
   ([troubleshooting.md](../../../docs/operations/advanced/troubleshooting.md), lines 218–221).

## Fix

**The patch:** [storage-error-enters-recovery-mode.patch](../../fixes/storage-error-enters-recovery-mode.patch)

`boot_base_kms` now enters recovery mode only when private storage positively shows the key is
gone. When loading the signing identity fails, it lists the `SigningKey` folder itself:

- the listing succeeds and is **empty**: the node has lost its key, and it boots in recovery mode
  exactly as before (same logs, same verification-key selection);
- the listing succeeds and **holds a key**: the key is there but could not be read, so the boot
  fails with the original error plus "Private storage holds a signing key that could not be
  loaded; not entering recovery mode";
- the listing **fails**: the boot fails with both errors and "not entering recovery mode".

A failed boot exits the process like every other boot-time storage error, and Kubernetes restarts
it, so the node comes back under its own key once storage answers. This covers each way the
load can fail in step 3 above. A failed listing or read of the key, a failed seed read, and a
keychain or decryption failure on an encrypted vault are all either a failed listing or a listing
that still shows the key, so none of them can lead to recovery mode any more. Only an empty folder
can. This matches the documented recovery flow, which starts from empty private storage
([backup.md](../../../docs/guides/backup.md), Phase 4, lines 230–232). One behaviour changes on
purpose: a node whose key object is present but permanently unreadable (for example a corrupted
object) now fails to boot with that error, instead of silently dropping into recovery mode. An
operator who really means to recover such a node removes the object first.

The patch adds a unit test next to the existing recovery-mode test in the same module,
`engine::backup_operator::tests::boot_base_kms_does_not_enter_recovery_mode_when_the_signing_key_is_unreadable`
(crate `kms`, library `kms_lib`). It boots against a private-storage reader that holds the node's
signing key but whose reads fail with "dispatch failure", first with the listing working and then
with it failing too, while public storage holds a verification key (so recovery mode would have a
key to boot under). Both boots must fail. A last boot against the same storage, now readable, must
come up under the node's key. Without the fix, both failing boots succeed in recovery mode and the
test fails. The existing `boot_base_kms_enters_recovery_mode_without_a_signing_key` still covers
the empty-storage case, which is unchanged.

**How it was checked:** **By a unit test, not by an Antithesis run.** The bug showed up once per run at most, so a fix-check run long enough to say anything wouldn't have reported before our deadline. In the [log](../logs/unit-test-storage-error-enters-recovery-mode.txt), the patch's new test, `boot_base_kms_does_not_enter_recovery_mode_when_the_signing_key_is_unreadable`, **fails** on the tested build with only the test added ("a node whose signing key could not be read must not boot in recovery mode"), and **passes** with the fix. With the fix, every test in `engine::backup_operator` and every test with "recovery" in its name passes (50 of 50, the new test included), and so does every custodian backup-recovery test (23 of 23, run separately), including those that start a node with no signing material. Run with `cargo test -F testing -p kms --lib` in the project's Rust 1.98.1 build image, after generating test material with `generate-test-material --profile insecure --parties 4`.


## Comparison with upstream

This is a new finding, so there is no upstream fix to compare with. The analysis above was done
before this section was written.

- **Known upstream?** Not that we found. A search of the public
  [zama-ai/kms](https://github.com/zama-ai/kms) issues and pull requests for "recovery mode",
  "ENTERING RECOVERY MODE" and `boot_base_kms` finds no report of it. The pull request that
  introduced recovery mode, [#468](https://github.com/zama-ai/kms/pull/468) ("allow starting
  without signing key in recovery mode"), describes it as the path for a node started "with an
  empty private storage in order to do recovery from a backup", which is the case the patch keeps.
- **Still on the latest `main`?** Yes, by reading the code: `boot_base_kms` at
  [`f0258b8a`](https://github.com/zama-ai/kms/blob/f0258b8ade070f33e574e7ffde96988b0e94649a/core/service/src/engine/backup_operator.rs#L850-L872)
  (2026-10-16) is unchanged from the tested build. We didn't build or test `main`.
- **Suggested upstream issue** (not filed):
  - Title: *kms-server boots into recovery mode when its signing key can't be read transiently*
  - A transient private-storage error while `boot_base_kms` reads the signing key (e.g. an S3
    "dispatch failure" during a network blip) is treated as a lost key: the core boots in
    recovery mode, keeps passing its health checks, and refuses every decryption until someone
    restarts it. Only an empty key listing should lead to recovery mode; other errors should fail the boot.

[a]: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTQwNS41NTYxNDgyMjQ1MTAzIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii03MzUzOTUwNjk0OTIwNzU0NjQ3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ
[b]: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiOTEyLjQ5MDE1NTEyOTY5MzQifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTU2NjM5NzIxODA4OTQwMTE3NjcifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMjhkNWU1YjY2NjM5ZDI0MDlkN2YwMzZkZTk1MjM3OGUtNjQtNCJ9
