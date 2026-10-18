# System under test: Zama KMS

**Decision:** Zama KMS @ `main` (no release tag) (`4a644c8546abc8b002b7e45c19bf195996e7d229`), chosen by rank 0: the customer's own open-source system.

`current_ref` is a commit on `main` from 2026-10-07 ([4a644c85](https://github.com/zama-ai/kms/commit/4a644c8546abc8b002b7e45c19bf195996e7d229), "fix(charts): preempt core for keygen job (#920)"), not a release. This clone has no release tags, and the user's harness (the four commits on branch `antithesis-poc-speedrun`) is built on this commit. The harness adds only the coverage-instrumentation shim (`Cargo.toml`, `Cargo.lock`, `observability/`) and the [antithesis/](../README.md) folder. It changes no KMS code.

`system_label`: `kms`.

## Why Zama's engineers will recognize this

This is Zama's own code: the [zama-ai/kms](https://github.com/zama-ai/kms) repository that builds the `kms-server` cores every Zama Protocol KMS operator runs, and the `kms-core-client` CLI that Zama's own docs use to drive them. The topology is the threshold mode that production uses, scaled from 13 parties with `t = 4` down to 4 parties with `t = 1` (the smallest cluster that survives one lost party), with MinIO in place of S3. Every guarantee in [guarantees.md](guarantees.md) quotes Zama's own documentation, and the known bug chosen as the control ([positive-control.md](positive-control.md)) is a fix Zama merged three weeks before `current_ref`, found by Zama's own rolling-upgrade tests.

## Guarantee coverage on Zama KMS

All five guarantees are expressible. Guarantees 1 to 4 use the `kms-core-client` CLI as it is ([core-client/src/lib.rs](../../core-client/src/lib.rs), `CCCommand`). Guarantee 5 needs a small workload-side helper, because the CLI does not let the caller choose a decryption request ID.

| Guarantee | Expressible on Zama KMS? | How / why not |
|---|---|---|
| [Guarantee 1](guarantees.md#guarantee-1) | yes | `public-decrypt from-args --to-encrypt --data-type --key-id [--batch-size] [--sync]` encrypts a chosen value, sends the request to all four cores, verifies signatures and majority, and fails with `decryption result mismatch` if a collected plaintext differs ([core-client/src/decrypt.rs](../../core-client/src/decrypt.rs)). The global flag `-a` collects all four responses instead of `num_majority`, so every signed response gets checked. The harness driver [parallel_driver_public_decrypt.sh](../test/v1/public_decrypt/parallel_driver_public_decrypt.sh) does this already. |
| [Guarantee 2](guarantees.md#guarantee-2) | yes | The same command with `-a` (all four responses) and `--max-iter` (result polls per core), retried after faults stop. The CLI fails with `Only got <k>/4 public decryption responses, need at least 4` when a core does not answer. |
| [Guarantee 3](guarantees.md#guarantee-3) | yes | `new-epoch --new-epoch-id --new-context-id --previous-epoch-params ...` reshares the key into a new epoch (as in [anytime_reshare_key.sh](../test/v1/public_decrypt/anytime_reshare_key.sh)). `public-decrypt --context-id --epoch-id` decrypts under a chosen epoch, the old one included. The public key is read from each party's public bucket in MinIO before and after (the client already reads it there to encrypt). |
| [Guarantee 4](guarantees.md#guarantee-4) | yes | `user-decrypt from-args ... [--sync]` reconstructs the plaintext from the cores' signcrypted shares and fails with `user decryption result mismatch` if it differs from the encrypted value. |
| [Guarantee 5](guarantees.md#guarantee-5) | yes, with a helper | The CLI cannot do it: `public-decrypt` and `user-decrypt` draw a fresh random request ID on every call (`RequestId::new_random` in [decrypt.rs](../../core-client/src/decrypt.rs)) and have no request-ID flag. `public-decrypt-result -i <id>` polls a known ID but cannot re-send it. A small Rust helper in the workload can: `Client::public_decryption_request` and `Client::user_decryption_request` in the `kms` crate take a caller-chosen `&RequestId` ([public_decryption.rs](../../core/service/src/client/public_decryption.rs), [user_decryption_non_wasm.rs](../../core/service/src/client/user_decryption_non_wasm.rs)). The helper sends the same request bytes to `PublicDecrypt` / `PublicDecryptSync` / `UserDecrypt` / `UserDecryptSync` through the `kms-grpc` client and polls `GetPublicDecryptionResult` / `GetUserDecryptionResult`. This is what the KMS connector does, so it stays a client action. |

Not covered: malicious (Byzantine) parties, as [guarantees.md](guarantees.md#not-covered) says. The launcher injects no lying parties.

## Candidates considered

Rank 0 applies (the customer's system is open source and builds from this checkout), so no substitute was evaluated.

| Candidate | Rank | Buildable + licence | Topology ≤4+1 | ≥2 of top-3 guarantees | Control candidate | Runs in Antithesis | Verdict |
|---|---|---|---|---|---|---|---|
| Zama KMS ([zama-ai/kms](https://github.com/zama-ai/kms)) | 0 | ☑ Rust workspace, built in containers by [kms-binaries.Dockerfile](../images/kms-binaries.Dockerfile). [BSD-3-Clause-Clear](../../LICENSE) (a BSD-3 variant that grants no patent rights; Zama's README allows free use for "development, research, prototyping, and experimentation", which covers testing) | ☑ 4 cores + client pod, plus MinIO as a dependency ([deployment-topology.md](deployment-topology.md)) | ☑ all of Guarantees 1–3 | ☑ #887, #792, #658 (below) | ☑ insecure build with the mock enclave, MinIO for S3. No Nitro Enclave, AWS KMS or special hardware. An earlier uninstrumented run already deployed it under Antithesis ([deployment-topology.md](deployment-topology.md)) | **chosen** |

No guarantee depends on an enterprise edition: the whole KMS is in the public repository. The production-only parts (Nitro Enclave attestation, AWS KMS backup wrapping) are outside all five guarantees.

## Machine size

Estimates, from the 834 crates in `Cargo.lock` (TFHE-rs, the AWS SDK, tonic and their trees) and the build in [kms-binaries.Dockerfile](../images/kms-binaries.Dockerfile): profile `release-lto-off`, coverage flags, line tables, and one shared cargo target cache mount (`id=kms-antithesis-target`).

| Item | Size | Count |
|---|---|---|
| Builder image, toolchain and system packages | ~4 GB | once |
| Cargo registry cache | ~2 GB | once |
| Shared target cache after one full build | ~20–25 GB | once. A revert-on-current or fix-verify build recompiles only the changed workspace crates and their dependents, and overwrites them in place: +1–3 GB |
| The four images of one build (instrumented binaries plus the `/symbols` layer) | ~3–4 GB | per build |

For current + 1 pre-fix (revert on current) + 3 fix-verify builds: about 45–55 GB, at most about 60 GB. The machine has 135 GB free, so it fits with more than 70 GB to spare. An old-release pre-fix build would add a second dependency tree (+10–15 GB) and would still fit. CPU and memory: 16 vCPU and 31 GB fit a no-LTO build. If a TFHE-heavy compile step runs out of memory, cap the build at 8 jobs. That is a build setting, not a strategy change. No S12.

## Positive-control candidates (handed to P6b)

Details, criteria and the rejected candidates are in [positive-control.md](positive-control.md).

1. **Restarted peer unreachable over a dead connection** (leading): [PR #887](https://github.com/zama-ai/kms/pull/887), violates [Guarantee 2](guarantees.md#guarantee-2). Fix: [a51d30be](https://github.com/zama-ai/kms/commit/a51d30beeae0131a84c9875f62de3012ae3890f9). Trigger: a core is deleted (pod_kill) while a network fault cuts its link to a running core, so the running core keeps a dead HTTP/2 connection to it. Without keepalive, that connection stays dead for about 15 minutes. Affected: v0.14.x and `main` before 2026-09-25. Way: fix reverted on current (all production hunks reverse-apply cleanly, 18 commits from fix^ to `current_ref`).
2. **Failed reshare deletes public keys**: [PR #792](https://github.com/zama-ai/kms/pull/792), violates [Guarantee 3](guarantees.md#guarantee-3). Fix: [00cebe09](https://github.com/zama-ai/kms/commit/00cebe099c99464d613d5835a0c9416334ab23c8). Trigger: a core's write to MinIO fails during the storage phase of a reshare (network fault between core and MinIO, or MinIO deleted), and the rollback deletes the key's public key, server key and compressed keyset. Affected: `main` before 2026-08-26 (found in v0.14 end-to-end tests). Way: old release only (the revert conflicts in 3 files, and #873 rewrote the same rollback later), 92 commits behind.
3. **Network deadlock**: [PR #658](https://github.com/zama-ai/kms/pull/658), violates [Guarantee 2](guarantees.md#guarantee-2). Fix: [50595343](https://github.com/zama-ai/kms/commit/5059534364cc27f190967c8644a7f5265130e415). Trigger: a race between the session-cleaning task, which held a `DashMap` shard guard across an `.await`, and message receipt on the same shard. Thread pausing and CPU contention widen it. Affected: `main` before 2026-06-24. Way: old release only (files moved, and #834 later removed the field involved), 182 commits behind. Such an old build also carries #887's bug, which breaks the same guarantee.
