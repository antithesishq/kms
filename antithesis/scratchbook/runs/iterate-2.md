# iterate-2 · 8bce7ea4 · current@3095d82a · completed · 30 m
Report: [triage report](https://zama.antithesis.com/report/44bMN2ghOV9ZTAc83HSRfKnO/96r6fNvaA5d6LUw5ajYS_fztx_3SlavhPmibaUEBBjQ.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiOTZyNmZOdmFBNWQ2TFV3NWFqWVNfZnp0eF8zU2xhdmhQbWliYVVFQkJqUS5odG1sIiwicmVwb3J0X2lkIjoiNDRiTU4yZ2hPVjlaVEFjODNIU1JmS25PIn19LCJuYmYiOiIyMDI2LTEwLTE3VDIyOjExOjQ5Ljc3OTUzNTgyN1oifSgqXMK1usZRwMye-_c4lZtMhUnajeS9S-m1KD51UoAdMwpsw4RopSB7vyLGKcKKHn_ojzZUOKHK_JyEPi37cAw)

Run `8bce7ea4f0dbbe8fd99570d14eca17e8-64-4`. Fault level 2: network faults plus `pod_kill` (pod fault interval 600 s; client and MinIO pods excluded from kills). 49 properties: 46 passing, 3 failing. Property list: [props-iterate-2.ndjson](../logs/props-iterate-2.ndjson).

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, reached | 3931 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, never reached | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 329 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1447 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1062 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 666 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 893 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1782 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 636 | 434 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit (unhit in iterate-1) | 224 | 116 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached | 1145 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached | 1145 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | **failing: not hit** | 0 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 5 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached | 2240 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 355 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 1648 | 0 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 306 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | not in this run's report | — | — |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | not in this run's report | — | — |
| Setup: workload generated an FHE key (Reachable) | — | hit | 957 | 0 |
| Setup: Commands finish with zero exit code: `first_generate_key.sh` / `parallel_driver_public_decrypt.sh` / `anytime_reshare_key.sh` / `eventually_recovers_after_faults.sh` | — | passing | 957 / 3092 / 3889 / 1145 | 0 |
| Setup: all commands started and run to completion; full parallelism; fault injector started; 9 containers joined the network | — | passing | 1 each (9 joined) | 0 |
| Setup: Software was instrumented (kms-server 970574, kms-gen-keys 394465, kms-core-client 348094, kms-init 143553 locations); Every instrumented module has symbols; Thread pausing was enabled (9 binaries/containers) | — | passing | 4 / 1 / 9 | 0 |
| Antithesis default: No unexpected container exits: container: kms-core, exit code: 1 | — | **failing** | 0 | 168 |
| Antithesis default: No unexpected container exits: container: kms-core-init-gen-keys, exit code: 1 | — | **failing** | 0 | 14 |
| Other Antithesis defaults (no crashes, no build/session errors, memory, SDK version, image platform; "Recent software version provided" lists the six third-party images as old) | — | passing | — | — |

The 14 rows marked "not in this run's report" are in [assertion-map.json](../assertion-map.json) but no assertion with that text was registered in this run, and no `parallel_driver_user_decrypt.sh` command ran.

## Failing: No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1
- moment: input_hash=329938113531194020 vtime=261.57384481164627
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMjYxLjU3Mzg0NDgxMTY0NjI3In1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6IjMyOTkzODExMzUzMTE5NDAyMCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiI0YjRjMGFhOTJkMDZiNmI4ZDJlZjQ3YWY2MDU0ZjMwYy02NC00In0
- log: [iterate-2-exit-kms-core-329938113531194020.ndjson](../logs/iterate-2-exit-kms-core-329938113531194020.ndjson) (full history, vt 0 to 261.57)
- pod: **kms-core-2-core-2**, container `kms-core` (`kms-server --config-file=kms-server.toml`). It was the first start of `kms-core` in a **fresh replacement pod**, 14 s after a pod kill of this same pod. Exit status: 168 counterexamples, 0 examples.
- timeline:
  - vt 225.48 · fault_injector: faults unpaused after setup and settle.
  - vt 244.31 · kms-core-2-core-2/kms-core: last output of the original pod (a `NewMpcEpoch` reshare request).
  - vt 247.24 · fault_injector: `kill` node fault on `kms-core-2-core-2` (pod_kill; max_duration "0").
  - vt 247.80–250.28 · kms-core-2-core-2/kms-core-init-load-env (replacement pod): "Fetching TLS certificates from S3 base URL: http://minio:9000/kms-public", then fetches the CA certs for parties 1–4.
  - vt 251.25–252.48 · kms-core-2-core-2/kms-core-init-gen-keys: "Signing keys already exist, skipping generation", "Keygen finished successfully."
  - vt 253.26–254.92 · kms-core-2-core-2/kms-core: kms-server boots, "KMS Server service socket address: 0.0.0.0:50100", "Starting threshold KMS server v0.15.0-1, with id Some(2)".
  - vt 255.08 · kms-core-2-core-2/kms-core: "Reading object from bucket kms-private under key PRIV-p2/FheKeyInfo/0800000000000000000000000000000000000000000000000000000000000001/a744988a…". This is its last line before the error, 6 s later.
  - vt 255.10 · fault_injector: Jammed asymmetric partition (8.47 s), core-2 and MinIO in different groups.
  - vt 255.43 · fault_injector: Jammed asymmetric partition (8.13 s), core-2 and MinIO in different groups.
  - vt 255.97 / 255.98 · fault_injector: restore, then immediately a Jammed asymmetric partition (6.01 s), core-2 and MinIO in different groups.
  - vt 257.42 · fault_injector: Jammed clog (4.38 s) on core-2, MinIO and five others.
  - vt 259.30 · fault_injector: Jammed asymmetric partition (5.99 s), MinIO with core-1 and the client, core-2 with core-3 and core-4.
  - vt 260.05 · fault_injector: Jammed clog (4.41 s) on minio-provision, core-1 and core-2. vt 260.63: restore.
  - vt 261.09 · kms-core-2-core-2/kms-core (stderr): the error below. kms-server exits with code 1.
  - vt 261.26 · kms-core-2-core-2/kms-core: kubelet restarts the container in the same pod (env dump, then kms-server boots again). vt 261.57 is the property moment.
- details: container's last lines before exiting (vt 255.08, then vt 261.09 on stderr):
  > `2026-10-17T22:37:34.879971Z  INFO main ThreadId(01) kms_lib::vault::storage::s3: core/service/src/vault/storage/s3.rs:332: Reading object from bucket kms-private under key PRIV-p2/FheKeyInfo/0800000000000000000000000000000000000000000000000000000000000001/a744988affe21f95052800be9db5fc9d7dfec02e8e96d748e1e408b3bdf0e84…`
  >
  > `Error: reading failed for FheKeyInfo with id a744988affe21f95052800be9db5fc9d7dfec02e8e96d748e1e408b3bdf0e843 and epoch id 0800000000000000000000000000000000000000000000000000000000000001: Unencrypted load failed: streaming error`

  Preceding fault: a pod kill of this same pod (vt 247.24), followed by repeated Jammed partitions and clogs between core-2 and MinIO while kms-server was streaming the FheKeyInfo object at startup. The gen-keys history below (another branch with the same kill at vt 247.24) shows the same exit repeating in core-2: identical `Error: reading failed for FheKeyInfo … streaming error` at vt 306.35 and vt 346.41.

## Failing: No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1
- moment: input_hash=-3120340626669997383 vtime=372.8238430679776
- log link: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMzcyLjgyMzg0MzA2Nzk3NzYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTMxMjAzNDA2MjY2Njk5OTczODMifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiNGI0YzBhYTkyZDA2YjZiOGQyZWY0N2FmNjA1NGYzMGMtNjQtNCJ9
- log: [iterate-2-exit-gen-keys-3120340626669997383.ndjson](../logs/iterate-2-exit-gen-keys-3120340626669997383.ndjson) (full history, vt 0 to 372.82)
- pod: **kms-core-1-core-1**, init container `kms-core-init-gen-keys` (`kms-gen-keys --config-file kms-gen-keys.toml`, which runs after the cert-fetching init container `kms-core-init-load-env`). It ran in a **fresh replacement pod**, after the second pod kill of core-1 in this history. Exit status: 14 counterexamples, 0 examples.
- timeline:
  - vt 247.24 · fault_injector: `kill` on kms-core-2-core-2 (same prefix as the kms-core history).
  - vt 270.25 · fault_injector: `kill` on kms-core-1-core-1 (first pod kill of core-1). The replacement's gen-keys ran from vt 277.28 to "Keygen finished successfully." at vt 291.18.
  - vt 306.35, 346.41 · kms-core-2-core-2/kms-core (stderr): `Error: reading failed for FheKeyInfo … Unencrypted load failed: streaming error`. At vt 347.32, core-2's init-load-env runs again, with no kill fault logged for core-2.
  - vt 352.11 · fault_injector: Stopped partition (2.88 s), core-1 and MinIO in different groups.
  - vt 352.32 · fault_injector: `kill` on kms-core-1-core-1 (second pod kill; max_duration "0").
  - vt 352.85–357.97 · kms-core-1-core-1/kms-core-init-load-env (replacement pod): "Fetching TLS certificates…", then fetches the CA certs for parties 1–4. The init container finishes.
  - vt 357.60 · fault_injector: Slowed clog (7.22 s) on core-1, MinIO, core-2, core-3 and two others.
  - vt 358.33 · kms-core-1-core-1/kms-core-init-gen-keys: "generating keys". vt 358.94: prints its config (`DEBUG: SETTINGS: KmsGenKeysConfig {… s3_endpoint: … host: Some(Domain("minio")), port: Some(9000) …`). It prints nothing more for 13.4 s.
  - vt 359.56 · fault_injector: Stopped asymmetric partition (2.50 s), core-1 and MinIO in different groups.
  - vt 361.17 · fault_injector: Stopped clog (7.09 s) on MinIO and minio-provision.
  - vt 363.88 · fault_injector: Stopped clog (7.23 s) on core-1 and core-3.
  - vt 364.80 · fault_injector: Stopped asymmetric partition (3.26 s), core-1 and MinIO in different groups.
  - vt 371.96 · fault_injector: Stopped partition (1.35 s), core-1 (with core-4 and the client) separated from MinIO.
  - vt 372.36 · kms-core-1-core-1/kms-core-init-gen-keys (stderr): the error below. The init container exits with code 1. vt 372.82 is the property moment.
- details: container's last lines before exiting:
  > `DEBUG: SETTINGS: KmsGenKeysConfig { keygen: KeygenConfig { deterministic: false, overwrite: false, show_existing: false, repopulate: false }, aws: Some(AWSConfig { region: "eu-west-1", … s3_endpoint: Some(Url { scheme: "http", … host: Some(Domain("minio")), port: Some(9000), …`
  >
  > `Error: Failed to read existing server signing keys for party 1: Getting all ids failed: dispatch failure`

  Preceding fault: a pod kill of this same pod (vt 352.32), followed by Stopped partitions and clogs between core-1 and MinIO during the whole 14 s that gen-keys spent on its first S3 call (listing the signing-key ids). Between vt 359.26 and 369.34, CoreDNS also logged `plugin/errors: 2 minio. AAAA: read udp …->8.8.8.8:53: i/o timeout`. The same upstream timeouts also appear elsewhere in the run (32 in vt 0–50), so they are not specific to this window.

## Failing: Sometimes: a core the client could not connect to after faults stopped accepted connections again
Never hit (0 examples, 0 counterexamples). This is a coverage marker ([Guarantee 2](../guarantees.md#guarantee-2)), so there is no log to download. Its companion Always, "every core accepts client connections within 600 s after faults stop", passed 1145 times.
