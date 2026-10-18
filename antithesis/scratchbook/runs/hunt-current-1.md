# hunt-current-1 · 8196fb3cff90b7a677b4394f5e24e550-64-4 · current@3095d82a · completed · 240 m
Report: [triage report](https://zama.antithesis.com/report/RQ8Cbp-xGNyv2LzRK7QJhdaS/Q4j24Mga4r9vKq6G1GGKGJhmWP0f7ZtlCtPmgF4J-dU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUTRqMjRNZ2E0cjl2S3E2RzFHR0tHSmhtV1AwZjdadGxDdFBtZ0Y0Si1kVS5odG1sIiwicmVwb3J0X2lkIjoiUlE4Q2JwLXhHTnl2Mkx6Uks3UUpoZGFTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjUyOjUyLjkwNzU2NjUzOVoiffXOyyh90TorAK1eQ08RnDaqV3Hiuf4ZXbyxANa4Qh-8Ku_qk3g7JPpHFH0alZBWKDgpmQ1bzWKzpgv7_81JSwI)

Session `28d5e5b66639d2409d7f036de952378e-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, one pod fault about every 300 s, MinIO and the client pod excluded from pod faults), no strobing quiet windows (`strobe_quiet_max_seconds` 0). Completed 04:52:53Z. Property list: [props-8196fb3c.ndjson](../logs/props-8196fb3c.ndjson).

63 properties: 60 pass, 3 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, and every Reachable and Sometimes marker was hit.** The failures are Antithesis defaults: "Peak memory usage" (new in the 4-hour hunts) and the two known fail-fast container exits.

Setup and instrumentation are fine. There is no explicit setup-complete property in the list. Setup finished: the test composer received its first input and started `first_generate_key.sh` at vtime 226.50 in the triaged history, and "All commands were started at least once", "All commands were run to completion at least once" and "workload generated an FHE key" all pass. "Software was instrumented" lists kms-server (970,574 locations), kms-gen-keys (394,465), kms-core-client (348,094) and kms-init (143,553). "Every instrumented module has symbols" passes, and thread pausing ran in all 9 kms containers.

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 27517 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 6480 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4135 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 8715 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 6117 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 26849 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 12198 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 14822 | 8646 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2951 | 2817 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 5841 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 5841 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 38 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 57 | 0 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 896 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 8899 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2511 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 10500 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 896 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 20350 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 11458 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 28440 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 19268 | 3589 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 1450 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 7623 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 432 | 1128 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1450 | 1587 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3258 | 1159 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3528 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2050 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1967 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2687 | 0 |
| workload generated an FHE key (Reachable; setup / bootstrap) | — | hit | 4948 | 0 |
| All commands were started at least once (setup / bootstrap) | — | passing | 1 | 0 |
| All commands were run to completion at least once (setup / bootstrap) | — | passing | 1 | 0 |
| Commands finish with zero exit code (all 5 commands) | — | passing | 4948–28875 each | 0 |
| **Peak memory usage** (Antithesis default) | — | **failing** | 122387 | 1235 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 1268 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 96 |
| Other Antithesis defaults (instrumentation, symbols, thread pausing, crashes, build, fault injector, parallelism, software versions) | — | passing | — | — |

The Sometimes markers with counterexamples pass: a Sometimes property only needs one true evaluation, and the false ones are the cases where the condition didn't apply.

## Failing: Peak memory usage
1235 counterexamples, 122387 examples. Antithesis default: memory never exceeded 95 % of the total available. It passed in every earlier 30-minute run ([iterate-1](iterate-1.md) to [iterate-4](iterate-4.md)) and fails in all four 4-hour hunts.
- moment: input_hash=8539341375660142708 vtime=733.5996778807603
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNzMzLjU5OTY3Nzg4MDc2MDMifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiODUzOTM0MTM3NTY2MDE0MjcwOCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiIyOGQ1ZTViNjY2MzlkMjQwOWQ3ZjAzNmRlOTUyMzc4ZS02NC00In0)
- log: [hunt-current-1-peakmem-8539341375660142708.ndjson](../logs/hunt-current-1-peakmem-8539341375660142708.ndjson) (full history, root to 733.20; 131,583 events)
- timeline:
  - 36.7–61.0 · setup: `kms-prepopulate-keys` (36.7), the four cores' init containers (40.9–42.1) and `kms-core-init-threshold-init` (59.8–61.0) run and finish. The init containers of cores 1, 3 and 4 run again after the pod faults below, the last at 548.72.
  - 43.1 · each kms-core at boot: "Running on 1 CPUs. Total memory: 10431954944 bytes" (9.71 GiB), free 6.94–7.06 GiB.
  - 226.50 · test composer: first input, `first_generate_key.sh` starts. 233.33: the composer reports `hit_cpu_limit`.
  - 226.5 → 694.6 · test composer: 268 commands start (219 `anytime_reshare_key.sh`, 38 `parallel_driver_user_decrypt.sh`, 10 `parallel_driver_public_decrypt.sh`, 1 keygen). Only 107 finish by 733 (58 of the reshares). Commands running at once (`tasks_len`): 4 at 250, 41 at 350, 109 at 450, 160 at 550, 183 at 650.
  - 200 → 733 · kms-core-2 (the other cores alike): about 217 "Received initiate resharing" requests. Its "is not ready yet" answers to `GetEpochResult` polls grow from 71 per 50 s (250–300) to 1,618 (550–600) and 4,958 (650–700).
  - 413.25 kill kms-core-1, 519.31 stop kms-core-1, 529.31 kill kms-core-3, 542.32 kill kms-core-4 · fault_injector. The restarted cores print free memory at boot: 4.16 GiB (kms-core-1, 463.30), 3.93 GiB (kms-core-1, 544.39), 3.43 GiB (kms-core-3 and kms-core-4, 549.54). Each restarted core's own memory isn't in those numbers.
  - 651.63 · minio: the MinIO container starts again (restart_count 1). No fault targets MinIO (it's excluded from pod faults), and the log has no exit line for it.
  - 660 → 720 · kms-core-1..4: 2,500–8,800 log lines per core per 20 s, almost all `GetEpochResult` "not ready yet" and `NewMpcEpoch` (resharing=true) lines. After 720 the volume drops to 160–230 lines per core per 20 s.
  - 695.98 · test composer: `hit_mem_limit: True`.
  - 718.75 → 731.73 · coredns: "Local health request to http://:8080/health took more than 1s" (1.66 s, 1.22 s, 1.15 s, 1.14 s), and at 730.41 "failed … context deadline exceeded".
  - 725.19 → 733.18 · fault_injector: a burst of short Stopped partitions (0.05–0.21 s each); the last starts at 733.18.
  - 733.60 · Peak memory usage counterexample (the log ends at 733.20).
- details: none. The property list carries only the moment, and the API output has no memory value. The report itself redirects to a GitHub login, so the peak value shown there wasn't read.

## Peak memory: what was happening
The full analysis, including the run-wide search, is in [hunt-current-2.md](hunt-current-2.md#peak-memory-what-was-happening). For this run:

- **Peak value:** not read (see "details" above). The VM's total memory, as kms-server reports it at boot, is 10,431,954,944 bytes (9.71 GiB); 95 % of that is about 9.23 GiB.
- **Just before the moment:** no setup step was running. Prepopulate and threshold-init had finished by 61, and the cores' last init-container run ended at 548.72. No key generation was running (the history's one `first_generate_key.sh` ran 226.50–227.59), and no pod fault had happened since 542.32. The history was dominated by resharing: 219 reshare commands had started and 161 were still running. The 10 public and 38 user decryption drivers of this history had all finished, so every open command was a reshare. The cores were flooded with reshare result polls. MinIO had restarted without a fault at 651.63, and coredns's own health check was taking over 1 s from 718.75.
- **Startup spike or growth:** growth. Free memory seen by cores booting at 43, 463, 544 and 549 falls from about 7.0 to 4.2, 3.9 and 3.4 GiB while the number of running commands climbs from 4 to 183. A run-wide search for the test composer's `hit_mem_limit` events (complete, 41 events) finds them only between vtime 568.90 and 853.78. None falls in setup (before 226).
- **Memory settings:** no container limit stops the VM from filling up. See the table in [hunt-current-2.md](hunt-current-2.md#peak-memory-what-was-happening).

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#core-exits-when-storage-unreachable-at-boot)): 1268 counterexamples, 0 examples. No log downloaded.
- moment: input_hash=-1250492564694544750 vtime=288.57384464447387
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMjg4LjU3Mzg0NDY0NDQ3Mzg3In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii0xMjUwNDkyNTY0Njk0NTQ0NzUwIn1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6IjI4ZDVlNWI2NjYzOWQyNDA5ZDdmMDM2ZGU5NTIzNzhlLTY0LTQifQ)
- log: not downloaded (known false positive)

## Failing: No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)): 96 counterexamples, 0 examples. No log downloaded.
- moment: input_hash=7891916617660909840 vtime=305.5738428356126
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzA1LjU3Mzg0MjgzNTYxMjYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNzg5MTkxNjYxNzY2MDkwOTg0MCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiIyOGQ1ZTViNjY2MzlkMjQwOWQ3ZjAzNmRlOTUyMzc4ZS02NC00In0)
- log: not downloaded (known false positive)

## Added later: entry into recovery mode

A search made after this digest was written (08:27 UTC, repeated at 11:05 UTC with no error) found that kms-core-1 entered recovery mode at vtime 912.49 (input_hash -5663972180894011767; [search output](../logs/recovery-mode-8196fb3c.json)), the mechanism of [storage-error-enters-recovery-mode](../violations/storage-error-enters-recovery-mode.md). No decryption reached it in that mode, so no guarantee property failed here.
