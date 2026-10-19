---
sut_path: /home/avpai/src/customer/customer-zama/sut/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229  # plus the uncommitted Antithesis kit changes (sut/kms-changes.patch)
updated: 2026-10-16
external_references: []
---

# Property Catalog

## Scope

The user asked for **one black-box property** and said not to build a full catalog. This file
therefore holds a single property, which is intentionally far below the usual ~15-property
target. "Black-box" here means the check uses only what a client sees over the service gRPC API
and public S3 storage. It needs no SUT-side instrumentation.

## Category: Decryption correctness under faults

Public decryption is the KMS output that FHEVM publishes on chain. These properties check that the
threshold cluster never returns, under its own signature, a plaintext that differs from the one
encrypted. That must hold no matter which parties crash, restart, or lose connectivity while the
MPC runs.

### public-decrypt-returns-encrypted-plaintext — Public decryption never returns a wrong plaintext

| | |
|---|---|
| **Type** | Safety |
| **Property** | Every successful public-decryption response from any KMS party carries exactly the plaintext the workload encrypted, for every ciphertext in the batch. A "successful response" is a gRPC OK from `GetPublicDecryptionResult` or `PublicDecryptSync` whose signature verifies under that party's published key. This must hold whatever faults hit the cores, their network, or MinIO during the decryption. |
| **Invariant** | Workload-side `Always(ok, "public decryption response carries the encrypted plaintext")`. It is evaluated once per (request, party) pair that returns OK with a payload whose signature verifies under that party's published verification key. The gate is **only** that payload signature. Full request-bound validation (`process_decryption_resp` with `Some(request)`) would reject a mixed-up result and skip it instead of reporting it. `ok` = `payload.request_id` equals the request ID that was sent, and every `payload.plaintexts[i]` equals the expected plaintext for slot `i` (same FHE type and value). Expected plaintexts always belong to the **original** request for that ID. The core assumes a known request ID carries the same ciphertexts as before (`ai-docs/ARCHITECTURE.md:50`), so the workload must resend a reused ID byte-for-byte. Reusing an ID with new ciphertexts is workload misuse, not a defect. Error responses (`Unavailable`, `DeadlineExceeded`, `Internal`, `AlreadyExists`, `NotFound` after a restart, and so on) are **not** evaluated, because availability belongs to a separate liveness property. A response whose signature does not verify is not evaluated either. That is an authentication question for a separate property. **Why `Always`:** a single wrong plaintext is a violation, so this is a must-always invariant. Antithesis also fails an `Always` that is never reached. A run where no decryption ever succeeds therefore also fails, which catches a vacuous pass. That is why `AlwaysOrUnreachable` would be the wrong fit. Add no SUT-side assertion: the workload alone can observe the condition exactly. |
| **Antithesis Angle** | The cluster is n = 4, t = 1. The timing windows that matter: (1) kill or restart one core during the online MPC rounds of a decryption session; (2) partition one core from its peers so sessions run with a party missing until `network_timeout` (300 s) passes; (3) **restart a core, then resubmit the same request ID** (byte-identical request). The restart wipes the in-memory meta store and network session store, so the restarted party rebuilds MPC sessions under the same derived session IDs (`req_id.derive_session_id_with_counter(ctr)`) while its peers may still be mid-protocol or `Completed` on those IDs; (4) retry a failed request ID (`add_or_redo_failed_in_meta_store` redo path, byte-identical request) while peers still hold state for it; (5) send the same request to `PublicDecrypt` and `PublicDecryptSync` so sync attaches to an in-flight async entry; (6) batches of several ciphertexts, so sessions with sibling IDs (`ctr` = 0..k) run in parallel. The workload chooses random values, FHE types, batch sizes, endpoints, and retry or resubmit behavior, so Antithesis can branch on them. Each new request, and each ciphertext in a batch, gets a **distinct** random value wherever the FHE type has room for one (otherwise the slot types vary). That makes result mix-ups detectable: request A's result returned for request B fails the `request_id` check, and slot `ctr = 1` returned for slot 0 mismatches. The stock CLI's `-b` flag repeats one value, so it cannot catch index mix-ups. |
| **Why It Matters** | A signed wrong public decryption is the most damaging correctness failure the KMS can produce. FHEVM publishes the result on chain, where it cannot be undone. The client's built-in defense is majority agreement (`num_majority = 2`), and it fails if the parties agree on the wrong value. That can happen if a fault-path defect shifts every honest party the same way, for example when stale or misaligned session state is reused. Checking each party's response against ground truth (the encrypted plaintext) catches what the client's check misses. |
| **Implementation status** | **Partially implemented** (2026-10-16). The test template `antithesis/test/v1/public_decrypt/` holds thin Python commands around the stock `kms-core-client` CLI. It is mounted into the client pod from the ConfigMap in `config/manifests/41-kms-workload-tests.yaml`. Covered: the Antithesis angles (1), (2) and (6); random FHE types, a value menu per type, `-a`, `--sync`, `-b`, and both ciphertext formats. Not covered: the angles (3), (4) and (5), because the CLI picks a fresh random request ID on each run. Also not covered: responses beyond the first 2 when `-a` is not set, and slot mix-ups, because `-b` repeats one value. Added later on 2026-10-16: `anytime_reshare_key.py` reshares the key into new epochs (chains included) while the drivers run, and the decryption driver also decrypts under those epochs. See the evidence file, "Instrumentation status". |

**Open Questions:**

- Can a restarted party's new attempt, running under the same derived session ID, ever line up in round number with a peer's still-running old session, so that the peer accepts a message from the wrong attempt? `(partial: messages carry a round_counter; stale rounds are dropped and future rounds buffered, so alignment would need the restarted party to reach the peer's current round without the peer's earlier messages; behavior of the robust protocol when parties go missing was not traced)`
- Does a restarted core really orphan its epoch (`Antithesis_RUN/README.md:113-115`), so it cannot decrypt until the deploy script's manual repair, which does not run under Antithesis? `(partial: a code trace on 2026-10-16 found no code that does this; at boot a core loads every epoch, see deployment-topology.md)` If so, scenario (3) never reaches session creation. Kills of two different cores over one run could also leave the cluster permanently below quorum, so the `Always` might never be reached, a false failure.

## File-level Open Questions

- After a restart, a core fills its `GetKeyGenResult` store from the epoch with the
  byte-wise largest ID (`core/service/src/engine/threshold/service/kms_impl.rs:564-571`).
  Reshared epochs (`08…` random) almost always sort above the kms-init epoch (`08…01`). A client
  that fetches a keygen result after a reshare and a restart may therefore get the re-signed
  metadata, whose signature covers the reshared epoch's `extra_data`. Not researched further;
  this could become a property ("a keygen result verifies under the epoch the client names").

- This catalog covers one property by request. A full research pass would add, at least, the
  liveness counterpart (with at most t parties faulted and a quiet period, public decryption
  eventually succeeds), user-decryption reconstruction correctness, keygen agreement across
  parties, and restart and recovery properties. None of these were researched.
