---
sut_path: /home/avpai/src/customer/customer-zama/sut/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229  # plus the uncommitted Antithesis kit changes (sut/kms-changes.patch)
updated: 2026-10-14
external_references: []
---

# SUT Analysis — Zama KMS (threshold mode)

## Scope of this pass

The user asked for **one black-box property**, not a full catalog. This analysis is scoped to
that. It describes the whole system briefly and goes deeper only on the public-decryption path that
the chosen property exercises. Areas listed under "Failure-prone areas" were not researched in
depth; they are leads for a later full pass.

## Summary

Zama KMS holds FHE key material and does key generation, CRS generation, public decryption, user
decryption, and resharing. It runs either as one centralized server or as an `n`-party threshold
MPC cluster (`ai-docs/ARCHITECTURE.md`). The Antithesis deployment in `Antithesis_RUN/` runs
**threshold mode with n = 4, t = 1**. It uses an **insecure** build with the **mock enclave**,
`Test` FHE parameters, and `NoiseFloodSmall` decryption mode.

## Architecture

| Component | What it is | Interfaces |
|---|---|---|
| `kms-core-{1..4}` | `kms-server` binary, one per party, each a 1-replica StatefulSet | service gRPC `:50100` (`CoreServiceEndpoint`, no auth, no TLS); core-to-core gRPC `:50001` (mTLS, `[threshold.tls.auto]`, self-issued from each node's onboard CA); metrics `:9646` |
| MinIO | S3 stand-in. Holds `kms-public` (`PUB-p<i>`) and `kms-private` (`PRIV-p<i>`) buckets per party | S3 HTTP `:9000` |
| `kms-prepopulate-keys` Job | Runs `kms-gen-keys` for all parties before the cores start, so each core finds every peer's CA cert at boot (workaround, see `Antithesis_RUN/README.md`) | writes to MinIO |
| `kms-core-init-threshold-init` Job | Waits for all four cores' health checks, then runs `kms-init`, which creates the default MPC context and epoch | service gRPC to all cores |
| `kms-core-client` | Idle pod with the `kms-core-client` CLI and a generated `config.toml` (`num_majority = 2`, `num_reconstruct = 3`). Intended driver host for the workload | service gRPC to all cores; S3 reads for public material |

### Public decryption request path (the part this pass traced)

1. The client encrypts a plaintext under the cluster's FHE public key, which it reads from MinIO.
   It sends the same `PublicDecryptionRequest` (request ID, key ID, context, epoch, EIP-712 domain,
   ciphertexts) to **every** party (`core-client/src/decrypt.rs:913`).
2. Each party validates the request, checks the context and epoch, and takes a read guard on the FHE
   key share. It then registers the request ID in its in-memory public-decryption meta store via
   `add_or_redo_failed_in_meta_store` (`core/service/src/engine/threshold/service/public_decryptor.rs:373`).
3. Each ciphertext in the batch runs its own MPC session. The session ID is derived
   deterministically as `req_id.derive_session_id_with_counter(ctr)`
   (`public_decryptor.rs:395`). The sessions run in parallel on the node's task tracker.
4. Results, or the error, go into the meta store. The client polls `GetPublicDecryptionResult`
   on every party, retrying on `Unavailable` (`decrypt.rs:956`). The other option is
   `PublicDecryptSync`, which attaches to the same meta-store entry (`public_decryptor.rs:654`).
5. The client accepts the result once `num_majority` (default) or all `n` (`-a`) responses arrive.
   It checks signatures and majority agreement (`core/service/src/client/public_decryption.rs:77`).
   In encrypt-then-decrypt mode it also checks that each response's plaintext equals what it
   encrypted (`decrypt.rs:266-310`).

## State

- **In-memory meta stores** (one per operation type) track every accepted request ID. They do not
  survive a restart. ARCHITECTURE.md states that a reboot forgets every known request and session
  ID, and that the external KMS connector compensates.
- **Network session store** (`core/threshold-networking/src/grpc/session_store.rs`): a per-session-ID
  map whose status is `Inactive` (messages buffered before the local party knows the request),
  `Active`, or `Completed`. A background task removes `Completed` entries after a cleanup interval.
  This store is also in memory only.
- **Persistent storage** in MinIO: public material (keys, CRS, verification keys, CA certs) and
  private material (key shares, `EpochData`, contexts, PRSS setups). ARCHITECTURE.md says
  boot-time verification checks this storage and repairs public material from peers. This pass
  did not check that claim.

## Concurrency model

- Tokio async runtime. Each ciphertext in a batch gets its own MPC session, spawned on the node's
  task tracker. ARCHITECTURE.md says CPU-heavy crypto runs on Rayon pools
  (`core/thread-handles`).
- MPC rounds are synchronised per session. Every message carries a `round_counter`. Stale-round
  messages are dropped, future-round messages are buffered, and only exact-round messages are
  delivered (`core/threshold-networking/src/sending_service/session.rs:142-235`).
- A rate limiter gates each operation type (`rate_limiter.start_pub_decrypt()`,
  `public_decryptor.rs:275`). ARCHITECTURE.md says in-memory lifecycle leases serialize epoch and
  context creation against destruction. This pass did not check that claim.

## Claimed guarantees (claims to test, not established facts)

- The MPC protocol is described as "maliciously secure and robust" for up to `t` corrupt parties
  (ARCHITECTURE.md, citing Noah's Ark, eprint 2023/815).
- The client says it accepts a public-decryption plaintext only as a consensus value of at least
  `min_agree_count` validly signed responses (`core/service/src/client/public_decryption.rs:66-73, 108-110`).
- Retrying a failed decryption request ID resets the entry and decrypts again. Retrying a pending
  or successful ID is rejected with `AlreadyExists`, and the sync variant attaches to it instead
  (`util/meta_store.rs:1014-1026`, ARCHITECTURE.md "Request IDs").

## Failure-prone areas (leads, not researched in this pass)

- **Restart, then the same request ID.** A restart wipes both the meta store and the network
  session store. A retry with the same request ID then rebuilds sessions under the same derived
  session IDs while peers may still be mid-protocol or `Completed` under those IDs.
- **Retry after failure while the session is still `Completed`.** Creating a network session with an
  ID that is not `Inactive` returns an error (`core/threshold-networking/src/grpc/manager.rs:273`).
  A quick retry of a failed request on the same party can therefore fail until cleanup removes the
  entry.
- **Restart orphans the epoch.** `Antithesis_RUN/README.md` says that after a party restarts, its
  context is rewritten with an empty epoch list, and the deploy script works around this. This is a
  deployment-kit claim. It has **not** been checked against the code and is not a premise of any
  property here.
- Boot-time public-storage repair from peers, non-atomic paired material writes, reshare rollback,
  and custodian-backup rollback (all described in ARCHITECTURE.md) are candidate areas for later
  passes.

## Assumptions

- The Antithesis run uses the manifests in `antithesis/config/manifests/` unchanged:
  4 cores, MinIO, the init Job, and the core-client pod.
- `Test` FHE parameters keep keygen and decryption fast enough for many operations per timeline.
  Nobody has measured this under Antithesis yet.

## Open Questions

- How long do `preproc-key-gen` and `key-gen` take under Antithesis with `Test` params? This
  decides whether the workload generates a key in a `first_` command or uses insecure keygen.
- Should the workload target the secure keygen path (real DKG) or `insecure-key-gen`? Both produce a
  key that public decryption can use. Secure DKG exercises far more MPC code.
