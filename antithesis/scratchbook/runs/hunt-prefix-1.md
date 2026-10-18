# hunt-prefix-1 · 52a8bf9be7747728dac81893037062a5-64-4 · prefix@3095d82a-prefix887 · completed · 240 m
Report: [triage report](https://zama.antithesis.com/report/9eEE7zOFd9Dh9U3xoux0L-pj/QKG_cHLnNVVbOYWB0R0HlqKpRTSdfPqStnNZHN3dfPw.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUUtHX2NITG5OVlZiT1lXQjBSMEhscUtwUlRTZGZQcVN0bk5aSE4zZGZQdy5odG1sIiwicmVwb3J0X2lkIjoiOWVFRTd6T0ZkOURoOVUzeG91eDBMLXBqIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjU5OjE0LjIyMjgwNjM3N1oifbWHfRwyY5SragY9QudsFg23eqGDVqsOLpO1QjjEXtewl5lI-gUwUNxI3o5onfIw34kyP6XqcyIcKwhz_FiQ4Qk)

Session `3684f1dfb7414641a5de8ad694e0cbf7-64-4`. Pre-fix build: current Zama KMS with PR #887's HTTP/2 keepalive reverted ([positive-control.md](../positive-control.md)). Fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, pod faults about every 300 s, client and MinIO pods excluded from pod faults), turbo, no strobing (`strobe_quiet_max_seconds` 0). 63 properties: 58 passing, 5 failing. Property list: [props-52a8bf9b.ndjson](../logs/props-52a8bf9b.ndjson); run metadata: [show-52a8bf9b.json](../logs/show-52a8bf9b.json).

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, reached | 22027 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, never reached | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1996 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5269 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5144 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3443 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 30839 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 8033 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3992 | 14777 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 465 | 5043 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached | 8424 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | **failing** | 8306 | 118 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 63 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 127 | 118 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 3360 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 9943 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2634 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 25987 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 3360 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 36401 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 26402 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 50073 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 39727 | 7182 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 1959 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing, reached | 14584 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2175 | 2066 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1959 | 916 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 6029 | 2603 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 8783 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 7375 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3573 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 6438 | 0 |
| Setup: setup complete / bootstrap (the report has no `setup_complete` property; in the first failing timeline the fault injector unpauses after setup and settle at vtime 227.44 and the Test Composer starts `first_generate_key.sh` at 228.40) | — | reached | — | — |
| Setup: workload generated an FHE key (Reachable) | — | hit | 7201 | 0 |
| Setup: Commands finish with zero exit code: `first_generate_key.sh` / `parallel_driver_public_decrypt.sh` / `parallel_driver_user_decrypt.sh` / `anytime_reshare_key.sh` | — | passing | 7201 / 24077 / 17213 / 51935 | 0 |
| Commands finish with zero exit code: `eventually_recovers_after_faults.sh` | — | **failing** | 8306 | 118 |
| Setup: all commands started and run to completion at least once; full parallelism; fault injector started; 9 containers joined the network | — | passing | 1 each (9 joined) | 0 |
| Instrumentation: Software was instrumented (llvm-sancov: kms-server 970084, kms-gen-keys 394465, kms-core-client 348094, kms-init 143553 locations); Every instrumented module has symbols; Thread pausing was enabled (kms-server in all 4 cores, kms-gen-keys in all 4 init containers, kms-core-client) | — | passing | 4 / 1 / 9 | 0 |
| Antithesis default: No unexpected container exits: container: kms-core, exit code: 1 | — | **failing** (known false positive) | 0 | 1841 |
| Antithesis default: No unexpected container exits: container: kms-core-init-gen-keys, exit code: 1 | — | **failing** (known false positive) | 0 | 124 |
| Antithesis default: Peak memory usage | — | **failing** | 190138 | 1650 |
| Other Antithesis defaults (no unexpected crashes, no Antithesis/build/session errors, SDK version, image platform, no invalid commands, output volume, virtual time per wall time; "Recent software version provided" flags the 6 third-party images as old) | — | passing | — | — |

Instrumentation works: all four expected binaries registered with symbols, and thread pausing is enabled in every core and init container. No container exit other than the two known exit-1 kinds was reported (no exit 101 from [boot-panic-port-in-use](../false-positives.md#boot-panic-port-in-use)).

## Failing: public decryption answered by all four cores succeeds within 300 s of every core accepting connections
- moment: input_hash=-1064784367327107482 vtime=537.2539669850376
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTM3LjI1Mzk2Njk4NTAzNzYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTEwNjQ3ODQzNjczMjcxMDc0ODIifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMzY4NGYxZGZiNzQxNDY0MWE1ZGU4YWQ2OTRlMGNiZjctNjQtNCJ9
- log: [hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson](../logs/hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson) (full history, vtime 0 to 537.25)
- timeline:
  - vt 227.44 · fault_injector: faults unpaused after setup and settle. 228.40–229.49: `first_generate_key.sh` makes key `f1fe8add…` while faults are paused; faults resume at 229.49.
  - vt 230.72–233.56 · fault_injector: a run of short partitions (Stopped and Jammed) and a clock jitter.
  - vt 233.56 · fault_injector: symmetric `Stopped` partition that isolates **kms-core-3-core-3** from every other pod for 1.72 s (until about vt 235.27).
  - vt 235.13 · fault_injector: `kill` of **kms-core-1-core-1** (pod_kill, max_duration "0"), while that partition is active, so core-3 is cut off from core-1 when core-1's pod dies. The old core-1 last logged at 229.12 (keygen).
  - vt 235.81–237.41 · kms-core-1-core-1/kms-core-init-load-env (replacement pod) fetches the TLS certificates from MinIO. Meanwhile, at 236.04, a 1.79 s `Jammed` partition separates {MinIO, client, core-4} from {core-1, core-2, core-3}, and at 236.27 a 6.4 s `Stopped` clog hits MinIO.
  - vt 237.22 · **faults stop**: antithesis_test_composer starts `eventually_recovers_after_faults.sh`, and fault_injector logs `restore` and `paused: true` at 237.218. The script's ANTITHESIS_STOP_FAULTS call printed no failure. `parallel_driver_user_decrypt.sh` is killed (exit 137). No fault is injected after this.
  - vt 239.20 · kms-core-1-core-1/kms-core: the replacement's kms-server is up ("Starting KMS core on socket 0.0.0.0:50100"), with no container exit in this timeline.
  - vt 237.23 → 252.01 · script: attempt 1 (`-a`, `--sync`, euint16). The CLI connects to all four cores (connect_wait_s 0), and all four receive the request at 252.01.
  - vt 252.05 · kms-core-2, -3 and -4: "Public decryption in session 242508055033525534766159842339229800878 completed. Inner thread took 39–41 ms", then each signs its result. kms-core-1 never logs completion of this session.
  - vt 312.01 · kms-core-1-core-1/kms-core: "Grpc info from KMS Core server: Code: 14", 60 s after the request. Code 14 (Unavailable) means "not done yet" (`core/service/src/engine/server.rs`). The CLI sends the same request again at 312.51.
  - vt 327.23 · script: the script's 90 s `timeout` kills attempt 1 ("Terminated", exit 143). The CLI printed no error of its own.
  - vt 337.24–427.24 and 437.25–527.25 · attempts 2 (async, euint160) and 3 (async, euint128, batch 2) fail the same way. Cores 2–4 complete their sessions within 7 ms (337.33, 437.34). Core-1 answers each result poll with code 14 (397.33, 497.34), and the timeout kills both attempts at 90 s.
  - vt 537.25 · script: `Always "every core accepts client connections within 600 s after faults stop": true`, then `Always "public decryption answered by all four cores succeeds within 300 s of every core accepting connections": false`.
- details: `{"attempts":3,"connect_wait_s":0,"decrypt_bound_s":300,"decrypt_wait_s":300,"elapsed_s":300,"failed_attempts":3,"guarantee":"guarantee-2","last_attempt":{"attempt":3,"batch":2,"connected":true,"data_type":"euint128","error":"{… \"Encrypting plaintext: TypedPlaintext { bytes: [1, 0, …], fhe_type: 6 }, Euint128, U128(1)\" …} Terminated","exit_code":143,"key_id":"f1fe8adda078ca6652e7b9ebdf0dfd7e0133935406c443d0475f3199dfaa7cc0","started_after_s":200,"sync":false,"value_hex":"01000000000000000000000000000000"},"last_unreached_party":"","property":"recovers-after-faults"}`

## Failing: Commands finish with zero exit code: public_decrypt/eventually_recovers_after_faults.sh
- moment: input_hash=-1064784367327107482 vtime=537.2544727453496
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTM3LjI1NDQ3Mjc0NTM0OTYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTEwNjQ3ODQzNjczMjcxMDc0ODIifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMzY4NGYxZGZiNzQxNDY0MWE1ZGU4YWQ2OTRlMGNiZjctNjQtNCJ9
- log: the same file as above ([hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson](../logs/hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson)); this is the same timeline, 0.5 ms later.
- timeline: the script exits 1 because its Guarantee 2 decryption check failed (see above). Its counts (8306 / 118) equal the Guarantee 2 Always, so this is the same failure, not a separate one.
- details: none (command exit status).

## Failing: Peak memory usage
- moment: input_hash=8302671792121512231 vtime=1105.0422158592846 (first counterexample)
- counts: 190138 examples, 1650 counterexamples. This Antithesis default did not fail in the earlier 30 m runs. No log was downloaded (out of scope).
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEwNS4wNDIyMTU4NTkyODQ2In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6IjgzMDI2NzE3OTIxMjE1MTIyMzEifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMzY4NGYxZGZiNzQxNDY0MWE1ZGU4YWQ2OTRlMGNiZjctNjQtNCJ9

## Failing: No unexpected container exits (known false positives)
- container: kms-core, exit code: 1: 0 examples, 1841 counterexamples. See [core-exits-when-storage-unreachable-at-boot](../false-positives.md#core-exits-when-storage-unreachable-at-boot).
- container: kms-core-init-gen-keys, exit code: 1: 0 examples, 124 counterexamples. See [gen-keys-init-exits-when-storage-unreachable](../false-positives.md#gen-keys-init-exits-when-storage-unreachable).
- No logs were downloaded for these.

## Known-bug signature
**Verdict: partial.** The cores' side of the expected symptom matches. The trigger also matches: a pod_kill overlapping a network fault. Two of the expected lines can't appear in this timeline. The CLI never printed its own error, because the harness's 90 s per-attempt timeout killed it first. The restarted core's 300 s session timeout falls after the log ends.

Matches:
- The restarted core is the missing response. kms-core-1-core-1 was killed at vtime 235.13 while a `Stopped` partition isolated kms-core-3-core-3. Faults stopped at 237.22. For the next 300 s, every `-a` attempt failed: cores 2–4 finished each session in milliseconds, and core-1 never finished one.
  ```
  233.55528315762058 fault_injector partition Stopped, partitions [[…the 8 other pods…], ["kms-core-3-core-3"]], max_duration 1.718627905
  235.1312214769423 fault_injector kill kms-core-1-core-1, max_duration "0"
  ```
  ```
  252.0501022799872 kms-core-2-core-2/kms-core Public decryption in session 242508055033525534766159842339229800878 completed. Inner thread took 39 ms
  252.05162973492406 kms-core-4-core-4/kms-core Public decryption in session 242508055033525534766159842339229800878 completed. Inner thread took 41 ms
  312.0115947651211 kms-core-1-core-1/kms-core Grpc info from KMS Core server: Code: 14
  ```

Differences from the expected symptom:
- **CLI error text:** neither `Only got 3/4 public decryption responses` nor a poll timeout. The restarted core holds each sync call and each result poll for 60 s before it answers "not done yet" (code 14), so the CLI was still waiting when the script's 90 s `timeout` killed it (exit 143). The eventual error text is just "Terminated".
  ```
  327.23393365042284 eventually_recovers_after_faults.sh Terminated
  537.2539655880537 eventually_recovers_after_faults.sh [assert] Always "public decryption answered by all four cores succeeds within 300 s of every core accepting connections": false
  ```
- **`(Share reconstruction) Some party has timed out`:** this line is not in the log. The restarted core's first session began at vtime 252.01, so its 300 s `network_timeout` would expire at about vtime 552, after the log ends (537.25). The line does appear elsewhere in this run. An events search (`snouty runs events <run> "Share reconstruction" "Some party has timed out"`, 40-event sample) returned 40 hits, all on kms-core-2-core-2/kms-core between vtime 2092.79 and 2452.35, for example input_hash -8918480334329293149 at vtime 2092.793521303218: `(Share reconstruction) Some party has timed out:  Elapsed(())`. Those hits are in other timelines and aren't tied to this counterexample.
- **Which peer's connection is dead:** the pre-fix build doesn't log this. The only core cut off from core-1 at the kill was kms-core-3-core-3, so it is the likely running peer.

Guarantee 1 in the same timeline: no Guarantee 1 assertion fired false. In fact, none was evaluated. The drivers were killed at 237.22, and the recovery attempts never collected four responses, so the CLI never checked a plaintext. The three answering cores computed and signed their results normally. Run-wide, "public decryption response carries the encrypted plaintext" passed (22027 / 0), and the authentication Unreachable was never reached.
