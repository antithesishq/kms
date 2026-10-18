# System brief: Zama KMS

Customer: Zama ([zama.ai](https://www.zama.ai)). Product under test: the Zama KMS, the threshold key management system behind decryption in the Zama Protocol. Repository: this checkout of [zama-ai/kms](https://github.com/zama-ai/kms), base commit `4a644c85`.

## What the company does

Zama builds fully homomorphic encryption (FHE), which lets programs compute on encrypted data. Its main product is the Zama Protocol: confidential smart contracts on existing EVM chains (fhEVM). Ciphertexts live on a host chain, FHE coprocessors compute on them, and a Gateway chain coordinates requests. The users are dApp developers and token issuers who build confidential contracts, plus the independent organizations that operate nodes: the litepaper lists "initially 13 KMS nodes and 5 FHE Coprocessors", and Zama's testnet update names the operator partners, among them Ledger, Fireblocks, OpenZeppelin, Figment and P2P. The KMS holds the network's single FHE secret key, split into shares across those 13 operators. It generates that key and decrypts ciphertexts when the Gateway authorizes it, either publicly or for one user. Every confidential value that ever becomes readable goes through it.

## The system

**Two modes.** The same `kms-server` binary runs either as one server that holds the whole key (centralized mode) or as one of `n` independent parties that each hold a share of the key and run multi-party computation protocols together (threshold MPC mode). The mode is chosen at startup: a party runs in threshold mode when its config has a `[threshold]` section. Production uses threshold mode with `n = 13` parties and threshold `t = 4`. A decryption needs cooperation from more than `t` parties. The protocol is meant to give the correct output even when up to `t` parties are offline or malicious, and it requires `t < n/3` (a "strong honest majority"). The Antithesis harness in this repo runs `n = 4`, `t = 1` ([sut-analysis.md](sut-analysis.md)).

**Two gRPC interfaces per party** ([trust_model.md](../../docs/explanations/trust_model.md)):

- The *service interface* (`CoreServiceEndpoint`, port 50100) is where operations are requested and results are fetched. It has no TLS, no authentication and no authorization. Exactly one caller is expected to reach it: the operator's own KMS connector.
- The *core-to-core interface* (port 50001) carries MPC protocol messages between parties over gRPC with mutual TLS. Every message carries a tag with the session ID, the round number and the sender, and the receiver checks that the sender matches the peer certificate. Sending uses exponential backoff. A message that arrives for a session the receiver does not know yet is held briefly and then dropped ([network_doc.md](../../docs/explanations/network_doc.md)). In production each party runs inside an AWS Nitro Enclave, and its TLS certificate carries an attestation of the enclave image (PCR values), which peers check against an allowlist of releases.

**The "start, then poll" pattern.** Every operation is keyed by a caller-chosen 32-byte request ID. The caller sends the request to *every* party (for example `PublicDecrypt`), then polls each party with the matching result call (`GetPublicDecryptionResult`). A result call answers `Unavailable` while the work is running and `NotFound` if the request ID is unknown ([core_grpc.md](../../docs/references/api/core_grpc.md)). The decryption calls also have blocking variants (`PublicDecryptSync`, `UserDecryptSync`) that start the work, or attach to work already running under the same ID, and wait for the result. Each party keeps the state of every request in an in-memory table, one per operation type (the "meta store"). MPC session IDs are derived from the request ID. The caller collects the signed responses and accepts a value once enough parties agree: the `kms-core-client` setting `num_majority` gives the number of matching responses needed, and `num_reconstruct` gives the number of shares needed to rebuild a user-decryption result ([core_client.md](../../docs/guides/core_client.md)).

**Operations** ([ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md), [entry_points.md](../../docs/guides/entry_points.md)):

- *Preprocessing* (`KeyGenPreproc`): produces one-time correlated randomness that key generation consumes. Each batch can be used exactly once. With production parameters it takes hours. Mainnet's offline phase took 54 hours.
- *Key generation* (`KeyGen`, distributed key generation or DKG): creates the FHE public key, server key and secret-key shares. Public material is written to each party's public storage, and the caller gets signed digests back. An insecure fast path (`InsecureKeyGen`) exists for tests.
- *CRS generation* (`CrsGen`): a distributed ceremony that produces the common reference string used by zero-knowledge input proofs.
- *Public decryption* (`PublicDecrypt`): the parties jointly decrypt a batch of ciphertexts. Each ciphertext runs its own MPC session. Each party signs the plaintext (EIP-712 / ECDSA, and optionally Ed25519 or ML-DSA).
- *User decryption* (`UserDecrypt`): each party masks its partial decryption, then signs and encrypts it to the user's public key (signcryption). The user rebuilds the plaintext from enough shares. The request carries the user's EIP-712 signature, which each party verifies.
- *Contexts and epochs, including resharing* (`NewMpcEpoch`, `DestroyMpcEpoch`, `DestroyMpcContext`): a context names the set of parties. An epoch is one sharing of the keys among them. `NewMpcEpoch` with `previous_epoch` set reshares existing key shares to a new epoch, possibly with a new party set. The result is fetched with `GetEpochResult`. A party whose storage fails during a reshare rolls back the new epoch on its side.
- *Backup and recovery*: private material is backed up to a backup vault, wrapped either by AWS KMS or by a key that is secret-shared among offline custodians (`NewCustodianContext`, `CustodianRecoveryInit`, `CustodianBackupRecovery`, `RestoreFromBackup`).
- *Health*: a health check probes the MPC network and reports Optimal, Healthy, Degraded or Unhealthy according to how many parties are reachable.

**Storage.** Each party has a *public* store (keys, CRS, verification keys, CA certificates, readable by clients) and a *private* store (key shares, epoch data, contexts, signing keys). Each store is an S3 bucket, or a local directory. On boot, a party checks its public storage against the digests recorded in its private storage, refuses to serve if they disagree, and can fetch missing public material from peers ([troubleshooting.md](../../docs/operations/advanced/troubleshooting.md)). The in-memory meta stores and network session tables do not survive a restart.

**In front of the KMS.** Applications ask for decryption on the host chain. The Gateway contracts check access rights (ACL), assign the request ID and emit an event. Each operator runs a KMS connector next to its core. The connector's `gw-listener` stores Gateway events in a Postgres database, its `kms-worker` forwards them to the local core and polls for the result, and its `tx-sender` posts the signed response back to the Gateway. The connector keeps request state across core restarts, and on a retry it polls only instead of resubmitting.

**Components**

- `kms-server`: one per party. It contains the service layer (`core/service`) and the MPC engine (`threshold-execution`, `threshold-networking`).
- `kms-core-client`: the CLI that drives the gRPC API, checks signatures and takes the majority vote. It is the workload driver for Antithesis.
- `kms-init`: initializes the cluster after deployment by creating the default MPC context and epoch.
- `kms-gen-keys`, `kms-gen-tls-certs`: generate the signing identity and the mTLS certificates.
- `kms-custodian`: the custodian-side backup tool.
- `kms-health-check`: a gRPC health probe.
- Storage: AWS S3 in production, MinIO in the Antithesis harness, or local files.
- External, not in this repo: the KMS connector (fhevm repo), the Gateway contracts, and AWS Nitro Enclaves and AWS KMS.

## Hard problems

- **All parties must agree that they are running the same request.** Each party learns about a request on its own, through its own connector, at its own time. The parties line up only through the session ID derived from the request ID. A fast party may send round-1 messages before a slow party has even seen the request. Those messages are held for a short time and then dropped. The docs admit that a party that falls far enough behind "will never be able to catchup for this specific request" ([common-errors.md](../../docs/operations/advanced/common-errors.md)).
- **Up to `t` parties may be slow, crashed or malicious, and the result must still arrive (robustness, or guaranteed output delivery).** Honest parties have to stop waiting for missing messages at the right time. If they give up too early, they fail a request that could have succeeded. If they wait forever, the request hangs. Malicious messages must be filtered without letting them count twice. A fix in August 2026 found that broadcast counted votes more than once (#775).
- **Request IDs are not handled the same way by every operation.** Key generation, preprocessing, CRS generation and epoch management reject a known ID with `AlreadyExists`. Decryption redoes an ID whose earlier attempt failed. The sync variants attach to the existing attempt. All of this lives in memory and is lost on restart, while the network session derived from the same ID may still be marked completed on peers. Retries from a connector, retries after failure and retries after a restart each take a different path.
- **A party can restart in the middle of a protocol session.** A restarted party forgets every request and session, but its peers are still mid-round under the same session ID, and their TCP connections to the old process may be silently dead. A September 2026 fix (#887) was needed so that a running party could reach a restarted party at all. Whether the cluster resumes cleanly, retries correctly, or stays wedged depends on timeouts and cleanup intervals.
- **Some sessions run for a long time.** Preprocessing and key generation run for hours across many rounds. Session cleanup, eviction of idle sessions (#834, which evicted sessions that were idle but still active), keepalives and per-session round clocks (#815) all have to be right over that whole span, including when clocks jump.
- **Resharing has to work while the cluster keeps serving.** A new epoch is created while decryptions run against the current one, and destruction of old epochs or contexts can race with creation. Leases serialize these, and a storage failure rolls back per party. Five resharing fixes landed between August and October 2026 (#752, #792, #873, #907, #910), including one where a failed reshare deleted public keys.
- **Public material must be identical across parties and match what was signed.** Writes of key material span several files and are not atomic. Each party publishes its own copy, and clients verify signed digests. A crash between writes, a reshare that re-serializes keys (#910), or a repair from peers can all leave copies that disagree. Boot-time verification then refuses to serve, which turns a consistency bug into an availability outage.
- **Recovery after a network partition.** The sender retries with exponential backoff, the receiver buffers messages for future rounds (#738) and holds messages for unknown sessions only briefly, and dead connections need HTTP/2 keepalive to be detected. After a partition heals, the cluster should go back to serving without operator action, and requests that overlapped the partition should either complete or fail visibly.
- **Preprocessing must be used up exactly once.** Each preprocessing batch may feed exactly one key generation. Consuming it is a check-then-delete on shared state, which was made atomic in #885. A rate limiter that took the wrong number of tickets was fixed in #229.

## How it might be tested

- **Correct decryption under at most `t` faults.** A `kms-core-client` workload encrypts known random plaintexts under the cluster key, then runs public and user decryptions concurrently. Meanwhile, Antithesis partitions, pauses or kills up to `t` parties (1 of 4 in the harness). The workload checks that every accepted result equals the encrypted plaintext, that at least `num_majority` signed responses agree, and that no validly signed response from any party carries a different plaintext.
- **Liveness after faults heal.** After each fault window, the workload stops injecting faults and requires every outstanding request to finish within a bounded time. This catches requests stuck in `Unavailable` forever, wedged network sessions, and parties that never rejoin.
- **Restart mid-session, then retry like a connector.** The workload kills a core while it has decryptions or keygen sessions in flight, restarts it, and then does what the connector does: poll first, and resubmit the same request ID only if the restarted party answers `NotFound`. It checks that the cluster converges and that results stay correct. It also covers retry-after-failure and the sync variants attaching to an existing ID.
- **Duplicate and racing requests.** The workload sends the same request ID to a party twice, concurrently, and mixes async and sync calls. It checks that the documented replies (`AlreadyExists`, redo after failure, attach) hold and that no party runs two MPC sessions for one ID.
- **Resharing while serving.** The workload runs `NewMpcEpoch` with `previous_epoch` while decryptions run, with faults injected during the reshare. It then decrypts the same ciphertexts under the new epoch and checks for the same plaintexts and an unchanged public key. If the reshare failed, the old epoch must still serve.
- **Clock jumps.** Antithesis moves clocks on individual parties to exercise session timeouts, cleanup of completed sessions, keepalive and backoff. The checks: no active session is evicted, and no request fails only because of a clock jump.
- **Consistent public material.** After keygen or CRS generation under faults, the workload reads every party's public bucket. All digests must match the signed digests, and every party must restart and pass boot-time verification.
- **More than `t` faults (sanity check).** With 2 of 4 parties down, requests may stall or fail. They must never return a wrong plaintext that carries enough valid signatures. After healing, the cluster must make progress again.

## Promises to clients

| # | Promise | Exact quote | Source | Kind |
|---|---|---|---|---|
| 1 | Correct output with up to a third of nodes malicious | "our MPC protocol is robust, meaning it will give a correct output with up to 1/3 malicious nodes." | https://docs.zama.org/protocol/zama-protocol-litepaper | explicit |
| 2 | Robust against malicious nodes | "The protocol is robust against malicious actors as long as at most 1/3 of the nodes act maliciously." | https://docs.zama.org/protocol/protocol/overview/kms | explicit |
| 3 | Output delivered despite offline or misbehaving nodes (availability) | "It supports guaranteed output delivery even if some nodes are offline or misbehaving." | https://docs.zama.org/protocol/protocol/overview/kms | explicit |
| 4 | Decryption is correct when two thirds are honest and online | "As long as ⅔ of the operators are running the correct software and are online, decryption is guaranteed to be correct." | https://www.zama.org/post/zama-protocol-testnet-update-mpc-partners-better-performance-audits-and-new-features | explicit |
| 5 | Correct result always recovered with at most `t` malicious parties | "if less than or equal to t parties are malicious, a correct output result will always be recovered" | https://www.zama.org/post/introducing-zama-threshold-key-management-system-tkms | explicit |
| 6 | Key generation and decryption succeed with at most `t` offline or malicious parties | "key generation and decryption will succeed even if at most $$t$$ of the parties are offline or chose to act _malicious_" | [concepts.md](../../docs/getting-started/concepts.md), https://github.com/zama-ai/kms/blob/main/docs/getting-started/concepts.md | explicit |
| 7 | Mainnet tolerance is 4 of 13 | "Our protocol was designed to withstand up to 4 offline or malicious operators," | https://www.zama.org/post/decentralized-key-generation-for-zama-mainnet-has-successfully-completed | explicit |
| 8 | Every result is signed by each node and can be verified | "All decryption operation outputs are signed by each node and the output can be verified on-chain for full auditability." | https://docs.zama.org/protocol/protocol/overview/kms | explicit |
| 9 | Key secrecy and correct results with up to `t` malicious peers | "up to `t` of the `n` parties may be malicious, and the protocol still protects the secret key and produces correct results." | [trust_model.md](../../docs/explanations/trust_model.md), https://github.com/zama-ai/kms/blob/main/docs/explanations/trust_model.md | explicit |
| 10 | Retry semantics for decryption request IDs | "If the earlier attempt failed, the core resets the entry and runs the decryption again." The same section says a known ID whose attempt is "pending, succeeded or deleted" is rejected with `AlreadyExists`, and the sync variants "attach". | [trust_model.md](../../docs/explanations/trust_model.md), https://github.com/zama-ai/kms/blob/main/docs/explanations/trust_model.md | explicit |
| 11 | A request is not lost across core restarts (the connector's promise, not the core's) | "the `KmsWorker` will be able to re-pick the event from the DB and re-send the request"; the goal is that "it never misses any KMS Core responses." The core itself says "a reboot empties every meta store". | https://raw.githubusercontent.com/zama-ai/fhevm/main/kms-connector/docs/architecture.md, [trust_model.md](../../docs/explanations/trust_model.md) | explicit (connector); the core makes no such promise |
| 12 | A failed reshare does not corrupt the old state | "A storage failure during resharing rolls the new epoch back on the party that fails." and "Public material that existed before the storage phase remains unchanged." | [ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md) | explicit (developer doc) |
| 13 | Keys and CRS are not published half-done | "Key generation and CRS generation write persistent material only after generation completes." | [ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md) | explicit (developer doc) |
| 14 | A node never serves inconsistent public material | "Every node verifies its public storage against private storage during startup and refuses to serve if they disagree." | [troubleshooting.md](../../docs/operations/advanced/troubleshooting.md), https://github.com/zama-ai/kms/blob/main/docs/operations/advanced/troubleshooting.md | explicit |
| 15 | Honest parties return matching answers for the same request (consistency) | The client counts "The minimum number of matching responses required to have an honest majority" (`num_majority`). This assumes honest parties never sign different plaintexts for one request ID. | [core_client.md](../../docs/guides/core_client.md) | implied |
| 16 | Poll results have defined meanings | "`Unavailable`: The `KeyGen` for the queried `request_id` has started but is not finished yet." and "`NotFound`: There has not been a `KeyGen` call for the provided `request_id`." The decryption result calls follow the same pattern. | [core_grpc.md](../../docs/references/api/core_grpc.md) | explicit |

A documented limit that bounds promises 3 and 6: "If one party is very late however, and does not catchup before the 3 other parties finish running the protocol, then this late party will never be able to catchup for this specific request." ([common-errors.md](../../docs/operations/advanced/common-errors.md)). A lagging party may therefore fail a request for good. The cluster as a whole must still deliver.

Other explicit claims that are less useful for testing: "no individual party has access to the full key" and "If a share is lost, a quorum of custodians can collaboratively restore it" (https://docs.zama.org/protocol/protocol/overview/kms). "a correct output result" means the plaintext that was encrypted. The thresholds in these sources are stated in several different ways (1/3, 2/3, 9 of 13, `t = 4`, `t < n/3`), but all of them agree with `n = 13`, `t = 4`.

## Known bugs and fixes

`CHANGELOG.md` is stale: its last entry is v0.8.0 from 2024-07-19, before the repository moved from `kms-core`. Everything below comes from `git log` and commit messages, not from diffs. Symptoms come from commit titles and bodies. Where a body is empty, the symptom is inferred from the title and marked "(title)".

| Commit | Date | PR | Symptom a client would see |
|---|---|---|---|
| `3f6ebcdf` | 2026-06-12 | #624 | An MPC network message could be dropped, so a protocol session could stall or fail (title). |
| `50595343` | 2026-06-24 | #658 | Deadlock in the core-to-core networking layer: parties hang and requests never finish (title). |
| `d64fa2ac` | 2026-02-09 | #388 | "stability issues on KMS when getting out of sync": parties that fell out of step with each other became unstable. The fix added an active-session timeout. |
| `c484bdbc` | 2026-07-30 | #738 | Messages that arrived early, for a later protocol round, were mishandled, which could break or stall a session (title). |
| `e0f3c67e` | 2026-08-21 | #775 | Broadcast counted a party's votes more than once. A malicious party could break the protocol, which violates robustness with up to `t` malicious parties. The regression test is a malicious strategy. |
| `71538202` | 2026-09-11 | #834 | Network sessions that were idle but still active were evicted, so long-running protocols lost their session in the middle. |
| `a51d30be` | 2026-09-25 | #887 | After a peer restarted, a running party could not reach it in a new session over a frozen or dead connection. The fix added HTTP/2 keepalive (15 s interval, 30 s timeout). This is a restart and recovery bug. |
| `e3c79fa7` | 2025-06-17 | #2552 | User decryption returned 0 when all signcryptions failed: a wrong plaintext instead of an error. |
| `00cebe09` | 2026-08-26 | #792 | A failed resharing deleted public keys. A related fix, `b0ae8277` (#873, 2026-09-23), addressed over-aggressive deletion of epoch data on reshare failure. |
| `aa45f658` | 2026-10-02 | #910 (port of #899) | During resharing, parties signed digests of re-serialized keys and CRS that could differ from what was stored, so the signed digests did not match the published material. |

Other relevant fixes: `9c4e4367` (#907): a reshare failed with `InvalidArgument` when a party's URL changed between contexts. `d3246a37` (#885): keygen preprocessing is now consumed atomically. `64a1b45a` (#58): a failed request's meta-store entry was deleted instead of keeping the error. `b6979bae` (#2404): the MPC session ID is now derived by hashing the request ID.

## Open questions

- What timeout makes honest parties give up on a missing peer in each protocol round, and how does that interact with the "late party never catches up" limit? Does the client see a clean error or `Unavailable` forever?
- After a restart, does a party need its epoch re-registered? An older deployment kit claims that a restart rewrites the context with an empty epoch list. [sut-analysis.md](sut-analysis.md) flags this claim as unverified.
- What exactly is the retry policy in the connector's `kms-worker` (poll-only after acceptance, backoff, give-up)? The workload should copy it so that every failure it reports reflects real client behaviour.
- Which decryption mode does production use (`NoiseFloodSmall`, `NoiseFloodLarge`, `BitDecSmall` or `BitDecLarge`)? The harness uses `NoiseFloodSmall` with `Test` parameters.
- Is "every honest party signs the same plaintext for one request ID" a stated promise anywhere? So far it is only implied by the client's majority vote.
- What did the Trail of Bits review of Zama (2025-10, https://trailofbits.com/library/zama/) cover? The listing gives no scope or findings. The testnet blog post also names Zenith, OpenZeppelin, Burrasec and the Alexandra Institute as auditors.
- How long do preprocessing and key generation take under Antithesis with `Test` parameters (also open in [sut-analysis.md](sut-analysis.md))?
- Other systems not briefed: the fhEVM host-chain contracts (ACL, decryption oracle), the Gateway chain and its contracts, the KMS connector (`gw-listener`, `kms-worker`, `tx-sender` and its Postgres database), the FHE coprocessor, the relayer, and the custodian backup service. OSS and third-party components seen in use: TFHE-rs (`tfhe`, `tfhe-zk-pok`, `tfhe-csprng`), tonic, prost and tonic-health (gRPC), hyper, tower and tower-http (HTTP/2), rustls (Zama fork) with tokio-rustls and rustls-webpki (mTLS), tokio (async runtime), rayon (thread pools), bincode (encoding via `bc2wrap`), aws-sdk-s3 (S3 storage), MinIO (S3 stand-in in the harness), AWS KMS and AWS Nitro Enclaves, OpenTelemetry and Prometheus (observability), and Kubernetes and Helm charts (deployment).

## Sources

- https://www.zama.ai
- https://docs.zama.org/protocol/protocol/overview/kms (redirected from https://docs.zama.ai/protocol/protocol/overview/kms)
- https://docs.zama.org/protocol/protocol/overview/gateway
- https://docs.zama.org/protocol/zama-protocol-litepaper
- https://www.zama.org/post/introducing-zama-threshold-key-management-system-tkms
- https://www.zama.org/post/zama-protocol-testnet-update-mpc-partners-better-performance-audits-and-new-features
- https://www.zama.org/post/decentralized-key-generation-for-zama-mainnet-has-successfully-completed
- https://github.com/zama-ai/fhevm/tree/main/kms-connector
- https://raw.githubusercontent.com/zama-ai/fhevm/main/kms-connector/docs/architecture.md
- https://trailofbits.com/library/zama/
- https://eprint.iacr.org/2023/815 (Noah's Ark, cited by the repo, not fetched)
- https://github.com/zama-ai/kms
- [README.md](../../README.md)
- [ai-docs/ARCHITECTURE.md](../../ai-docs/ARCHITECTURE.md)
- [docs/SUMMARY.md](../../docs/SUMMARY.md)
- [docs/getting-started/concepts.md](../../docs/getting-started/concepts.md)
- [docs/explanations/trust_model.md](../../docs/explanations/trust_model.md)
- [docs/explanations/node.md](../../docs/explanations/node.md)
- [docs/explanations/network_doc.md](../../docs/explanations/network_doc.md)
- [docs/guides/entry_points.md](../../docs/guides/entry_points.md)
- [docs/guides/core_client.md](../../docs/guides/core_client.md)
- [docs/references/api/core_grpc.md](../../docs/references/api/core_grpc.md)
- [docs/operations/quickstart.md](../../docs/operations/quickstart.md)
- [docs/operations/advanced/metrics.md](../../docs/operations/advanced/metrics.md)
- [docs/operations/advanced/troubleshooting.md](../../docs/operations/advanced/troubleshooting.md)
- [docs/operations/advanced/common-errors.md](../../docs/operations/advanced/common-errors.md)
- [CHANGELOG.md](../../CHANGELOG.md)
- [Cargo.toml](../../Cargo.toml) (dependency list only)
- [antithesis/scratchbook/inputs.md](inputs.md)
- [antithesis/scratchbook/sut-analysis.md](sut-analysis.md)
- Local `git log` of this checkout (commit titles and bodies only)
