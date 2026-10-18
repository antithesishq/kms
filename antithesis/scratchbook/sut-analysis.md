---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: https://docs.zama.org/protocol/protocol/overview/kms
    why: robustness and guaranteed-output-delivery claims
---

# SUT Analysis — Zama KMS (threshold mode)

## Scope

Only the components and data paths that the five guarantees in [guarantees.md](guarantees.md)
touch: public and user decryption, resharing into a new epoch, the request-ID meta stores, the
core-to-core session layer, restart and boot, and the client CLI. Key generation, CRS generation,
backup and custodian recovery are out of scope except where a guarantee depends on them (the
workload needs a key). Per-property detail is in [properties/](properties/).

## Summary

Zama KMS holds the FHE secret key of the Zama Protocol and decrypts on request. The harness runs it
in **threshold mode, n = 4, t = 1**: four `kms-server` parties, each holding a Shamir share of the
key, run MPC protocols to decrypt. The build is `insecure` with the mock enclave, `Test` FHE
parameters and `NoiseFloodSmall` decryption ([tuning.md](tuning.md)). Storage is MinIO standing in
for AWS S3. The deployment is in [deployment-topology.md](deployment-topology.md).

## Components the guarantees touch

| Component | What it is | Interfaces | Guarantees |
|---|---|---|---|
| `kms-server` (×4) | One party: service layer (`core/service`), MPC engine (`core/threshold-execution`), networking (`core/threshold-networking`) | service gRPC `:50100` (no auth, no TLS); core-to-core gRPC `:50001` (mTLS, `[threshold.tls.auto]`); metrics `:9646` | all |
| Meta stores | In-memory table per operation type: request ID → pending / done(ok) / done(err) / deleted (`core/service/src/util/meta_store.rs`) | — | 1, 4, 5 |
| Network session store | In-memory map session ID → `Inactive` / `Active` / `Completed` (`core/threshold-networking/src/grpc/session_store.rs`, `manager.rs`) | — | 1, 2, 5 |
| Epoch manager | Creates epochs (PRSS init), reshares keys, rolls back on storage failure (`core/service/src/engine/threshold/service/epoch_manager.rs`) | `NewMpcEpoch`, `GetEpochResult` | 3 |
| MinIO | `kms-public` (`PUB-p<i>/…`, anonymous read) and `kms-private` (`PRIV-p<i>/…`) | S3 HTTP `:9000` | 2, 3 (boot, reshare storage) |
| `kms-core-client` | CLI: encrypts, fans out requests, polls, verifies signatures, majority, reconstruction, ground truth | service gRPC to every core; HTTP reads of `kms-public` | all (the driver) |

## Data paths

### Public decryption (Guarantee 1, and the probe for Guarantee 2)

1. The client reads every party's verification key from MinIO, connects to every core, fetches
   the public key, and encrypts locally (randomized).
2. It sends one `PublicDecryptionRequest` (request ID, ciphertexts with handles, key ID, context,
   epoch, EIP-712 domain, extra data) to **every** core.
3. Each core: rate-limiter permit → validation → context and epoch check → FHE key read guard →
   `add_or_redo_failed_in_meta_store` → one MPC session per ciphertext, ID
   `req_id.derive_session_id_with_counter(ctr)`, in `NetworkMode::Async`
   (`public_decryptor.rs:266-560`).
4. When every slot succeeds the core signs the payload once and stores it; any failure stores
   `Done(Err)`.
5. The client polls `GetPublicDecryptionResult` (blocks ≤ 60 s server-side while pending) or uses
   `PublicDecryptSync`, collects `num_majority` (2) or all 4 (`-a`) responses, verifies signatures,
   request link and agreement, then compares with the encrypted value.

### User decryption (Guarantee 4)

Same fan-out and meta-store handling (`user_decryptor.rs:467-646`). Each core masks its partial
decryption and signcrypts it to the request's ephemeral ML-KEM key. The client needs `2t + 1` = 3
authenticated responses, votes on the invariants, un-signcrypts, reconstructs with error
correction, and compares with the encrypted value
([details](properties/user-decrypt-returns-encrypted-plaintext.md)).

### Resharing into a new epoch (Guarantee 3)

`NewMpcEpoch` with `previous_epoch` (`epoch_manager.rs:1858`): lease, existing-epoch check
(`InvalidArgument`), meta-store insert (`AlreadyExists`), then in the background PRSS init (stores
`EpochData` and **registers the epoch**), the reshare protocol in Sync mode, and the storage phase
under a per-party lock. A storage failure rolls back; a protocol failure leaves the epoch
registered without key shares on that core. `GetEpochResult` returns signed key digests per key.
Public material is stored per key ID, not per epoch, and must stay byte-identical
([details](properties/reshare-preserves-key.md)).

### Restart and boot (Guarantees 2 and 5)

A restarted core loses its meta stores and network session store. At boot it re-stores the
default context, loads every key share of every epoch and every `EpochData` from private storage,
verifies public storage (repairing from peers if needed), starts the MPC server, then the service
server, and only then reports ready (`kms_impl.rs:512-662`, `:852`;
`observability/src/health.rs`). Readiness doesn't check peer connectivity. Peers detect the dead
connection to the old process with HTTP/2 keepalive (15 s ping, 30 s timeout) and reconnect on the
next send ([details](properties/recovers-after-faults.md#what-recovery-takes-step-by-step)).

### Request-ID handling (Guarantee 5)

Decryption IDs: unknown → new attempt; pending, succeeded or deleted → `AlreadyExists` (async) or
attach (sync); failed → redo. Epoch IDs: any known ID → `AlreadyExists`. Everything is in memory,
so a restart forgets every ID. A redo re-creates the same MPC session IDs, which the core's own
session store keeps as `Completed` for 24 h, so a redo of an in-session failure fails at once unless
the core restarted ([details](properties/decrypt-request-id-retries.md)).

## The client CLI

Facts every check depends on (`core-client/src/`):

- **Connects to every configured core before sending** (`lib.rs:2029, 2038`, seven attempts 100 ms
  apart, no connect timeout). A core with no ready pod refuses the connection, and the run fails
  with exit 1. `num_parties` can be set above the number of listed cores (`lib.rs:413`), so a
  three-core config runs public decryption while one core is down.
- **Fresh random request ID per run**; no flag to choose one. Printed only on success.
- **Polling:** 500 ms between polls, `--max-iter` polls (default 30), retry only on `Unavailable`;
  `--sync` re-sends the identical request on `Unavailable` or `ResourceExhausted`.
- **Collection stops at the quota** (`num_majority` = 2, `num_reconstruct` = 3, or all with `-a`);
  later responses are dropped unchecked.
- **Exit codes:** 0 success; 1 error (including wrong-result errors, told apart by text); 101 panic
  (`new-epoch` unwraps every error); 2 bad arguments.

## Concurrency model

- Tokio runtime (`num_tokio_threads = 2` here), Rayon pools for CPU-heavy crypto
  (`num_rayon_threads = 8`). Each ciphertext in a batch is its own MPC session, spawned on the
  node's task tracker.
- MPC rounds are synchronized per session by a round counter: stale rounds dropped, future rounds
  buffered (up to 16 rounds ahead), exact rounds delivered
  (`core/threshold-networking/src/sending_service/session.rs:142-235`).
- Messages for a session a party doesn't know yet are buffered in an `Inactive` entry (at most
  1000 per sender here) and discarded after 900 s.
- In-memory leases serialize epoch creation against destruction; a per-party lock serializes
  reshare storage phases and rollbacks.

## Claimed guarantees (claims to test, not established facts)

- The MPC protocol is robust for up to `t` corrupt parties (litepaper, ARCHITECTURE.md).
- Guaranteed output delivery with offline or misbehaving nodes (KMS overview); failing nodes
  re-join from on-disk material without `init` ([kms-server-bin.md](../../docs/guides/kms-server-bin.md)).
- Resharing keeps the public key; a storage failure rolls back on that party
  ([entry_points.md](../../docs/guides/entry_points.md), [ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md)).
- The documented request-ID replies ([trust_model.md](../../docs/explanations/trust_model.md)).

## Failure-prone areas (leads)

- **Restart, then the same request ID.** Both stores are wiped on the restarted core while peers
  keep `Active`/`Completed` sessions under the same derived session IDs.
- **Redo after failure on a core that didn't restart** fails at session creation for 24 h (see
  above). Documented as "runs again".
- **A failed reshare leaves a registered epoch without shares** on cores that finished PRSS init.
- **Boot reads every epoch's key material**; repeated reshares make boot slower, and a storage
  error at boot ends the process (crash loop with back-off up to 300 s).
- **After a reshare and a restart**, `GetKeyGenResult` answers from the largest epoch ID
  (`kms_impl.rs:561-566`), which may not be the epoch a client names.
- **Async decryption sessions wait up to 900 s** for a missing party (`discard_inactive_sessions_interval`),
  not `network_timeout`.

## Assumptions

- The Antithesis run uses `antithesis/config/manifests/` rendered with the `speedrun-<sha>` image
  tag, unchanged otherwise.
- `Test` parameters keep keygen and decryption fast enough for many operations per timeline; not
  measured yet under Antithesis.

## Open Questions

- Boot time of `kms-server` under Antithesis, and its growth with the number of epochs.
- Whether the robust online protocols ever advance a session with more than t parties marked
  missing (relevant to a restarted party's round alignment;
  [details](properties/public-decrypt-returns-encrypted-plaintext.md#investigation-log)).
