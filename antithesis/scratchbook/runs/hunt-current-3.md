# hunt-current-3 · 4e338bff64a6f329ebadc856cace0692-64-4 · current@3095d82a · completed · 105 m
Report: [triage report](https://zama.antithesis.com/report/z0DpS4BEFi0AtQY_3k2xQYil/WNeeUiIs3qYUlUd7UAiS1YdNQh8HKvhl2ofzq82Afa8.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA3OjA0OjQzLjEwMjAyODEzMloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV05lZVVpSXMzcVlVbFVkN1VBaVMxWWROUWg4SEt2aGwyb2Z6cTgyQWZhOC5odG1sIiwicmVwb3J0X2lkIjoiejBEcFM0QkVGaTBBdFFZXzNrMnhRWWlsIn19fZI8ndKJGsf6_PbNOmcRvP7XRP6CnD-8mfcqZYL0UYS8iuH35ePerg9wy7HvBDKR8Y_jV7R5W-saZjsBZoGotAo)

Session `88ceb1add6b037b42548b98e799583e4-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, one pod fault about every 300 s, MinIO and the client pod excluded from pod faults), no strobing quiet windows (`strobe_quiet_max_seconds` 0, as in [hunt-current-1](hunt-current-1.md) and [hunt-current-4](hunt-current-4.md); [hunt-current-2](hunt-current-2.md) had strobing), plus `custom.timing_fuzzing=true`, the first run with timing fuzzing. Completed 08:04:43Z. Property list: [props-4e338bff.ndjson](../logs/props-4e338bff.ndjson); run details: [show-4e338bff.json](../logs/show-4e338bff.json).

66 properties: 57 pass, 9 fail. **A Guarantee 2 property fails on the current build**: "public decryption answered by all four cores succeeds within 300 s of every core accepting connections" has 48 counterexamples, and the checker's exit-code property has 80. They come from two separate checker runs. In the triaged one, kms-core-2 boots while network faults are active. Reading its signing key from MinIO fails with "dispatch failure", and the core then starts in "recovery mode" with no signing key. After faults stop, it accepts connections but refuses every decryption with gRPC code 9 for the whole 300 s window. The other three cores answer every attempt. Every other guarantee property passes, and every Reachable and Sometimes marker was hit.

The other failures are Antithesis defaults:
- one Antithesis error, a guest timeout in another timeline;
- a coredns exit with code 2 and a systemd-journald abort, also in other timelines;
- a new init-container exit: `kms-core-init-load-env` exits 1 when the harness's 600 s CA-certificate fetch bound runs out;
- the three known container exits.

"Peak memory usage", which failed in all four 4-hour hunts, passes here (191,871 examples, 0 counterexamples).

Setup and instrumentation are fine. There is no explicit setup-complete property. Setup finished: the test composer received its first input and ran `first_generate_key.sh` at vtime 227.09–228.10 in the triaged history, and "All commands were started at least once", "All commands were run to completion at least once" and "workload generated an FHE key" all pass. "Software was instrumented" lists kms-server (970,574 locations), kms-gen-keys (394,465), kms-core-client (348,094) and kms-init (143,553). "Every instrumented module has symbols" passes, and thread pausing ran in all 9 kms containers.

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 22584 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4672 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5414 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5973 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3016 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 8105 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4904 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2666 | 3039 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 881 | 1303 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 9307 | 0 |
| **public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always)** | [Guarantee 2](../guarantees.md#guarantee-2) | **failing** | 9312 | 48 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 479 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 621 | 80 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2599 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 13866 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 4293 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 13482 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 2599 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 26275 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 12427 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 26374 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 12472 | 6524 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 2517 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 12149 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 822 | 1141 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2544 | 1576 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4844 | 1241 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 5357 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4948 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3154 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3149 | 0 |
| workload generated an FHE key (Reachable; setup / bootstrap) | — | hit | 7840 | 0 |
| All commands were started at least once (setup / bootstrap) | — | passing | 1 | 0 |
| All commands were run to completion at least once (setup / bootstrap) | — | passing | 1 | 0 |
| Commands finish with zero exit code: anytime_reshare_key.sh, first_generate_key.sh, parallel_driver_public_decrypt.sh, parallel_driver_user_decrypt.sh | — | passing | 28343 / 7840 / 16237 / 13457 | 0 |
| **Commands finish with zero exit code: public_decrypt/eventually_recovers_after_faults.sh** | [Guarantee 2](../guarantees.md#guarantee-2) (its checker) | **failing** | 9355 | 80 |
| **No Antithesis errors** (Antithesis default) | — | **failing** (new) | 0 | 1 |
| **No unexpected container exits: container: coredns, namespace: kube-system , exit code: 2** (Antithesis default) | — | **failing** (new) | 0 | 1 |
| **No unexpected crashes: systemd-journald** (Antithesis default) | — | **failing** (new) | 0 | 2 |
| **No unexpected container exits: container: kms-core-init-load-env, namespace: kms-threshold-staging , exit code: 1** (Antithesis default) | — | **failing** (new) | 0 | 16 |
| **No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101** (Antithesis default) | — | **failing** ([suspect](../false-positives.md#boot-panic-port-in-use)) | 0 | 155 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 2275 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 209 |
| Peak memory usage (Antithesis default) | — | passing (failed in all four 4-hour hunts) | 191871 | 0 |
| Other Antithesis defaults (instrumentation, symbols, thread pausing, build, fault injector, parallelism, software versions, session errors) | — | passing | — | — |

The Sometimes markers with counterexamples pass. A Sometimes property needs only one true evaluation, and the false ones are the cases where the condition didn't apply.

## Failing: public decryption answered by all four cores succeeds within 300 s of every core accepting connections
This is an Always for [Guarantee 2](../guarantees.md#guarantee-2), checked by [eventually_recovers_after_faults.sh](../../test/v1/public_decrypt/eventually_recovers_after_faults.sh) ([property file](../properties/recovers-after-faults.md)). It has 48 counterexamples and 9312 examples. It passed in [hunt-current-1](hunt-current-1.md), [hunt-current-2](hunt-current-2.md) and [hunt-current-4](hunt-current-4.md). Before this run it had failed only on the pre-fix build ([prefix-recovery-fails-after-core-restart](../false-positives.md#prefix-recovery-fails-after-core-restart)). The failure here looks different: the restarted core refuses requests outright and never takes part in the MPC.
- moment: input_hash=-7353950694920754647 vtime=1405.5561482245103
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTQwNS41NTYxNDgyMjQ1MTAzIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii03MzUzOTUwNjk0OTIwNzU0NjQ3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ)
- log: [hunt-current-3-g2decrypt-7353950694920754647.ndjson](../logs/hunt-current-3-g2decrypt-7353950694920754647.ndjson) (full history, root to 1405.558, the checker's exit; 14,407 events). The same log covers the checker's exit-code property below.
- timeline:
  - 227.09–228.10 · setup ends. The test composer runs `first_generate_key.sh`, which finishes with exit 0. The fault injector unpauses at 228.10 and stays unpaused until 1100.67: no quiet window, because strobing is off.
  - 228.10 → 1100.67 · fault_injector:
    - Network clogs and partitions every few seconds: Stopped, Jammed, or Slowed with 1.6–2.6 s mean latency.
    - Clock jitter of about 0.5 s.
    - Nine pod faults: kill kms-core-3 at 260.31, stop kms-core-2 at 300.33, stop kms-core-1 at 323.34, stop kms-core-4 at 390.37, stop kms-core-2 at 460.42, kill kms-core-2 at 690.62, kill kms-core-3 at 738.67, stop kms-core-4 at 859.82, stop kms-core-1 at 1068.96.
  - 237.27 → 701.63 · test composer: "set parallelism limit to 0" at 237.27. Only 8 workload commands run in this history: 6 public-decryption drivers and 2 reshares, all exit 0 by 701.63. No command runs from 701.63 to 1100.66, and the composer reports no `hit_mem_limit`.
  - 390 → 1100 · while faults are active, replacement pods recover slowly:
    - init containers take 40–250 s;
    - kms-server boots take 160–240 s, because each S3 read takes 1–41 s.
    - After the kill of kms-core-3 at 738.67, no core logs "Starting KMS core on socket" until 1100.82, so no core is serving clients in that span.
  - 690.62 → 862.89 · kms-core-2 restarts after the kill at 690.62:
    - `kms-core-init-load-env` runs 691.85–714.10;
    - `kms-core-init-gen-keys` runs 714.73–862.61;
    - kms-server starts at 862.89 (restart_count 0) and spends the next 238 s reading its private and public material from MinIO.
  - 1085.75 · fault_injector: an asymmetric Stopped partition (6.7 s) cuts all four cores and the client off from MinIO.
  - 1089.59 · kms-core-2: `Failed to read SigningKey from "S3 storage with bucket kms-private": Getting all ids failed: dispatch failure`.
  - 1089.64 · kms-core-2: "SIGNING KEY NOT AVAILABLE, ENTERING RECOVERY MODE!!!!" (`backup_operator.rs:861`). The code path is `boot_base_kms` in [backup_operator.rs](../../../core/service/src/engine/backup_operator.rs) (about line 850). Any error from `get_core_signing_identity` sends the server to `new_no_signing_key` instead of ending the process.
  - 1100.66 · test composer: starts `eventually_recovers_after_faults.sh` and logs "killing running drivers and running Eventually command". **Faults stop at 1100.67:** `fault_injector --pause` returns 0, then a `restore` and `paused: true`. This is the start of the checker's quiet period.
  - 1100.77–1114.60 · when each core accepts connections:
    - kms-core-2 logs "Initializing KMS without a signing key. ONLY BACKUP RECOVERY OPERATIONS WILL BE POSSIBLE." (1100.77) and starts serving on 0.0.0.0:50100 at 1100.82;
    - kms-core-4: new kms-server 1108.15, serving 1108.31;
    - kms-core-1: its init container waited for CA certificates from 1069.69 to 1109.29, then kms-server 1111.12, serving 1111.29;
    - kms-core-3: serving at 1114.60, at the end of a boot that began at 950.03.
    - Boots after faults stop take about 0.2 s.
    - The checker's attempt 1 starts at 1100.69 and connects to all four cores (connect_wait_s 0).
  - 1126.13 → 1395.55 · checker: 27 attempts, 10 s apart. Attempt 1 returns at 1126.47 and every later one fails within about 0.3 s:
    - 18 sync attempts end with "Error: Only got 3/4 sync public decrypt responses, need at least 4".
    - 9 async attempts end with "Error: Only 3/4 public decrypt requests succeeded, need at least 4".
    - For each request, kms-core-2 logs `gRPC request failed … code=The system is not in a state required for the operation's execution error=Signing key is not present. This should only happen when server is booted in recovery mode: No signing key available` and "Grpc error from KMS Core server: Code: 9".
    - kms-core-1, -3 and -4 run each decryption among themselves and sign the results ("Signing public decryption result …"). None of them logs an error or a timeout for these requests.
  - 1360.69 → 1405.11 · kms-core-1, -3 and -4: 7 lines of "No more listeners on SingleSet(2), everything failed, 1 errors, shutting down network task" (`sending_service/service.rs:272`). Their message tasks to party 2 give up, because party 2 never joined a session.
  - 1100.67 → 1405.56 · kms-core-2 stays at restart_count 0 and in recovery mode. In that span no core restarts, panics, or logs a "deadline" or "timeout" line. The history also has no coredns or MinIO restart, no process crash, and no Antithesis error.
  - 1405.556 · checker assertions:
    - connect Always: true (connect_wait_s 0);
    - this decrypt Always: false;
    - Sometimes "…succeeded after a failed first attempt once faults stopped": false.
    - Message: "recovery: all cores accepted connections after 0 s; decryption ok=false after 27 attempt(s)". The command exits 1 at 1405.558 (runtime 304.9 s).
- details: `{"attempts":27,"failed_attempts":27,"connect_wait_s":0,"decrypt_wait_s":305,"decrypt_bound_s":300,"elapsed_s":305,"last_unreached_party":"","last_attempt":{"attempt":27,"started_after_s":294,"data_type":"euint256","batch":1,"sync":false,"connected":true,"exit_code":1,"key_id":"96c7027d6ec858046e94b6c9fb8479bc5860c76c757eefe9716025328117049e","value_hex":"7775d722…4f69d97","error":"…Encrypting plaintext: TypedPlaintext { bytes: [119, 117, …"}}`. The `error` field stops partway through the CLI's "Encrypting plaintext" line. The checker's output shows the actual error line: "Error: Only 3/4 public decrypt requests succeeded, need at least 4".

### Guarantee 2: where the 48 counterexamples come from
These counts come from a run-wide search for this assertion with `hit` and `condition: false` (48 events, under the cap, so the list is complete) and from a search for the checker's non-zero exits (80 events, complete). No logs were downloaded for this.
- 48 counterexamples, 48 distinct input_hashes, from **two checker executions**:
  - **Execution A**, 1 counterexample: vtime 1405.5561482245103, the one triaged above. The checker started at 1100.66.
  - **Execution B**, 47 counterexamples: vtime 1568.7049745654222; 1570.5002876643557, 1570.5002882338595, 1570.5002950679045; 1570.6978561654687 (×2); 1571.284192723455; 1571.3426956476178; 33 between 1571.352467671968 and 1571.3527611782774; 1571.3975429285783; 1571.5472653412726 (×5); 1571.547266160138.
    - All 47 carry identical details, including the CLI timestamp `06:26:59.162273Z` in the error. So they are one checker execution (started by the composer at vtime 1196.5) that Antithesis branched afterwards.
    - Details: `attempts 2, failed_attempts 2, connect_wait_s 49, decrypt_wait_s 310, elapsed_s 359, last_unreached_party "2"`, last attempt `{attempt 2, started_after_s 49, sync true, euint160, batch 2, key_id 28152d8c…, connected true, exit_code 143, error "… Terminated"}`.
    - So party 2 refused the first attempt's connection, the second attempt connected at +49 s, and that attempt never returned. It ended "Terminated" with exit 143.
    - Open point: `timeout 90` should have ended attempt 2 by about +139 s, but the window only closed at +359 s with no third attempt. That isn't explained without B's log.
    - Whether kms-core-2 was in recovery mode in B's timeline is not established. A run-wide search finds "ENTERING RECOVERY MODE" exactly once in the whole run, at 1089.64 on kms-core-2, in execution A's ancestry. All 331 "Signing key is not present" events are on kms-core-2, at vtime 1121.9–1395.5. B's last attempt hung, where a recovery-mode core refuses at once.
    - Moment for a follow-up: input_hash=-453276507424875132 vtime=1568.7049745654222 ([log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTU2OC43MDQ5NzQ1NjU0MjIyIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii00NTMyNzY1MDc0MjQ4NzUxMzIifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiODhjZWIxYWRkNmIwMzdiNDI1NDhiOThlNzk5NTgzZTQtNjQtNCJ9)).
- The checker's 80 non-zero exits: 1 from execution A (1405.56, runtime 304.9 s) and 79 from execution B's branches (1581.61–1920.08, runtime 385–724 s, all started at 1196.5).

## Failing: Commands finish with zero exit code: public_decrypt/eventually_recovers_after_faults.sh
80 counterexamples, 9355 examples. The [Guarantee 2](../guarantees.md#guarantee-2) checker exits 1 when its decryption check fails. Its counterexamples are the same two executions as above (1 from A, 79 from B).
- moment: input_hash=-7353950694920754647 vtime=1405.5580317366403
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTQwNS41NTgwMzE3MzY2NDAzIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii03MzUzOTUwNjk0OTIwNzU0NjQ3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ)
- log: [hunt-current-3-g2decrypt-7353950694920754647.ndjson](../logs/hunt-current-3-g2decrypt-7353950694920754647.ndjson) (the same history as above)
- timeline: the same as above. The checker started at 1100.66, its last attempt failed at 1395.55, the assertions ran at 1405.556, and the command exited 1 at 1405.558.
- details: none; the exit event carries `command_return_code` 1 and `command_runtime` 304.9 s.

## Failing: No Antithesis errors
1 counterexample.
- moment: input_hash=-5856226207055342701 vtime=1852.129124834668
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTg1Mi4xMjkxMjQ4MzQ2NjgifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTU4NTYyMjYyMDcwNTUzNDI3MDEifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiODhjZWIxYWRkNmIwMzdiNDI1NDhiOThlNzk5NTgzZTQtNjQtNCJ9)
- log: [hunt-current-3-antithesis-error-5856226207055342701.ndjson](../logs/hunt-current-3-antithesis-error-5856226207055342701.ndjson) (root to 1838.76; 17,333 events). The error event at 1852.13 isn't in the stream; a search on the moment's input_hash found it.
- timeline:
  - 227.09 · this history splits from the Guarantee 2 history at the first test-composer input, so the two share only setup.
  - 228.20 → 1681.34 · faults with no quiet window. The only pod fault is a kill of kms-core-4 at 267.31.
  - 650 → 1700 · log volume falls to about 1–5 events/s.
  - 1277.70–1324.10 · the four kms-cores' last lines: reshare (NewMpcEpoch) requests. kms-core-2, -3 and -4 log "Grpc error from KMS Core server: Code: 13" for one reshare, and kms-core-1 is reading from S3. **No core logs anything after 1324.10**, 528 s before the error.
  - 1676.19 last SDK assertion; 1681.34 last fault-injector event; 1688.13 last workload line (`anytime_reshare_key.sh`, "source epoch check, attempt 2/2"); 1690.14 last coredns line (an upstream DNS timeout for `minio.`).
  - 1695.93 → 1838.76 · local-path-provisioner: "Failed to watch … Get "https://10.43.0.1:443/api/v1/…": net/http: TLS handshake timeout". The Kubernetes API server no longer completes TLS handshakes.
  - 1700 → 1852 · 14 events in 152 s; test-composer lines arrive 24–44 s apart (1707.50, 1731.78, 1761.87, 1805.33).
  - 1822.04 · a new fuzzer input (the fault injector reseeds).
  - 1852.13 · the Antithesis error.
- details: `"antithesis_error":"state_cant_be_materialized (guest timed out)","guest_timed_out":true,"guest_stopped":true,"guest_exit_code":-11000`. The guest VM stopped making progress in this timeline. This is 447 s of vtime after the Guarantee 2 failure, in a timeline unrelated to it.

## Failing: No unexpected container exits: container: coredns, namespace: kube-system , exit code: 2
1 counterexample, 0 examples. New: in [hunt-current-2](hunt-current-2.md), coredns restarted but never exited with a code that this property flagged.
- moment: input_hash=1396279730201570877 vtime=1178.5607261131518
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTE3OC41NjA3MjYxMTMxNTE4In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6IjEzOTYyNzk3MzAyMDE1NzA4NzcifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiODhjZWIxYWRkNmIwMzdiNDI1NDhiOThlNzk5NTgzZTQtNjQtNCJ9)
- log: [hunt-current-3-coredns-exit2-1396279730201570877.ndjson](../logs/hunt-current-3-coredns-exit2-1396279730201570877.ndjson) (root to 1178.56; 12,039 events)
- timeline:
  - 227.09 · this history splits from the Guarantee 2 history; it matches the init-load-env history below until about 686.6.
  - 228.20 → 1178.56 · faults with no quiet window. Pod faults: kill kms-core-2 at 472.77, kill kms-core-3 at 1054.17. No fault targets coredns.
  - 523.57 · coredns (restart_count 0): "[INFO] SIGTERM: Shutting down servers then terminating". It is back 191 s later, at 715.03 (restart_count 1), with "Plugins not ready: kubernetes".
  - 810.99 · coredns: SIGTERM again. It is back at 936.31 (restart_count 2), logs "waiting for Kubernetes API before starting server", then "starting server with unsynced Kubernetes API" (945.63).
  - 1013.64 · coredns: "Local health request to "http://:8080/health" took more than 1s: 1.863505065s".
  - 1089.58 · coredns: a third SIGTERM. At 1094.70 it logs "plugin/ready: Failed to stop ready http server: context deadline exceeded", and nothing more after that.
  - 1173.44–1175.76 · the init-load-env containers of kms-core-4 and kms-core-1 log "No CA cert listed for party 1/2 yet".
  - 1178.56 · the coredns container exits with code 2 (the counterexample), 84 s after its last line. No log line gives the reason for code 2.
- details: none.
- When, relative to Guarantee 2: a different timeline. In vtime it falls inside execution A's checker window (1100.66–1405.56), 227 s before A's failure.

## Failing: No unexpected crashes: systemd-journald
2 counterexamples, 0 examples. New.
- moment: input_hash=-7967124503942916867 vtime=858.8327274175826
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiODU4LjgzMjcyNzQxNzU4MjYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTc5NjcxMjQ1MDM5NDI5MTY4NjcifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiODhjZWIxYWRkNmIwMzdiNDI1NDhiOThlNzk5NTgzZTQtNjQtNCJ9)
- log: [hunt-current-3-journald-7967124503942916867.ndjson](../logs/hunt-current-3-journald-7967124503942916867.ndjson) (root to 858.83; 4,771 events)
- timeline:
  - 227.09 · this history splits from the Guarantee 2 history.
  - 231.99 → 239.39 · faults run for 7 s. The fault injector pauses at 238.68 for an eventually command, and the pod fault "kill kms-core-2" lands at 239.39. There are no faults after that.
  - 239 → 667.39 · the Guarantee 2 checker runs and passes: "all cores accepted connections after 100 s; decryption ok=true after 2 attempt(s)". The kms-cores' last lines are at 344.36–358.24.
  - 434.86, 693.51 · coredns: "Local health request … context deadline exceeded".
  - 733.77 · local-path-provisioner logs a watch warning. **Nothing else is logged for 125 s.**
  - 858.83 · `processes_terminated_with_signal`: `{ "executable": "systemd-journald", "signal": 6, "pid": 287, "container": "" }`, a SIGABRT of a host-level process outside any pod.
- details: signal 6 (SIGABRT), pid 287, container "".
- When, relative to Guarantee 2: a different, fault-free, idle timeline, 547 s of vtime before the Guarantee 2 failure.

## Failing: No unexpected container exits: container: kms-core-init-load-env, namespace: kms-threshold-staging , exit code: 1
16 counterexamples, 0 examples. **New**: first seen in this run.
- moment: input_hash=6729454480049558375 vtime=1085.861419843277
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTA4NS44NjE0MTk4NDMyNzcifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNjcyOTQ1NDQ4MDA0OTU1ODM3NSJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiI4OGNlYjFhZGQ2YjAzN2I0MjU0OGI5OGU3OTk1ODNlNC02NC00In0)
- log: [hunt-current-3-load-env-exit1-6729454480049558375.ndjson](../logs/hunt-current-3-load-env-exit1-6729454480049558375.ndjson) (root to 1085.86; 11,996 events)
- timeline:
  - 227.09 · this history splits from the Guarantee 2 history; it matches the coredns history above until about 686.6.
  - 228.20 → 1085.86 · faults with no quiet window: 87 network fault events between 480 and 1086.
  - 472.77 · fault_injector: kill kms-core-2-core-2.
  - 482.86 · kms-core-2 `kms-core-init-load-env`: "Fetching TLS certificates from S3 base URL: http://minio:9000/kms-public".
  - 492.36 → 1085.86 · it logs "No CA cert listed for party N yet" 75 times, cycling through parties 1–4. It fetches only party 3's certificate (1079.34).
  - 1085.86 · "ERROR: no CA certificate for parties 1 2 4 after 600 s; exiting non-zero so that kubelet retries", then exit 1.
- details: none. This is the harness's own bound on the CA fetch in the init container ([31-kms-core-1.yaml](../../config/manifests/31-kms-core-1.yaml), lines 146 and 174, and the same in the other cores' manifests). MinIO listings kept failing for the full 600 s under continuous faults.

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101
Suspect ([false-positives.md](../false-positives.md#boot-panic-port-in-use)): 155 counterexamples, 0 examples. No log downloaded. Moment: input_hash=-1108657042140839867 vtime=1121.3239002183545 ([log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEyMS4zMjM5MDAyMTgzNTQ1In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii0xMTA4NjU3MDQyMTQwODM5ODY3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ)).

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#core-exits-when-storage-unreachable-at-boot)): 2275 counterexamples, 0 examples. No log downloaded. Moment: input_hash=-4855594384474264247 vtime=258.57384242792614 ([log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMjU4LjU3Mzg0MjQyNzkyNjE0In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii00ODU1NTk0Mzg0NDc0MjY0MjQ3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ)).

## Failing: No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)): 209 counterexamples, 0 examples. No log downloaded. Moment: input_hash=-85916453087349581 vtime=323.8238448346965 ([log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzIzLjgyMzg0NDgzNDY5NjUifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTg1OTE2NDUzMDg3MzQ5NTgxIn1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ)).

## Did timing fuzzing slow the environment?
- **The Guarantee 2 timeline shows no stall.**
  - After setup, the only gaps longer than 12 s are the checker's own 10 s sleeps.
  - Once faults stop, kms-server boots take about 0.2 s (kms-core-4 1108.15 → 1108.31, kms-core-1 1111.12 → 1111.29), and the failing attempts return in about 0.3 s.
  - The 160–240 s boots and the 40–250 s init containers happen only while network faults are active, where a single S3 read takes 1–41 s.
  - The history has no coredns or MinIO restart, no process crash, and no `hit_mem_limit`.
  - One run can't separate timing fuzzing from the continuous network faults, since strobing is off.
- **Three other timelines do stall, and each branched off at 227.09:**
  - journald: 125 s with no event, then the SIGABRT (858.83), in an idle, fault-free history.
  - coredns: SIGTERMed three times with no fault aimed at it, the third shutdown stuck on "context deadline exceeded", then exit 2 (1178.56).
  - Antithesis error: the cores silent for 528 s, the API server not completing TLS handshakes, then the guest timeout (1852.13).
  - None of them is in the Guarantee 2 timeline. In vtime they come before (journald), during (coredns) and after (Antithesis error) execution A.
  - Whether timing fuzzing causes these stalls can't be read from the logs. They are new in this run, which is the only run with timing fuzzing.
- "Virtual time per wall time" is 1.056.
