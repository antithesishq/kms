# public-decrypt-returns-encrypted-plaintext

## Evidence trail

- **Product role.** `ai-docs/ARCHITECTURE.md` ("System context", "Communication interfaces")
  describes public decryption as the path by which FHEVM obtains plaintexts that it publishes. The
  service interface trusts its caller. The core is responsible for the correctness of the result,
  and the threat model counts "breaking ... the correctness of a result" with at most `t`
  malicious parties as in scope.
- **Claimed robustness.** ARCHITECTURE.md says the MPC protocol is "maliciously secure and robust"
  (Noah's Ark, eprint 2023/815). This is a claim to test, and it is the reason a wrong result with
  ≤ t faulted parties counts as a defect.
- **Client's own defense** (`core/service/src/client/public_decryption.rs:57-115`):
  `process_decryption_resp` partitions responses by signature validity and requires
  `min_agree_count` responses to agree. The plaintext it returns is "a consensus value". That
  protects against a single deviating party, not against a defect that shifts every honest party
  the same way.
- **Existing encrypt-then-check logic.** `core-client/src/decrypt.rs:266-310`
  (`check_external_decryption_signature`) already compares each collected response's plaintext to
  the expected value and bails with `"decryption result mismatch: expected …, got …"`. This
  confirms that the ground-truth check is natural for this system and that its building blocks
  (`TestingPlaintext`, `TypedPlaintext`) exist for reuse.

## Relevant code paths

| Path | What happens |
|---|---|
| `core/service/src/engine/threshold/service/public_decryptor.rs:266` `public_decrypt` | Validates the request, checks context and epoch, takes the FHE key read guard |
| `public_decryptor.rs:373` → `core/service/src/util/meta_store.rs:1026` `add_or_redo_failed_in_meta_store` | Inserts the request ID, or resets a previously **failed** entry for a redo. Pending or successful IDs → `AlreadyExists` |
| `public_decryptor.rs:395` `req_id.derive_session_id_with_counter(ctr)` | **Deterministic** MPC session ID per (request ID, ciphertext index). A redo or resubmit reuses the same session IDs |
| `public_decryptor.rs:654` `public_decrypt_sync` | Sync variant. A known ID attaches to the existing entry (line 663) |
| `core/threshold-networking/src/grpc/session_store.rs:19` `SessionStatus` | `Inactive` (messages buffered for an unknown session) / `Active` / `Completed` |
| `core/threshold-networking/src/grpc/manager.rs:258-275` | Creating a session whose ID is `Active` or `Completed` → error `"Session … already exists and is not inactive"` |
| `core/threshold-networking/src/grpc/server.rs:385-430` | An incoming message for an unknown session creates an `Inactive` entry and buffers it (capped by `max_opened_inactive_sessions` per sender) |
| `core/threshold-networking/src/sending_service/session.rs:142-235` `receive` | Round classification: `Less` → drop as stale, `Equal` → deliver, `Greater` → buffer |
| `core-client/src/decrypt.rs:913` `send_public_decrypt_requests`; `:956` `spawn_get_public_decrypt_result`; `:2172` `verify_public_decrypt_responses` | Client fan-out, polling (retries on `Unavailable`), and verification |
| `core-client/src/lib.rs:2097` | The CLI collects `num_majority` (2) responses by default, or all `n` with `-a` (`lib.rs:1235`) |

Deployment knobs (`antithesis/config/manifests/31-kms-core-1.yaml`):
`decryption_mode = "NoiseFloodSmall"` (line 402), `network_timeout = 300` (line 409),
`timeout_secs = 360` (line 387). Client: `NUM_MAJORITY=2`, `NUM_RECONSTRUCT=3`
(`40-kms-core-init.yaml`).

## Failure scenario

The workload encrypts `m` and requests public decryption. Faults hit while the request runs:
for example, core 3 restarts mid-session, and the workload resubmits the same request ID. One or
more parties then return OK with `plaintexts[0] = m' ≠ m`, signed under their real key. If two or
more parties return the same `m'`, the stock client accepts it as the consensus value, and FHEVM
would publish it.

## Workload sketch (for antithesis-workload)

- **`first_` command:** generate a key (`preproc-key-gen` + `key-gen`, or `insecure-key-gen`)
  **with `Test` FHE params**, and write its key ID to a shared helper file. The "no false
  positives from FHE noise" result in the investigation log holds only for `Test`. Fetch the
  public key and every party's verification key from MinIO.
- **`parallel_driver_` command, looped:**
  1. **New request** (most iterations): pick a batch size in 1..4. For each slot, pick a random FHE
     type (`ebool` … `euint256`) and a random value, distinct across slots wherever the type has
     room for one (otherwise vary the slot types). Encrypt locally under the public key and use a
     fresh request ID. Distinct values turn slot mix-ups into detectable mismatches. The CLI's
     `-b` repeats one value and would hide them (`docs/guides/core_client.md`, "batch-size").
  2. **Resubmission** (low probability): pick a recent request whose earlier attempt failed or
     touched a core that later restarted, and resend the **byte-identical** request (same
     ciphertexts, handles, domain, extra data). Its expected plaintexts are the original ones. The
     core assumes a known ID carries the same ciphertexts (`ai-docs/ARCHITECTURE.md:50`), and
     `PublicDecryptSync` attaches to the existing entry. Resending new ciphertexts under an old ID
     would fire the `Always` without any SUT defect.
  3. Choose `PublicDecrypt` + poll or `PublicDecryptSync`. Send to all 4 cores. Do not stop at
     `num_majority`; collect whatever each party returns within a bounded time.
  4. For each party that returns OK, verify only the **payload signature** (the internal
     `signature` over `PublicDecryptionResponsePayload`, `core/grpc/proto/kms.v1.proto:407-421`)
     under that party's published key. If it verifies, evaluate the `Always`: `payload.request_id`
     must equal the ID that was sent, and each `plaintexts[i]` must equal the expected plaintext
     for slot `i`. Do not gate on full request-bound validation (`process_decryption_resp` with
     `Some(request)`). It rejects a response carrying another request's result, which would hide
     exactly the mix-up this check should report. Log every non-OK status with its code, for triage
     and for a future liveness property.
- **Implementation choice:** the CLI's `-a` mode requires all `n` responses and fails as a whole
  when one core is down, which hides partial results. A small Rust driver is the better fit. It
  would use the `kms` crate's client helpers in `core/service/src/client/local_crypto.rs`
  (`compute_cipher` at :93, `TestingPlaintext` at :138, `compute_cipher_from_stored_key` at :328;
  `encrypt` in
  `core-client/src/lib.rs:1702`) plus the Antithesis Rust SDK, and evaluate each party's response
  individually.

## Instrumentation status (vs. `existing-assertions.md`)

| Suggested assertion | Location | Status |
|---|---|---|
| `Always(ok, "public decryption response carries the encrypted plaintext")` | workload driver | **partial**: `test/v1/public_decrypt/parallel_driver_public_decrypt.py` |

The first workload is a thin wrapper around the stock CLI, which the user chose over the Rust
driver above. It uses the Antithesis Python SDK, and declares its assertion catalog at runtime.

- **`first_generate_key.py`** runs `insecure-preproc-key-gen` and `insecure-key-gen` with
  `Test` params. `KMS_WORKLOAD_KEYGEN=secure` selects the real DKG. It emits
  `Reachable("workload generated an FHE key")`.
- **`parallel_driver_public_decrypt.py`** runs one `public-decrypt from-args`. It picks a key
  that party 1 publishes in MinIO, a random type and value, and random `-a`, `--sync`, `-b`,
  `--no-compression` and `--no-precompute-sns` flags.
- **`Always` = true** when the CLI exits 0. The CLI verified the signatures, agreement and
  request link of the collected responses. It also compared each plaintext with the encrypted
  value.
- **`Always` = false** when the CLI fails with an error that only a validly signed wrong result
  causes. These are the plaintext mismatch, no pivot, too few agreeing responses, and the
  consensus checks (count, type, request link). The script lists the exact strings.
- **`Unreachable("public decryption response from a KMS party fails authentication")`** fires
  on "Not enough authenticated public decryption responses". A response for another request
  lands here, because its external signature does not cover this request's handles.
- **Reach claims:** success with `-a`, success with `--sync`, a batch, server-side SnS, and
  "public decryption attempt ended without a verdict". The last one shows that faults reach the
  workload.
- **Reshared epochs** (added 2026-10-16). `anytime_reshare_key.py` reshares the key with
  `new-epoch --previous-epoch-params` into a fresh random epoch (`08…`) of the default context.
  The source is the kms-init epoch, or an epoch that an earlier reshare created (a chain).
  - The command records each epoch in `/tmp/kms-workload-state/epochs` in the client container.
    The epoch is **confirmed** when the CLI succeeds and **unconfirmed** when it fails. The CLI
    needs all 4 cores, but the protocol tolerates t = 1, so a failed run can leave an epoch
    that 3 cores completed.
  - The decryption driver then picks the kms-init epoch, a confirmed epoch or an unconfirmed
    epoch (weights 2:2:1) and passes `--epoch-id`. The plaintext `Always` above therefore covers
    reshared shares too. It emits `Reachable("public decryption succeeded under a reshared
    epoch")`.
  - The reshare command emits `Always(ok, "key reshare result from every KMS party matches the
    reshared key")`. It is true when the CLI succeeds. It is false when every core reported the
    reshare as done, but a result names another key or preprocessing ID, or its signature does
    not verify over the published key material. It also emits `Reachable` for a chained reshare
    and for "key reshare attempt ended without a verdict".
  - Inputs that nothing public records: the preprocessing ID (`first_generate_key.py` writes it
    to `/tmp/kms-workload-state/preproc/<key_id>`), and the key digests. The command computes
    each digest from MinIO as `SHAKE-256/32("PDAT_KEY" || object bytes)`, which matches
    `hash_versioned`. This was checked against Python's `shake_256`, not against a live core.
  - The KMS returns only a gRPC code and a generic message to the client
    (`MetricedError` → `Status`). The command therefore cannot tell a rejected request (wrong
    digest or preprocessing ID) from a fault. Both end as "without a verdict". If the request
    is wrong, no reshare ever succeeds, and the must-hit reshare `Always` shows as unreached.
  - The state lives in the client container's `/tmp`. A restart of that container loses it,
    and from then on no reshare runs and no decryption picks a reshared epoch.

Gaps against the workload sketch:

- Without `-a`, the CLI checks the first 2 responses and drops the others unchecked.
- The CLI picks a new random request ID for each run. Resubmission and the redo path (angles 3
  and 4) and sync attaching to an async entry (angle 5) are therefore not exercised.
- `-b` repeats one value, so slot mix-ups are not detectable.
- Authentication runs before the plaintext check, unlike the payload-signature-only gate above.
  Therefore a request mix-up reports through the `Unreachable`, not the `Always`.

No SUT-side assertion is proposed. The condition is fully visible to the workload. A SUT-side
`Reachable` on the redo path (`MetaStore::redo_failed` succeeding) would help Antithesis find
scenario (4). That is guidance for the search, not part of this black-box property, and it is
**missing** too.

## Key observations

- **Redo on the same party can fail fast.** After a failed attempt, the network session for that
  ID is `Completed` until the cleanup interval removes it (`core/threshold-networking/src/grpc/manager.rs:80-130`; the Active → Completed transition is at :114-123). A redo within that
  window fails with "already exists and is not inactive". The workload should expect this failure
  mode and treat it as an availability error, not a violation.
- **Restart + resubmit.** A restarted party has empty meta and session stores, so it accepts the
  resubmitted ID as new. Peers whose sessions are `Completed` answer its messages with status
  `Completed` instead of delivering them. Peers still `Active` on the old session drop its earlier-
  round messages as stale. The expected outcome is a timeout on the restarted party, not a wrong
  value. The property checks that expectation.
- **The redo path reuses PRSS-derived randomness.** Noise-flood masks derive from the PRSS setup
  and the session ID, so a redo uses the same mask. That does not affect correctness and is out
  of scope here. It may matter for a confidentiality review.

## Open questions

- **Can a restarted party's new attempt line up in round number with a peer's still-running old
  session under the same session ID?** If it can, the peer would treat a message from the new
  attempt as the restarted party's contribution to the old attempt. In a robust protocol that
  either gets absorbed as a "corrupt party" input (safe) or, if it lands as a share of the same
  ciphertext computed with different session-local state, could bias the output. If alignment is
  impossible, scenario (3) can only cause availability errors. If it is possible, scenario (3) is
  the top target, and the workload should weight "restart, then resubmit the same ID" heavily.
  `(partial: see investigation log)`
- **Does a restarted core really orphan its epoch?** `Antithesis_RUN/README.md:113-115` says that
  after a party restarts, its context is rewritten with an empty epoch list while the epoch record
  survives, and that the deploy script repairs this by purging `EpochData` and re-running init.
  That repair does not run under Antithesis. If the claim holds, a restarted core rejects
  decryptions at `validate_context_and_epoch` (`public_decryptor.rs:303`), so scenario (3) never
  reaches session creation. Kills of two different cores over one run would also leave only two
  working parties, below the three that n = 4, t = 1 needs, so no decryption would succeed and
  the `Always` would fail as unreached: a false failure caused by the deployment, not the property.
  If the claim does not hold, restarts are fair game. The answer decides whether the run needs a
  repair step, limits on node faults, or a separate property for "a restarted core can still
  decrypt". Not investigated in this pass.

### Investigation Log

#### Can a restarted party's new attempt line up in round number with a peer's still-running old session?

- Examined: `core/threshold-networking/src/sending_service/session.rs:142-235` (`receive`),
  `core/threshold-networking/src/grpc/server.rs:355-470` (incoming message routing),
  `core/threshold-networking/src/grpc/manager.rs:80-135, 250-300` (session store lifecycle and
  session creation), `core/threshold-networking/src/grpc/session_store.rs`.
- Found: every message carries `(session_id, sender, round_counter)`. `receive` delivers only
  exact-round messages, drops stale ones, and buffers future ones. Messages for an unknown session
  are buffered in an `Inactive` entry and handed to whichever local session activates that ID
  next. A restarted party starts the session at round 0. To line up with a peer at round k, it
  must get through rounds 1..k−1, which needs peer messages that the peers sent to the
  pre-restart process.
- Not found: whether the robust decryption protocol, once its wait time for a message runs out,
  moves to the next round with that party marked missing. If it does, the restarted party could
  reach round k by treating all peers as absent, which needs more than t missing parties and
  should abort. That abort logic in `threshold-execution` was not traced.
- Conclusion: tagged `(partial: …)`. Alignment looks infeasible, but it is not ruled out without
  reading the online decryption protocol's handling of missing parties in `threshold-execution`.

#### Can the `Test` FHE parameters themselves produce a wrong decryption (false-positive risk)?

- Examined: `core/service/src/consts.rs:21` (`TEST_PARAM = PARAMS_TEST_BK_SNS`),
  `core/threshold-execution/src/tfhe_internals/parameters.rs:1651-1720`.
- Found: in `PARAMS_TEST_BK_SNS`, the LWE and GLWE noise, the compact-PKE encryption noise, the
  packing key-switch noise, and the noise-squashing GLWE noise (about line 1717) are all
  `t_uniform(0)`. The nominal `log2_p_fail` is −64.
- Not examined: the threshold protocol's noise-flood mask (`NoiseFloodSmall`). The protocol is
  meant to keep it within the decryption bound. If it ever pushed a result out of bounds, that
  would itself be a defect worth reporting, not a false positive.
- Conclusion: **resolved** for the false-positive question. Key and encryption noise contribute
  nothing under `Test` params, so a mismatch points to a real defect. The `Always` needs no
  tolerance. This holds only for keys generated with `Test` params (see the workload sketch).
