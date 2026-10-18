# hunt-current-2 · bbb951cd05081326d83a92e7efdba98c-64-4 · current@3095d82a · completed · 240 m
Report: [triage report](https://zama.antithesis.com/report/RrQpUXYBRSznhOom3OWSsVwm/GOczSuL6QWj7Sl9UX46ZavqUH-q6DwiQt8cf-yXoqwA.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDAzOjU2OjAzLjUzMjQyMjgxMVoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiR09jelN1TDZRV2o3U2w5VVg0NlphdnFVSC1xNkR3aVF0OGNmLXlYb3F3QS5odG1sIiwicmVwb3J0X2lkIjoiUnJRcFVYWUJSU3puaE9vbTNPV1NzVndtIn19fV6KMVLXfgSv3BN0DgMakXVvvIoEAi2-twEk9HZOqycO8BOfEEsMjOAaYl8MgRQlvNNY0l4DDvldF3EVrgJg9A4)

Session `d0254dba44ad247aeab414711b65127c-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, one pod fault about every 300 s, MinIO and the client pod excluded from pod faults), plus strobing: 60 s of chaos, then quiet windows of 60–120 s. Completed 04:56:04Z. Property list: [props-bbb951cd.ndjson](../logs/props-bbb951cd.ndjson).

64 properties: 60 pass, 4 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, and every Reachable and Sometimes marker was hit.** The failures are Antithesis defaults: "Peak memory usage" (new in the 4-hour hunts), the boot panic on a port in use (exit 101, seen once before in [iterate-3](iterate-3.md)), and the two known fail-fast container exits.

Setup and instrumentation are fine. There is no explicit setup-complete property in the list. Setup finished: the test composer received its first input and started `first_generate_key.sh` at vtime 226.14 in the triaged history, and "All commands were started at least once", "All commands were run to completion at least once" and "workload generated an FHE key" all pass. "Software was instrumented" lists kms-server (970,574 locations), kms-gen-keys (394,465), kms-core-client (348,094) and kms-init (143,553). "Every instrumented module has symbols" passes, and thread pausing ran in all 9 kms containers.

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 123356 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 11438 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 89511 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 45032 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 29714 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 25917 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 79587 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 56437 | 16059 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 490 | 372 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 11439 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 11439 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 132 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 145 | 0 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 3293 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 40597 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 6223 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 14685 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3293 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 56488 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 15928 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 74240 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 32895 | 6407 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3353 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 29854 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 9143 | 2051 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3353 | 1227 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 11918 | 4158 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 13372 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 14342 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 5784 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 10401 | 0 |
| workload generated an FHE key (Reachable; setup / bootstrap) | — | hit | 8860 | 0 |
| All commands were started at least once (setup / bootstrap) | — | passing | 1 | 0 |
| All commands were run to completion at least once (setup / bootstrap) | — | passing | 1 | 0 |
| Commands finish with zero exit code (all 5 commands) | — | passing | 8860–123061 each | 0 |
| **Peak memory usage** (Antithesis default) | — | **failing** | 238850 | 615 |
| **No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101** (Antithesis default) | — | **failing** ([suspect](../false-positives.md#boot-panic-port-in-use)) | 0 | 150 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 1335 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 205 |
| Other Antithesis defaults (instrumentation, symbols, thread pausing, crashes, build, fault injector, parallelism, software versions) | — | passing | — | — |

The Sometimes markers with counterexamples pass: a Sometimes property only needs one true evaluation, and the false ones are the cases where the condition didn't apply.

## Failing: Peak memory usage
615 counterexamples, 238850 examples. Antithesis default: memory never exceeded 95 % of the total available. It passed in every earlier 30-minute run ([iterate-1](iterate-1.md) to [iterate-4](iterate-4.md)) and fails in all four 4-hour hunts.
- moment: input_hash=-2683782795075500045 vtime=801.6929525653832
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiODAxLjY5Mjk1MjU2NTM4MzIifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTI2ODM3ODI3OTUwNzU1MDAwNDUifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiZDAyNTRkYmE0NGFkMjQ3YWVhYjQxNDcxMWI2NTEyN2MtNjQtNCJ9)
- log: [hunt-current-2-peakmem-2683782795075500045.ndjson](../logs/hunt-current-2-peakmem-2683782795075500045.ndjson) (full history, root to 801.41; 12,023 events)
- timeline:
  - 34.8–60.2 · setup: `kms-prepopulate-keys` (34.8), the four cores' init containers (39.7–40.3) and `kms-core-init-threshold-init` (58.8–60.2) run once and finish. They don't run again in this history.
  - 41.3 · each kms-core at boot: "Running on 1 CPUs. Total memory: 10431954944 bytes" (9.71 GiB), free 6.93–6.97 GiB.
  - 226.14 → 227.23 · test composer: first input; `first_generate_key.sh` runs and succeeds. 244.35: the composer reports `hit_cpu_limit`.
  - 226 → 667.17 · test composer: 333 commands start (247 `parallel_driver_public_decrypt.sh`, 56 `anytime_reshare_key.sh`, 29 `parallel_driver_user_decrypt.sh`, 1 keygen). Commands running at once (`tasks_len`): 15 at 200, 117 at 350, 240 at 500, 316 at 667. No command starts after 667.17. Only 50 finish by 801.69, so about 283 are still running: 209 public decryption drivers, 54 reshares and 20 user decryption drivers.
  - 244 → 735 · fault_injector: network faults (from 244.11) and clock jitter (from 257.52) only. There is no pod kill or stop in this history, and every kms-core keeps restart_count 0.
  - 520 → 801 · kms-core-client: 2–16 "Terminated" lines per 20 s, decryption attempts killed by their `timeout 300`.
  - 678.51 → 740 · kms-core-1..4: the first reshare requests reach the cores, one or two per core ("Received initiate resharing request").
  - 735.18 · fault_injector: restore, then `paused: true` (a strobing quiet window). No fault happens from here to 801.69.
  - 740 → 760 · kms-core-1..4: 26–31 reshare initiations per core in 20 s, then 5–10 more per core up to 794.69. Each reads `PUB-pN/PublicKey` and `PUB-pN/CompressedXofKey` from MinIO. The cores also answer hundreds of `GetEpochResult` polls with Code 14 "not ready yet".
  - 747.89 · test composer: `hit_mem_limit: True`.
  - 787.93 · coredns: "SIGTERM: Shutting down servers then terminating", and 24 ms later "Local health request to http://:8080/health failed: … context deadline exceeded". It is back at 790.20 (restart_count 1).
  - 789.20 · minio: the MinIO container starts again (restart_count 1). No fault targets MinIO, and the log has no exit line for it.
  - 801.41 · last log line: a user decryption attempt is "Terminated" by its timeout.
  - 801.69 · Peak memory usage counterexample.
- details: none. The property list carries only the moment, and the API output has no memory value. The report itself redirects to a GitHub login, so the peak value shown there wasn't read.

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101
150 counterexamples, 0 examples. Seen before only in [iterate-3](iterate-3.md) (3 counterexamples, kms-core-2). Previous entry: [false-positives.md](../false-positives.md#boot-panic-port-in-use); probe file: [boot-panic-port-in-use.md](../probes/boot-panic-port-in-use.md).
- moment: input_hash=-4436218268152229698 vtime=1101.244118173141
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEwMS4yNDQxMTgxNzMxNDEifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTQ0MzYyMTgyNjgxNTIyMjk2OTgifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiZDAyNTRkYmE0NGFkMjQ3YWVhYjQxNDcxMWI2NTEyN2MtNjQtNCJ9)
- log: [hunt-current-2-exit101-kms-core-4436218268152229698.ndjson](../logs/hunt-current-2-exit101-kms-core-4436218268152229698.ndjson) (full history, root to 1101.24; 48,111 events). Two extra logs (slices) are described in [Exit 101: what was happening](#exit-101-what-was-happening).
- timeline:
  - root → 791.51 · the same history as the Peak memory counterexample above, including the reshare burst, the coredns restart (787.93) and the MinIO restart (789.20).
  - 808.19 · fault_injector: `paused: false`, faults resume.
  - 857.84 · fault_injector: `node/stop` of kms-core-1-core-1. Its init containers run again (858.81–870.78). The new kms-core starts at 870.85, binds 0.0.0.0:50100 without error at 872.68 and serves requests (last line at 1067.98).
  - 876.83 kill kms-core-2, 931.88 kill kms-core-3 · fault_injector. Both cores restart and bind 50100 without error.
  - 926.11 · fault_injector: the last network fault before the panic (a Slowed partition, 5.8 s). After it there are only `restore` events (1031.04 → 1097.12). The last clock jitter was at 715.73.
  - 1076.96 · fault_injector: `node/stop` of kms-core-2-core-2. Its new kms-core binds 50100 without error at 1081.76.
  - 1098.99 · fault_injector: `node/stop` of kms-core-1-core-1 (max_duration 0). The old kms-core prints nothing more; no exit line.
  - 1099.41 → 1099.62 · kms-core-1/kms-core-init-load-env: "Fetching TLS certificates from S3 base URL: http://minio:9000/kms-public", fetches the CA certs of parties 1–4 (5 HTTP fetches), prints env and `kms-server.toml` (listen_port 50100).
  - 1100.02 → 1100.67 · kms-core-1/kms-core-init-gen-keys: "generating keys", 40 S3 log lines (existence checks and reads of the signing key and verification keys) against minio:9000.
  - 1101.02 · kms-core-1/kms-core (restart_count 0): starts, metrics server on 0.0.0.0:9646 (1101.026), "Total memory: 10431954944 bytes, Free memory: 7522062336 bytes" (7.0 GiB), migration checks, then 43 S3 log lines (1101.03–1101.04).
  - 1101.2431 · kms-core-1/kms-core: "KMS Server service socket address: 0.0.0.0:50100", then the panic (details below). No fault is active (`active_faults` is empty).
  - 1101.24 · the container exits with code 101 (the counterexample).
- details: the panic text, stderr of kms-core-1-core-1/kms-core at 1101.2430874:

  ```text
  thread 'main' (23) panicked at core/service/src/bin/kms-server.rs:594:29:
  Could not bind to 0.0.0.0:50100
   Os { code: 98, kind: AddrInUse, message: "Address already in use" }
  note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
  ```

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#core-exits-when-storage-unreachable-at-boot)): 1335 counterexamples, 0 examples. No log downloaded.
- moment: input_hash=1818559115828313879 vtime=251.07384287263267
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMjUxLjA3Mzg0Mjg3MjYzMjY3In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6IjE4MTg1NTkxMTU4MjgzMTM4NzkifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiZDAyNTRkYmE0NGFkMjQ3YWVhYjQxNDcxMWI2NTEyN2MtNjQtNCJ9)
- log: not downloaded (known false positive)

## Failing: No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1
Known false positive ([false-positives.md](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)): 205 counterexamples, 0 examples. No log downloaded.
- moment: input_hash=5967991591262741612 vtime=332.3238429930061
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzMyLjMyMzg0Mjk5MzAwNjEifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTk2Nzk5MTU5MTI2Mjc0MTYxMiJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJkMDI1NGRiYTQ0YWQyNDdhZWFiNDE0NzExYjY1MTI3Yy02NC00In0)
- log: not downloaded (known false positive)

## Peak memory: what was happening
Sources: the counterexample's log above, the run 1 counterexample ([hunt-current-1.md](hunt-current-1.md#failing-peak-memory-usage)), the exit-101 log (it shares this history up to vtime 791.51), two run-wide searches, and the manifests.

**1. The peak value.** Not available. The property list gives only moments, a run-wide event search finds no events for the property ("Peak memory": 0 events), and the triage report redirects to a GitHub login, so its chart and value weren't read. What the logs do show is the VM's size: every kms-server prints "Total memory: 10431954944 bytes" (9.71 GiB) at boot, so 95 % is about 9.23 GiB. The manifests' own comment ([10-minio.yaml](../../config/manifests/10-minio.yaml)) puts Antithesis's cluster-wide caps at 1 CPU and 10 GiB.

**2. What the cluster was doing just before 801.69.**
- *Setup steps:* none was running. Prepopulate (34.8), the cores' init containers (39.7–40.3) and `kms-core-init-threshold-init` (58.8–60.2) ran once, and the one keygen command ran 226.14–227.23. No core pod was killed, stopped or restarted in this history.
- *Pods restarting:* only infrastructure pods. coredns received SIGTERM at 787.93 and logged that its own local health check had timed out, and MinIO's container started again at 789.20 with no fault aimed at it. Both are signs that the node was starved just before the moment. The logs don't say whether memory or CPU caused it.
- *Reshares:* a burst. 56 reshare commands had started since 231, but their requests reached the cores mostly at 740–760 (26–31 per core in 20 s), just after the fault injector's quiet window began at 735.18. Each reshare makes every core load the key's public material from MinIO.
- *Parallel decryptions:* about 230 decryption driver commands were still running (209 public, 20 user), many of them waiting on `timeout 300` attempts. All of them, and the 54 open reshare commands, run in the one `kms-core-client` pod.
- *Run 1 differs in mix but not in shape:* its counterexample at 733.60 comes after 161 open reshare commands (219 started) rather than decryptions, with MinIO restarting without a fault at 651.63 and coredns health checks slowing at 718–731.

**3. Startup spike or growth.** Growth over the run, driven by work in flight. It isn't a startup spike.
- Both first counterexamples (733.60 and 801.69) come long after setup ended (about 226).
- In both histories, the number of test commands running at once climbs steadily from setup to the moment: 15 → 316 here, 4 → 183 in run 1. In run 1, the free memory that restarted cores see at boot falls from about 7.0 GiB (43) to 4.2 (463), 3.9 (544) and 3.4 GiB (549).
- A run-wide search for the test composer's `hit_mem_limit` events, which is complete because it returned fewer than the 999-event cap, finds 5 events in this run, all at vtime 681.14–747.89. Run 1 has 41 events, at 568.90–853.78. None falls in setup.
- The 615 counterexamples' own vtimes aren't visible (see 1), so this is a proxy.
- In the sibling history (the exit-101 log, identical to this one up to 791.51), faults resume at 808.19. About 200 waiting decryption commands then finish within 807–810: 179 public and 17 user decryptions succeed. Cores that restart later see 6.16 GiB free (870.86), 6.43 (885.86), 6.56 (936.90), 6.86 (1080.00) and 7.0 GiB (1101.03). So in that history, memory came back once the backlog cleared.
- Read together: the peak follows the backlog of concurrent commands and reshares. The logs can't tell whether part of that memory would also be held without the backlog, which is what a leak would look like. They also don't show which process holds it.
- Why the 30-minute runs never crossed 95 % isn't visible in these logs.

**4. Memory settings in the manifests** (`grep resources|memory` over [manifests](../../config/manifests/)):

| Pod / container | Request | Limit |
|---|---|---|
| kms-core-1..4 / kms-core ([31](../../config/manifests/31-kms-core-1.yaml)–[34](../../config/manifests/34-kms-core-4.yaml)) | 2Gi memory, 100m CPU each | 8Gi memory (plus 1Gi ephemeral storage) each |
| minio ([10-minio.yaml](../../config/manifests/10-minio.yaml)) | 256Mi, 50m CPU | 1Gi |
| kms-core-client ([40-kms-core-init.yaml](../../config/manifests/40-kms-core-init.yaml)) | 1Gi, 100m CPU | 4Gi, 2 CPU |
| core init containers, prepopulate, threshold-init, minio-provision, coredns | none set in the manifests | none |

Requests add up to 9.25 GiB, as the manifest comment says. Limits add up to 37 GiB against a 9.71 GiB VM, so no limit stops the VM from reaching 95 %: a single kms-core may grow to 8Gi. The client pod's 4Gi limit covers all ~280 concurrent workload commands together. The client log has no "Killed" or out-of-memory line, so nothing shows that limit being hit.

## Exit 101: what was happening
**The panic.** It is the same panic as iterate-3: "Could not bind to 0.0.0.0:50100 … Os { code: 98, kind: AddrInUse }" at `core/service/src/bin/kms-server.rs:594:29`. This time it is on **kms-core-1** (restart_count 0), at 1101.2431, 0.22 s after kms-server started and 2.25 s after a pod stop.

**Run-wide.** A search for "Could not bind" over the whole run returned 129 events. That's under the 999-event cap, so the list is complete.
- All 129 are on kms-core-1-core-1/kms-core. In iterate-3, all were on kms-core-2.
- They fall in three clusters: 1101.24–1160.16 (restart_count 0 to 3), 1574.14, and 1618.79–1637.20 (restart_count 0 and 1).
- The 150 exit counterexamples count container exits per branch, so they outnumber the panic lines.

**The 60 s before, in that pod** (from the timeline above):
- *Previous container:* the previous kms-core (started 870.85) bound 50100 without error at 872.68 and logged until 1067.98. It printed no exit line; the pod stop ended it.
- *Pod faults:* `node/stop` of kms-core-1 at 1098.99. The pod's init containers ran again at once (1099.41 and 1100.02), and the new kms-core came up at 1101.02 with restart_count 0. That looks like a new pod sandbox, so a new network namespace, but no log line states it.
- *Clock:* no jump since 715.73.
- *Network:* no fault since 926.11, only `restore` events. Nothing was active at the panic.
- *Memory:* the new kms-core reports 7.0 GiB free, so memory pressure plays no part here.
- *Outgoing connections from the pod in those 2.25 s:* about 5 HTTP fetches by `kms-core-init-load-env` (1099.41–1099.62), then the S3 calls of `kms-gen-keys` (40 log lines, 1100.02–1100.67) and of kms-server itself (43 log lines, 1101.03–1101.04), all to minio:9000.

**What holds port 50100.** No log line shows it. Nothing in any of the three logs prints a local port or a socket. The two extra logs (slices) narrow it down:
- **Extra log 1**, a later panic in the same history: [hunt-current-2-exit101-rc3-kms-core-6322595181088069127-from1040.ndjson](../logs/hunt-current-2-exit101-rc3-kms-core-6322595181088069127-from1040.ndjson) (moment -6322595181088069127 / 1143.8002873579971, slice from 1040; [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTE0My44MDAyODczNTc5OTcxIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii02MzIyNTk1MTgxMDg4MDY5MTI3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6ImQwMjU0ZGJhNDRhZDI0N2FlYWI0MTQ3MTFiNjUxMjdjLTY0LTQifQ)).
  - Up to 1101.24 it is the same as the counterexample.
  - kubelet then restarts kms-core in the same pod without running the init containers. All four kms-server processes in a row fail on the same bind: restart_count 0 panics at 1101.24, 1 at 1102.87, 2 at 1122.80, 3 at 1143.80.
  - No fault of any kind happens in the slice after the stop at 1098.99.
  - So port 50100 stayed taken in that pod for at least 42.6 s, across four server processes, while no other container ran in the pod.
- **Extra log 2**, a sibling branch where the bind later works: [hunt-current-2-kms-core-1-bindok-rc3-723287422945012827-from1095.ndjson](../logs/hunt-current-2-kms-core-1-bindok-rc3-723287422945012827-from1095.ndjson) (moment 723287422945012827 / 1174.8638607300818, slice from 1095; [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTE3NC44NjM4NjA3MzAwODE4In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6IjcyMzI4NzQyMjk0NTAxMjgyNyJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJkMDI1NGRiYTQ0YWQyNDdhZWFiNDE0NzExYjY1MTI3Yy02NC00In0)).
  - It shares the stop at 1098.99 and the `kms-core-init-load-env` run (1099.41–1099.62). It splits from the counterexample's history at 1099.93, when the test composer gets new input, before `kms-gen-keys` prints anything.
  - In this branch `kms-gen-keys` runs until 1105.39, under a Slowed partition.
  - kms-core then panics on the same bind three times: 1118.93 (restart_count 0), 1129.32 (1) and 1152.91 (2).
  - The init containers then run again (1153.06–1161.81), so this is probably a new sandbox. The next kms-core (restart_count 3) binds 50100 without error at 1174.80.

**Observed:**
- The port stays taken across consecutive kms-server processes in one pod for 34–43 s.
- In extra log 2, the failures stop once the init containers have run again, about 76 s after the stop.
- The run's first cluster of panics spans 1101.24–1160.16.
- Two branches that split right after `kms-core-init-load-env` both hit the panic.
- Other cores restarted after pod stops and kills in the same history (kms-core-2 at 1081.76, and earlier ones) bind without error.

**Inferred (not proved):**
- The holder isn't the new kms-server's own listener, since four separate processes fail.
- It probably isn't the old pre-stop kms-server either. The init containers ran again after the stop, which points to a fresh network namespace, so a listener left in the old one shouldn't be visible.
- What fits everything is a non-listening socket in the pod's namespace with local port 50100: an outgoing connection to minio:9000, still ESTABLISHED or in TIME_WAIT (60 s). That is the leading explanation from iterate-3.
- Because both failing branches share only the stop and `kms-core-init-load-env`'s fetches before they split, that init container's connections are the likelier source. The kernel's later port choices would have to repeat in both branches for kms-gen-keys or kms-server to be the source. That can't be ruled out without a probe.
- That every panic in a run lands on one core (kms-core-1 here, kms-core-2 in iterate-3) would fit a port choice that depends on the pod's addresses rather than on chance. Not checked.

**Difference from iterate-3:** there, kms-core-2 was in a boot crash loop under MinIO partitions, and the bind failed 74 s after the previous instance exited. Here there was no crash loop and no network fault. The panic came 2.25 s after a plain pod stop.
