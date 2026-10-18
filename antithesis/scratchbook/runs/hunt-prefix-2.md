# hunt-prefix-2 · 336b5b11e419dc9281d5298bbe3deff0-64-4 · prefix@3095d82a-prefix887 · completed · 240 m
Report: [triage report](https://zama.antithesis.com/report/Fll8Soc5kCDFTeEZp3ek17Ea/gZZGf9Vks_xaKy0EyS88AGlaJVfemscOEEYb6WG4vAs.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA0OjAxOjQxLjY1NTk3MDU5M1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiZ1paR2Y5VmtzX3hhS3kwRXlTODhBR2xhSlZmZW1zY09FRVliNldHNHZBcy5odG1sIiwicmVwb3J0X2lkIjoiRmxsOFNvYzVrQ0RGVGVFWnAzZWsxN0VhIn19fYJapcfSFfD2FlJP98J-1mav97zxLbJd1AWPqbw3R4BFyC9CJe4Ma707fn9SKpmxAwnwRwWBuICXoowHTbT69wM)

Session `e5d0f4e5d836bf22bd6bfc4fe7063a27-64-4`. Pre-fix build: current Zama KMS with PR #887's HTTP/2 keepalive reverted ([positive-control.md](../positive-control.md)). Fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, pod faults about every 300 s, client and MinIO pods excluded from pod faults), turbo, with strobing: 60 s of chaos, then quiet windows of 60–120 s. 63 properties: 57 passing, 6 failing. Property list: [props-336b5b11.ndjson](../logs/props-336b5b11.ndjson); run metadata: [show-336b5b11.json](../logs/show-336b5b11.json).

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, reached | 12542 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, never reached | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1176 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4843 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3148 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2006 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2475 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4732 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1615 | 1339 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 607 | 383 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached | 4492 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | **failing** | 4451 | 41 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | **failing: not hit** | 0 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 44 | 41 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 1175 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 18273 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2527 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 35195 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 1175 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 54733 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 36536 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 67600 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 49585 | 1892 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 1781 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing, reached | 6551 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 475 | 1212 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1781 | 1728 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2916 | 1020 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2745 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2136 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1671 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2006 | 0 |
| Setup: setup complete / bootstrap (the report has no `setup_complete` property; in the first failing timeline the fault injector unpauses after setup and settle at vtime 226.44 and the Test Composer starts `first_generate_key.sh` at 226.51) | — | reached | — | — |
| Setup: workload generated an FHE key (Reachable) | — | hit | 3828 | 0 |
| Setup: Commands finish with zero exit code: `first_generate_key.sh` / `parallel_driver_public_decrypt.sh` / `parallel_driver_user_decrypt.sh` / `anytime_reshare_key.sh` | — | passing | 3828 / 9197 / 7421 / 68078 | 0 |
| Commands finish with zero exit code: `eventually_recovers_after_faults.sh` | — | **failing** | 4451 | 41 |
| Setup: all commands started and run to completion at least once; full parallelism; fault injector started; 9 containers joined the network | — | passing | 1 each (9 joined) | 0 |
| Instrumentation: Software was instrumented (llvm-sancov: kms-server 970084, kms-gen-keys 394465, kms-core-client 348094, kms-init 143553 locations); Every instrumented module has symbols; Thread pausing was enabled (kms-server in all 4 cores, kms-gen-keys in all 4 init containers, kms-core-client) | — | passing | 4 / 1 / 9 | 0 |
| Antithesis default: No unexpected container exits: container: kms-core, exit code: 1 | — | **failing** (known false positive) | 0 | 288 |
| Antithesis default: No unexpected container exits: container: kms-core-init-gen-keys, exit code: 1 | — | **failing** (known false positive) | 0 | 39 |
| Antithesis default: Peak memory usage | — | **failing** | 101793 | 1370 |
| Other Antithesis defaults (no unexpected crashes, no Antithesis/build/session errors, SDK version, image platform, no invalid commands, output volume, virtual time per wall time; "Recent software version provided" flags the 6 third-party images as old) | — | passing | — | — |

Instrumentation works: all four expected binaries registered with symbols, and thread pausing is enabled in every core and init container. No container exit other than the two known exit-1 kinds was reported.

## Failing: public decryption answered by all four cores succeeds within 300 s of every core accepting connections
- moment: input_hash=1785964589558531638 vtime=542.3516741667408
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTQyLjM1MTY3NDE2Njc0MDgifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTc4NTk2NDU4OTU1ODUzMTYzOCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJlNWQwZjRlNWQ4MzZiZjIyYmQ2YmZjNGZlNzA2M2EyNy02NC00In0
- log: [hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson](../logs/hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson) (full history, vtime 0 to 542.35)
- timeline:
  - vt 226.44 · fault_injector: faults unpaused after setup and settle. 226.51–227.60: `first_generate_key.sh` makes key `54107ae0…` while faults are paused; faults resume at 227.60.
  - vt 228.20–240.39 · antithesis_test_composer: seven `parallel_driver_public_decrypt.sh` and two `anytime_reshare_key.sh` tasks start. No fault is injected in this timeline between 227.60 and 238.15.
  - vt 238.15 · fault_injector: `kill` of **kms-core-4-core-4** (pod_kill, max_duration "0"). **No network fault is active**: none has been injected in this timeline since setup. The old core-4 last logged at 227.49 (keygen).
  - vt 238.80–244.18 · kms-core-4-core-4 init containers (replacement pod) fetch the TLS certificates from MinIO ("Signing keys already exist, skipping generation" at 244.18).
  - vt 240.28 · fault_injector: asymmetric `Jammed` partition {cores 1–4, MinIO} vs {client, threshold-init job, prepopulate job}, 2.39 s. It starts after the kill and doesn't touch core-to-core links.
  - vt 242.31 · **faults stop**: `eventually_recovers_after_faults.sh` starts, and fault_injector logs `restore` and `paused: true` at 242.316. The script's ANTITHESIS_STOP_FAULTS call printed no failure. The 9 other running commands are killed (exit 137). No fault is injected after this.
  - vt 245.22 · kms-core-4-core-4/kms-core: the replacement's kms-server is up ("Starting KMS core on socket 0.0.0.0:50100"), with no container exit in this timeline.
  - vt 242.32 → 260.07 · script: attempt 1 (`-a`, `--sync`, euint128). The CLI connects to all four cores (connect_wait_s 0), and all four receive the request at 260.07.
  - vt 260.075–260.077 · kms-core-1, -2 and -3: "Public decryption in session 284755233094777381920193729655142642268 completed. Inner thread took 3–6 ms". kms-core-4 never logs completion of this session.
  - vt 320.07 · kms-core-4-core-4/kms-core: "Grpc info from KMS Core server: Code: 14" (not done yet), 60 s after the request. The CLI sends the same request again at 320.57.
  - vt 332.33 · script: the script's 90 s `timeout` kills attempt 1 ("Terminated", exit 143). The CLI printed no error of its own.
  - vt 342.33–432.34 and 442.34–532.35 · attempts 2 (sync, euint64) and 3 (sync, euint16) fail the same way. Cores 1–3 complete their sessions at 342.46 and 442.47. Core-4 answers with code 14 at 402.42 and 502.43, and the timeout kills both attempts at 90 s.
  - vt 542.35 · script: `Always "every core accepts client connections within 600 s after faults stop": true`, then `Always "public decryption answered by all four cores succeeds within 300 s of every core accepting connections": false`.
- details: `{"attempts":3,"connect_wait_s":0,"decrypt_bound_s":300,"decrypt_wait_s":300,"elapsed_s":300,"failed_attempts":3,"guarantee":"guarantee-2","last_attempt":{"attempt":3,"batch":1,"connected":true,"data_type":"euint16","error":"{… \"Encrypting plaintext: TypedPlaintext { bytes: [11, 146], fhe_type: 3 }, Euint16, U16(37387)\" …} Terminated","exit_code":143,"key_id":"54107ae012f729f3970a6ff972e49dbb95d31b92b3d57ca15e59a69c6305b151","started_after_s":200,"sync":true,"value_hex":"0b92"},"last_unreached_party":"","property":"recovers-after-faults"}`

## Failing: Commands finish with zero exit code: public_decrypt/eventually_recovers_after_faults.sh
- moment: input_hash=1785964589558531638 vtime=542.3521798998117
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTQyLjM1MjE3OTg5OTgxMTcifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTc4NTk2NDU4OTU1ODUzMTYzOCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJlNWQwZjRlNWQ4MzZiZjIyYmQ2YmZjNGZlNzA2M2EyNy02NC00In0
- log: the same file as above ([hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson](../logs/hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson)); this is the same timeline, 0.5 ms later.
- timeline: the script exits 1 because its Guarantee 2 decryption check failed (see above). Its counts (4451 / 41) equal the Guarantee 2 Always, so this is the same failure, not a separate one.
- details: none (command exit status).

## Failing: a core the client could not connect to after faults stopped accepted connections again
- moment: none. This Sometimes was never evaluated: 0 examples, 0 counterexamples, so there is no log.
- timeline: no recovery check in this run had a failed attempt that couldn't connect to some core before every core first accepted connections, so the assertion was never reached. It was hit 63 times in [hunt-prefix-1](hunt-prefix-1.md), which ran without strobing.
- details: none.

## Failing: Peak memory usage
- moment: input_hash=3818059882494376158 vtime=919.3764765637461 (first counterexample)
- counts: 101793 examples, 1370 counterexamples. This Antithesis default did not fail in the earlier 30 m runs. No log was downloaded (out of scope).
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiOTE5LjM3NjQ3NjU2Mzc0NjEifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzgxODA1OTg4MjQ5NDM3NjE1OCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJlNWQwZjRlNWQ4MzZiZjIyYmQ2YmZjNGZlNzA2M2EyNy02NC00In0

## Failing: No unexpected container exits (known false positives)
- container: kms-core, exit code: 1: 0 examples, 288 counterexamples. See [core-exits-when-storage-unreachable-at-boot](../false-positives.md#core-exits-when-storage-unreachable-at-boot).
- container: kms-core-init-gen-keys, exit code: 1: 0 examples, 39 counterexamples. See [gen-keys-init-exits-when-storage-unreachable](../false-positives.md#gen-keys-init-exits-when-storage-unreachable).
- No logs were downloaded for these.

## Known-bug signature
**Verdict: partial.** The cores' side of the expected symptom matches, but the trigger differs. In this timeline, **no network fault overlapped the restart**: kms-core-4-core-4 was killed at vtime 238.15, and no network fault had been injected since setup. So the pod kill alone was enough. The [positive control](../positive-control.md) anticipated this case in its "Fault needs" risk note: "If Antithesis's pod deletion itself drops the closing packets, the trigger is more frequent." As in hunt-prefix-1, the CLI's own error and the restarted core's timeout line can't appear in this timeline.

Matches:
- The restarted core is the missing response. Faults stopped at 242.31. For the next 300 s, every `-a` attempt failed: cores 1–3 finished each session in milliseconds, and the restarted core-4 never finished one.
  ```
  238.15180470072664 fault_injector kill kms-core-4-core-4, max_duration "0"
  242.3159239795059 fault_injector restore ALL
  242.3159240721725 fault_injector status paused: true
  ```
  ```
  260.0763018561993 kms-core-1-core-1/kms-core Public decryption in session 284755233094777381920193729655142642268 completed. Inner thread took 6 ms
  260.07682648068294 kms-core-3-core-3/kms-core Public decryption in session 284755233094777381920193729655142642268 completed. Inner thread took 4 ms
  320.0712694602553 kms-core-4-core-4/kms-core Grpc info from KMS Core server: Code: 14
  ```

Differences from the expected symptom:
- **No overlapping network fault:** the only network fault near the kill is a `Jammed` partition at 240.28, 2.1 s after the kill, between the cores and the client/job pods. It leaves core-to-core links alone.
  ```
  240.28063264815137 fault_injector partition Jammed, partitions [["kms-core-2-core-2","minio-…","minio-provision-…","kms-core-1-core-1","kms-core-4-core-4","kms-core-3-core-3"],["kms-prepopulate-keys-…","kms-core-init-threshold-init-…","kms-core-client-0"]], max_duration 2.394810812
  ```
- **CLI error text:** neither `Only got 3/4 public decryption responses` nor a poll timeout. The restarted core holds each sync call for 60 s before it answers "not done yet" (code 14), so the CLI was still waiting when the script's 90 s `timeout` killed it (exit 143). The eventual error text is just "Terminated".
  ```
  332.3314862702973 eventually_recovers_after_faults.sh Terminated
  542.351672769757 eventually_recovers_after_faults.sh [assert] Always "public decryption answered by all four cores succeeds within 300 s of every core accepting connections": false
  ```
- **`(Share reconstruction) Some party has timed out`:** this line is not in the log. The restarted core's first session began at vtime 260.07, so its 300 s `network_timeout` would expire at about vtime 560, after the log ends (542.35). An events search of the whole run (`snouty runs events <run> "Share reconstruction" "Some party has timed out"`) returned no match. In hunt-prefix-1 the same search found the line on kms-core-2-core-2.
- **Which peer's connection is dead:** the pre-fix build doesn't log this. With no partition at the kill, any or all of cores 1–3 may hold a dead connection to the old core-4.

Guarantee 1 in the same timeline: no Guarantee 1 assertion fired false. In fact, none was evaluated. The drivers were killed at 242.32, and the recovery attempts never collected four responses, so the CLI never checked a plaintext. The three answering cores computed their results normally. Run-wide, "public decryption response carries the encrypted plaintext" passed (12542 / 0), and the authentication Unreachable was never reached.
