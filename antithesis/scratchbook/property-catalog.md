---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: https://docs.zama.org/protocol/protocol/overview/kms
    why: guaranteed output delivery and robustness claims behind Guarantees 1, 2 and 4
  - path: https://docs.zama.org/protocol/zama-protocol-litepaper
    why: robustness claim behind Guarantee 1
---

# Property Catalog

## Scope

This catalog has exactly one property per guarantee in [guarantees.md](guarantees.md), five in
all, with the same slugs. It's a speedrun catalog: far below the usual ~15 properties, on
purpose. Every property is black-box. Its check uses only what a client sees over the service
gRPC API (`:50100`) and the public S3 storage (MinIO), and none needs SUT-side instrumentation.
The checks run in the `kms-core-client` pod, mostly through the stock `kms-core-client` CLI.
Where the CLI can't express a check, the evidence file says what workload-side helper is needed.

No guarantee is `n/a on Zama KMS`: the system and its API can express all five. Guarantee 5
(request-ID retries) needs a workload-side helper, because the CLI always picks a fresh random
request ID.

| Guarantee | Slug | Type | Priority | Status |
|---|---|---|---|---|
| [Guarantee 1](guarantees.md#guarantee-1) | [public-decrypt-returns-encrypted-plaintext](#public-decrypt-returns-encrypted-plaintext) | Safety | 1 of 5 (highest) | implemented (stock-CLI limits in the evidence file) |
| [Guarantee 2](guarantees.md#guarantee-2) | [recovers-after-faults](#recovers-after-faults) | Liveness | 2 of 5 | implemented |
| [Guarantee 3](guarantees.md#guarantee-3) | [reshare-preserves-key](#reshare-preserves-key) | Safety | 3 of 5 | implemented (stock-CLI limits in the evidence file) |
| [Guarantee 4](guarantees.md#guarantee-4) | [user-decrypt-returns-encrypted-plaintext](#user-decrypt-returns-encrypted-plaintext) | Safety | 4 of 5 | implemented (four-core config only) |
| [Guarantee 5](guarantees.md#guarantee-5) | [decrypt-request-id-retries](#decrypt-request-id-retries) | Safety | 5 of 5 | not implemented |

Two facts about the client constrain every property (details in
[sut-analysis.md](sut-analysis.md#the-client-cli)):

- The CLI opens a gRPC connection to **every** configured core before it sends anything, and fails
  the whole run if one refuses. While a core pod is down or not ready, every CLI run fails before
  a request is sent. A config listing three cores with `num_parties = 4` works around this for
  public decryption.
- The CLI's exit code is 0 on success, 1 for an error returned from the command, 101 for a panic
  (`new-epoch` reports every failure that way), and 2 for an argument error. The scripts tell a
  wrong result from a failed one by matching the error text.

## Category: Decryption correctness under faults

Decryption is the KMS output that clients act on. Public decryption results go on chain, and user
decryption results are what a dApp user sees. These properties check that the cluster never
returns, under its own signatures, a plaintext that differs from the one encrypted, whichever
parties crash, restart or lose connectivity while the MPC runs.

<a id="public-decrypt-returns-encrypted-plaintext"></a>
### public-decrypt-returns-encrypted-plaintext — Public decryption never returns a wrong plaintext

| | |
|---|---|
| **Guarantee** | `guarantee-1` |
| **Type** | Safety |
| **Priority** | 1 of 5 (highest) |
| **Status** | implemented (stock-CLI limits in the evidence file) |
| **Property** | Every successful public-decryption response from any KMS party carries exactly the plaintext the workload encrypted, for every ciphertext in the batch. A "successful response" is a gRPC OK from `GetPublicDecryptionResult` or `PublicDecryptSync` whose signature verifies under that party's published key. This must hold whatever faults hit the cores, their network, or MinIO during the decryption. |
| **Invariant** | Workload-side `Always(ok, "public decryption response carries the encrypted plaintext")`, evaluated once per (request, party) pair that returns OK with a payload whose signature verifies under that party's published verification key. The gate is **only** that payload signature: full request-bound validation would reject a mixed-up result and skip it instead of reporting it. `ok` = `payload.request_id` equals the request ID that was sent, and every `payload.plaintexts[i]` equals the expected plaintext for slot `i` (same FHE type and value). The expected plaintexts always belong to the **original** request for that ID, so a reused ID must be resent byte-for-byte. Error responses (`Unavailable`, `NotFound`, `Internal`, `Aborted`, `AlreadyExists`, transport errors) are not evaluated: availability is [recovers-after-faults](#recovers-after-faults). **Why `Always`:** one wrong plaintext is a violation, and an `Always` that's never reached also fails, which catches a run where no decryption ever succeeds. The workload evaluates it per CLI run; the CLI checks every response it collects (all of them with `-a`), so a wrong response from any collected party fails the run (see the evidence file). |
| **Antithesis Angle** | n = 4, t = 1. The windows that matter: (1) kill or restart one core during the online MPC rounds of a decryption; (2) partition one core so sessions run with a party missing; (3) restart a core, then resubmit the same request ID byte-identically, while peers still hold `Active` or `Completed` network sessions under the same derived session IDs; (4) retry a failed request ID (the meta-store redo path) while peers still hold state for it; (5) `PublicDecrypt` and `PublicDecryptSync` for one ID, so sync attaches to an in-flight entry; (6) batches, so sibling sessions (`ctr` = 0..k) run in parallel; (7) decrypt under reshared epochs, including unconfirmed ones. Values are random and distinct per request and per slot where the type allows, so a result for the wrong request or slot shows as a mismatch. |
| **Why It Matters** | A signed wrong public decryption is the most damaging correctness failure the KMS can produce: the gateway publishes it on chain, where it can't be undone. The client's majority check (`num_majority = 2`) fails if honest parties agree on the wrong value, for example after a fault-path defect reuses stale session state. Checking against ground truth catches that. |

**Open Questions:**

- Can a restarted party's new attempt, under the same derived session ID, line up in round number with a peer's still-running old session, so that the peer accepts a message from the wrong attempt? `(partial: messages carry a round_counter; stale rounds are dropped and future rounds buffered, so alignment needs the restarted party to reach the peer's round without the peer's earlier messages; the robust protocol's handling of missing parties was not traced)`
- Does a restarted core lose its epoch? `(partial: an earlier deployment kit's README claimed so; a code trace found that at boot a core re-stores the default context and loads every stored epoch, see the evidence file)`

<a id="user-decrypt-returns-encrypted-plaintext"></a>
### user-decrypt-returns-encrypted-plaintext — User decryption never reconstructs a wrong plaintext

| | |
|---|---|
| **Guarantee** | `guarantee-4` |
| **Type** | Safety |
| **Priority** | 4 of 5 |
| **Status** | implemented in `parallel_driver_user_decrypt.sh` (four-core config only, see Open Questions) |
| **Property** | Every plaintext the client reconstructs from the cores' signcrypted user-decryption shares equals the value the workload encrypted, or the client reports an error. It never reconstructs a different value, whatever faults hit the cores, their network or MinIO. |
| **Invariant** | Workload-side `Always(ok, "user decryption reconstructs the encrypted plaintext")`, evaluated once per `kms-core-client user-decrypt from-args` run that ends either with a reconstructed plaintext (exit 0) or with the CLI's own mismatch error (`user decryption result mismatch: expected …, got …`, exit 1). `ok` is true on exit 0 and false on the mismatch. The CLI has already authenticated each response (signature, link to the request, consensus on degree and slot metadata) and needs 2t + 1 = 3 authenticated responses before it reconstructs, so a false `ok` means authenticated shares rebuilt a wrong value. Every other error (too few responses, failed authentication, failed reconstruction, transport errors) is the "or an error" side of the guarantee and is not a violation; it's recorded for triage. **Why `Always`:** one wrong value is a violation, and an `Always` that's never reached also fails, so a run where no user decryption ever succeeds fails too. |
| **Antithesis Angle** | The same fault windows as public decryption (crash, restart, partition during the per-party partial decryption; restart then resubmit). Two differences: reconstruction needs 3 of 4 responses (no slack beyond one missing core), and each party's share is masked with fresh randomness and signcrypted to a per-request ML-KEM key, so a share from another request or another attempt fails to un-signcrypt instead of decoding to a value. Vary types, values, `--batch-size`, `--sync`, `-a`, compression and epochs (including reshared ones). |
| **Why It Matters** | User decryption is how a dApp user reads their own balance. A wrong value is silently wrong data. A past fix (user decryption returning 0 when every signcryption failed) shows this path can produce a plausible wrong value instead of an error. |

**Open Questions:**

- Does the client's threshold derivation (`(n − 1) / 3` from the configured cores) break when the workload lists only three cores, which public decryption can use to run while one core is down? `(answered: yes. With three configured cores the client expects degree 0 and rejects the cores' degree-1 shares in the pivot check, so the user-decryption driver always uses the four-core config and fails at connect while a core is down)`

## Category: Availability and recovery

<a id="recovers-after-faults"></a>
### recovers-after-faults — The cluster serves decryptions again after faults stop

| | |
|---|---|
| **Guarantee** | `guarantee-2` |
| **Type** | Liveness |
| **Priority** | 2 of 5 |
| **Status** | implemented |
| **Property** | Once fault injection stops, a new public decryption that needs all four cores' answers succeeds within the recovery window, so every core that was killed, stopped or cut off has rejoined. |
| **Invariant** | Probe operation: `kms-core-client -a public-decrypt from-args` with the four-core config and a fresh random value under the workload's key and the kms-init epoch, async or `--sync`, each attempt bounded by `timeout 90` (and the time left), repeated every 10 s, in the command `eventually_recovers_after_faults.sh`. Two `Always`s, so triage shows which bound failed: `Always(connected, "every core accepts client connections within 600 s after faults stop")`, where connected means an attempt got past the CLI's connect to all four cores (it logs that with `-l`) within 600 s of the command's start; and, once that holds, `Always(ok, "public decryption answered by all four cores succeeds within 300 s of every core accepting connections")`, with the 300 s counted from the start of the first attempt that connected. A successful attempt also passes Guarantee 1's plaintext check. `Sometimes("a core the client could not connect to after faults stopped accepted connections again")` and `Sometimes("public decryption answered by all four cores succeeded after a failed first attempt once faults stopped")` show that a real recovery was tested. Faults stop because it is an `eventually_` command (Test Composer reference: "All faults stop across all containers when an eventually command starts"); it also opens a 1020 s quiet window with `$ANTITHESIS_STOP_FAULTS`. The evidence file explains why 300 s measured from "faults stop" isn't safe on its own. |
| **Antithesis Angle** | Pod kill and stop of cores (rescheduling, boot from MinIO, readiness), partitions that leave peers holding dead HTTP/2 connections (keepalive 15 s + 30 s), clock jitter on keepalive and backoff timers, a stop or kill landing just before faults end, and two overlapping pod faults (more than t). Strobing (`custom.strobe_quiet_*`) gives many quiet windows per run; each one is a chance to check recovery. |
| **Why It Matters** | "Guaranteed output delivery" is a headline promise of the Zama Protocol. A core that can't rejoin after a restart or a partition leaves the cluster one failure away from an outage, and a fix landed in September 2026 because a running party couldn't reach a restarted one. |

**Open Questions:**

- How long does `kms-server` take to boot under Antithesis with `Test` parameters, and how fast does that grow with the number of reshared epochs it has to load? Not measured yet.
- Is the 600 s readiness bound enough when a core sits in `CrashLoopBackOff` at its 300 s cap when faults stop? It should be (300 s backoff + boot + 15 s readiness), but boot time is unmeasured.

## Category: Key management under faults

<a id="reshare-preserves-key"></a>
### reshare-preserves-key — Resharing keeps the same FHE key

| | |
|---|---|
| **Guarantee** | `guarantee-3` |
| **Type** | Safety |
| **Priority** | 3 of 5 |
| **Status** | implemented: (a) via the drivers plus Guarantee 3 `AlwaysOrUnreachable`s on reshared-epoch decryptions, (b) without the signed-digest half (the CLI does not print the result digests), (c) as a plaintext check only |
| **Property** | Resharing the key into a new epoch, while decryptions run and faults hit, keeps the same FHE key: decryptions under every epoch that a reshare reported done return the encrypted plaintexts, every core's public key for that key ID is byte-identical before and after, and a reshare that fails leaves the epoch it reshared from serving decryptions. |
| **Invariant** | Three workload-side checks. (a) Decryptions under a reshared epoch are covered by Guarantee 1's and Guarantee 4's `Always` (the drivers pass `--epoch-id`). (b) `Always(ok, "public key unchanged by a reshare")`: before the reshare the command reads `PUB-p<i>/PublicKey/<key_id>` from MinIO for all four parties and takes its digest (SHAKE-256/32 of `PDAT_KEY` + bytes); after `new-epoch` returns, successful or not, it reads them again. `ok` = every party's digest is unchanged, and when the CLI succeeded, the `PublicKey` digest in every core's signed reshare result equals it. (c) `Always(ok, "source epoch still serves after a failed reshare")`: after a `new-epoch` that failed, a public decryption under the source epoch is attempted (bounded retries); `ok` is false only when that decryption returns a wrong plaintext, or when it fails although all four cores accept connections and a decryption under the source epoch had succeeded right before the reshare. The existing `Always(ok, "key reshare result from every KMS party matches the reshared key")` stays. **Why `Always`:** each is a must-hold invariant on every evaluation, and each must be reached in a run. |
| **Antithesis Angle** | Crash, stop or partition a core during the PRSS init or the reshare rounds; cut a core off from MinIO during the reshare's storage phase, which is the documented rollback path (network faults on MinIO must stay enabled); run reshares from reshared epochs (chains), concurrent reshares from one source, and decryptions under the source epoch while the reshare runs. |
| **Why It Matters** | Resharing is how operators refresh shares after a compromise or a lost share. Five resharing fixes landed between August and October 2026, including one where a failed reshare deleted public keys and one where parties signed digests of re-serialized keys that didn't match the published material. |

**Open Questions:**

- After a reshare whose MPC part failed (not its storage part), the new epoch stays registered on the parties that finished PRSS init, with no key share. Is that the intended "failed reshare" state? `(partial: read in new_mpc_epoch; rollback runs only for storage failures)`
- After a reshare and a restart, a core answers `GetKeyGenResult` from the epoch with the byte-wise largest ID. Does a client fetching a keygen result for an earlier epoch then fail verification? Not researched; a candidate for a later property.

## Category: Request-ID semantics

<a id="decrypt-request-id-retries"></a>
### decrypt-request-id-retries — Retries under one request ID get a documented reply

| | |
|---|---|
| **Guarantee** | `guarantee-5` |
| **Type** | Safety |
| **Priority** | 5 of 5 |
| **Status** | not implemented |
| **Property** | Re-sending a decryption request byte-identically under the same request ID, after a timeout, an error or a core restart, gets one of the replies the documentation allows for the earlier attempt's state on that core, and every result returned under that ID carries the original request's plaintexts. |
| **Invariant** | Workload-side, per (resend, core): `Always(ok, "resent decryption request gets a documented reply")`. Allowed replies: async `PublicDecrypt`/`UserDecrypt` → OK (the ID was unknown: never seen, the core restarted, or the entry was evicted; or the earlier attempt failed and is redone) or `AlreadyExists` (pending, succeeded or deleted); sync variants → the result, `Unavailable` (still pending), or the error of a redo; any call → the transient codes that any request can get under faults (`Unavailable` for transport errors, `ResourceExhausted`, `NotFound` for an epoch or key the core doesn't hold). `ok` is false for any other code, and false whenever a result returned for the ID carries plaintexts other than the original ones (`Always` shared with Guarantee 1's check). `Sometimes` markers: a resend after the core restarted, a resend after a failed attempt, a sync resend that attached to a pending attempt. **Why `Always`:** the reply set is a contract on every call. |
| **Antithesis Angle** | Pod kill or stop of a core between the first send and the resend (empties its meta store and network session store while peers keep theirs); partitions that make the first attempt time out or fail; concurrent resends of one ID to one core; async and sync mixed for one ID. |
| **Why It Matters** | The KMS connector re-sends requests under the same ID after errors and core restarts. A reply outside the documented set strands a request, and a result that doesn't match the original ciphertexts is a wrong decryption delivered to the gateway. |

**Open Questions:**

- A redo of a failed attempt on a core that didn't restart re-runs MPC sessions whose IDs are still `Completed` in that core's network session store, which keeps them for `session_cleanup_interval_secs` (24 h). The redo then fails at once. The documented behaviour ("runs the decryption again") is technically met, but such a redo can never succeed within a run. Is that intended? `(partial: traced in code, see the evidence file; not observed)`

## File-level Open Questions

- Boot time of `kms-server` under Antithesis with `Test` parameters, and the time insecure keygen
  takes in the `first_` command, are unmeasured. They bound how many operations a timeline gets
  and feed Guarantee 2's window.
- ~~The deployment's init container writes a broken core config if it can't list the peer CA
  certificates in MinIO when a core pod starts.~~ `(resolved: the init containers in
  31..34-kms-core-*.yaml now retry until they have all four certificates, up to 600 s, then exit
  non-zero so kubelet retries; see deployment-topology.md)`
