# iterate-3 · 5a41ff45 · current@3095d82a · completed · 30 m
Report: [triage report](https://zama.antithesis.com/report/osAjr9BLYLHEbb3IXrirMKfU/qdH-RmNnyHthMKXV3T627ycFlSEFwwyqREKpQLF2ubI.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE3VDIyOjI1OjU5LjI2NDI5NTMxN1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoicWRILVJtTm55SHRoTUtYVjNUNjI3eWNGbFNFRnd3eXFSRUtwUUxGMnViSS5odG1sIiwicmVwb3J0X2lkIjoib3NBanI5QkxZTEhFYmIzSVhyaXJNS2ZVIn19fQfTp_Ex_1v8uV3QyajJ48Jw4HdyV1V3iprMM6sstjw5ZFUtGkmL2zv2RRGsRUfBLF_DjYhQu6Kd2hTVvfZU1wU)

Fault level 2: network faults plus pod kills (`network,pod_kill`, one pod fault every 600 s). Workload adds the Guarantee 3 public-key check and source-epoch decrypt, and the Guarantee 4 user-decryption driver. 64 properties: 60 pass, 4 fail. Every Always and AlwaysOrUnreachable assertion in the catalog passed. The failures are three kinds of container exit and one Sometimes marker that never fired. Instrumentation is fine: "Software was instrumented" lists kms-server (970,574 locations), kms-gen-keys (394,465), kms-core-client (348,094) and kms-init (143,553). "Every instrumented module has symbols" passes, and thread pausing ran in all 9 kms containers.

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 2583 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 331 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 890 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 534 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 424 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1147 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 722 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 240 | 433 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 69 | 86 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 1301 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 1301 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | **not hit** | 0 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 15 | 0 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 285 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 2388 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 524 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 733 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 285 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3146 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 764 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3097 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 747 | 101 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 223 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 1526 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 159 | 441 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 223 | 709 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 574 | 499 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 484 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 671 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 387 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1399 | 0 |
| workload generated an FHE key (Reachable) | — | hit | 1033 | 0 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101 (Antithesis default) | — | **failing** | 0 | 3 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** | 0 | 197 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** | 0 | 5 |
| Other Antithesis defaults (instrumentation, symbols, crashes, memory, commands) | — | passing | — | — |

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101
3 counterexamples, 0 examples. The first one is analysed below. The other two weren't inspected: `snouty runs events` timed out twice.
- moment: input_hash=-7321595884095562299 vtime=1123.323842965765
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEyMy4zMjM4NDI5NjU3NjUifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTczMjE1OTU4ODQwOTU1NjIyOTkifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiOGU1M2QyZjU4MjViNDNhN2FmZjZlMzY0NmVlN2RmMGQtNjQtNCJ9)
- log: [iterate-3-exit101-kms-core-7321595884095562299.ndjson](../logs/iterate-3-exit101-kms-core-7321595884095562299.ndjson)
- timeline:
  - 227.16 · test composer: `anytime_reshare_key.sh` (pid 7071) starts. At 227.5 cores 1, 2 and 4 log `NewMpcEpoch` for request `08374f78…`. This reshare never finishes in this history. Up to 1122.93, kms-core-4 keeps answering `GetEpochResult` for it with Code 14: "Result … with request ID 08374f78… is not ready yet". No other test command is running after 745.12.
  - 277.35, 372.41, 455.48, 712.70 · fault_injector: `node/kill` of kms-core-1, kms-core-1, kms-core-2 and kms-core-3. 455.48 is the only pod kill of kms-core-2, about 667 s before the panic. No pod kill happens in the 400 s before the panic.
  - 643.99 → 1048.67 · kms-core-2-core-2/kms-core: the container exits 6 times during boot (643.99, 717.44, 810.61, 901.06, 992.21, 1048.67). Each time it fails with "Error: reading failed for FheKeyInfo with id c967b067… and epoch id 0800…01: Unencrypted load failed: streaming error", and its init containers run again after each exit. kms-core-1 and kms-core-3 restart in a loop over the same period. kms-core-4 runs without a restart from 40.28.
  - 1034.58 · kms-core-2/kms-core (restart_count 1, the previous instance): prints "KMS Server service socket address: 0.0.0.0:50100" and binds without error, then exits 1 at 1048.67 with the FheKeyInfo error above.
  - 1049.00 → 1107.12 · kms-core-2 init containers (`kms-core-init-load-env`, then `kms-core-init-gen-keys`) run again.
  - 1068.27 → 1100.39 · fault_injector: network faults cut kms-core-2 off from MinIO several times: a Stopped partition at 1068.27 (7.6 s), a Stopped clog on kms-core-2 at 1079.25, a Slowed partition at 1084.40 (7.5 s), a Stopped partition at 1089.70 (7.0 s) and a Stopped clog on MinIO at 1098.67. Restores follow at 1100.39, 1104.29, 1108.02 and 1108.48.
  - 1108.05 · kms-core-2/kms-core: a new container starts with restart_count 0. It loads the config (listen_port 50100) and starts the metrics server on 0.0.0.0:9646.
  - 1108.27 → 1117.90 · kms-core-2/kms-core: boot-time S3 reads from kms-private and kms-public (migration checks, `PRIV-p2/SigningKey`, `PUB-p2/TypedVerfKey`, `PUB-p2/VerfAddress`). None of them fails.
  - 1118.71 · fault_injector: a Slowed partition (mean latency 1138 ms, 7.1 s) puts cores 1–4 on one side and the client and MinIO on the other. At 1120.80 a Slowed clog hits kms-core-2 and MinIO (1.75 s).
  - 1121.95 · fault_injector: `restore` ALL.
  - 1122.8736 · kms-core-2/kms-core: prints "KMS Server service socket address: 0.0.0.0:50100", then panics on bind (see details). Uptime is 14.8 s. The container was still booting and hadn't served a request.
  - 1123.32 · the exit-101 moment.
- details: party 2 (pod `kms-core-2-core-2`, container `kms-core`), stderr:
  ```
  thread 'main' (23) panicked at core/service/src/bin/kms-server.rs:594:29:
  Could not bind to 0.0.0.0:50100 
   Os { code: 98, kind: AddrInUse, message: "Address already in use" }
  note: run with `RUST_BACKTRACE=1` environment variable to display a backtrace
  ```
  The log has no backtrace because RUST_BACKTRACE isn't set. At 3095d82a, `core/service/src/bin/kms-server.rs:592-594` is the gRPC service listener bind, `TcpListener::bind(service_socket_addr).await.unwrap_or_else(|e| panic!("Could not bind to {service_socket_addr} \n {e:?}"))`. It runs before `boot_base_kms` loads the keys. The pod spec has a single app container, `kms-core`, on port 50100. The log doesn't show what still held 50100. The last instance known to have bound it is the previous `kms-core` container, which logged its exit error at 1048.67.

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1
197 counterexamples, 0 examples. This is the same failure as iterate-2: see [false-positives.md](../false-positives.md#core-exits-when-storage-unreachable-at-boot).
- moment: input_hash=3447929014687623522 vtime=307.0738430493511
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzA3LjA3Mzg0MzA0OTM1MTEifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzQ0NzkyOTAxNDY4NzYyMzUyMiJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiI4ZTUzZDJmNTgyNWI0M2E3YWZmNmUzNjQ2ZWU3ZGYwZC02NC00In0)
- log: [iterate-3-exit1-kms-core-3447929014687623522.ndjson](../logs/iterate-3-exit1-kms-core-3447929014687623522.ndjson)
- timeline:
  - 277.35 · fault_injector: `node/kill` of kms-core-1-core-1. Init containers run from 277.77 to 284.47.
  - 285.37 · kms-core-1/kms-core: a fresh container starts. At 296.91 it logs "Starting threshold KMS server v0.15.0-1, with id Some(1)".
  - 297.26 · kms-core-1/kms-core: "Reading object from bucket kms-private under key PRIV-p1/FheKeyInfo/0800…01/c967b067…".
  - 298.44 and 302.74 · fault_injector: Stopped clogs (2.9 s and 3.0 s) on links that include MinIO and kms-core-1.
  - 306.81 · kms-core-1/kms-core: exits 1. Uptime is 21.4 s.
- details: the last line on stderr is "Error: reading failed for FheKeyInfo with id c967b0670460f6a7405f4bef1688fbe699c2b8470c039f388b3ed96b0d674b8d and epoch id 0800000000000000000000000000000000000000000000000000000000000001: Unencrypted load failed: streaming error". Iterate-2 failed with the same message.

## Failing: No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1
5 counterexamples, 0 examples. This is the same class of failure as iterate-2, an S3 "dispatch failure" while MinIO is cut off: see [false-positives.md](../false-positives.md#gen-keys-init-exits-when-storage-unreachable). The wording differs from iterate-2.
- moment: input_hash=-4650200419233652953 vtime=753.5738429722842
- log link: [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNzUzLjU3Mzg0Mjk3MjI4NDIifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTQ2NTAyMDA0MTkyMzM2NTI5NTMifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiOGU1M2QyZjU4MjViNDNhN2FmZjZlMzY0NmVlN2RmMGQtNjQtNCJ9)
- log: [iterate-3-exit1-gen-keys-4650200419233652953.ndjson](../logs/iterate-3-exit1-gen-keys-4650200419233652953.ndjson)
- timeline:
  - 665.60 · fault_injector: `node/kill` of kms-core-2-core-2.
  - 680.64 · kms-core-2/kms-core-init-gen-keys: "generating keys". It reads `PRIV-p2/SigningKey` and `SigningSeed`, and then `PUB-p2/TypedVerfKey` and `TypedVerfAddress`.
  - 714.89 · kms-core-2/kms-core-init-gen-keys: the last S3 call is "Checking if object exists in bucket kms-public under key PUB-p2/TypedVerfKey/ab713248…". The container logs nothing more for 38 s.
  - 736.48 → 753.3 · fault_injector: a Stopped clog that includes MinIO and kms-core-2 (736.48, 7.2 s), a Stopped partition at 739.06 (3.1 s) that leaves all four cores and MinIO on the same side, a Stopped partition at 743.96 (3.0 s) with kms-core-2 and kms-core-4 on one side and MinIO, kms-core-1 and kms-core-3 on the other, and a Stopped clog on kms-core-2 and MinIO (747.14, 6.3 s).
  - 753.26 · kms-core-2/kms-core-init-gen-keys: exits 1.
- details: the last line on stderr is "Error: Party 2: dispatch failure". In iterate-2 the message was "Error: Failed to read existing server signing keys for party 1: Getting all ids failed: dispatch failure".

## Failing: a core the client could not connect to after faults stopped accepted connections again (Sometimes)
0 examples and 0 counterexamples, so no moment and no log. The assertion was never evaluated in any history. This run had pod kills, and "public decryption succeeded after the client left out a core it could not connect to" was hit 69 times. This marker still never fired.
