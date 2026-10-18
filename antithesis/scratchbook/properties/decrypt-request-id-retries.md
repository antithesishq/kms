---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: https://github.com/zama-ai/fhevm/tree/main/kms-connector
    why: the connector re-sends under the same request ID and polls only after a restart
---

# decrypt-request-id-retries

Checks [Guarantee 5](../guarantees.md#guarantee-5) (retries under one request ID behave as
documented). Catalog entry: [property-catalog.md](../property-catalog.md#decrypt-request-id-retries).

## Evidence trail

- **Documented contract** ([trust_model.md](../../../docs/explanations/trust_model.md), "Request IDs
  and replay", lines 59-73; [ARCHITECTURE.md](../../../ai-docs/ARCHITECTURE.md), lines 50-52):
  - the core assumes a known request ID carries the same ciphertexts as before and doesn't compare
    them (line 61), so a resend must be **byte-identical**;
  - `PublicDecrypt`/`UserDecrypt` reject a known ID whose attempt is pending, succeeded or deleted
    with `AlreadyExists`; "If the earlier attempt failed, the core resets the entry and runs the
    decryption again" (line 70);
  - the sync variants "attach": return the stored result, wait for the pending attempt, or retry a
    failed one (line 71);
  - "a reboot empties every meta store", so the core then accepts IDs it processed before (line 65).
- **Who relies on it.** The KMS connector re-sends the same payload under the same ID and, after a
  core restart, polls first and resubmits only if needed.

## Server behaviour per earlier state (one core)

Checks before the meta store can fail any call, whatever the ID's history: `ResourceExhausted`
(rate limiter, `public_decryptor.rs:275`; or meta store full), `InvalidArgument` (malformed),
`NotFound` (context, epoch or key not on this core, `public_decryptor.rs:303, 358-370`), and
`Unavailable` (transport error, as tonic reports it). Then
`add_or_redo_failed_in_meta_store` (`core/service/src/util/meta_store.rs:1026`, redo at `:818`) decides:

| Earlier attempt's state on that core | `PublicDecrypt` / `UserDecrypt` | `…DecryptSync` | `Get…DecryptionResult` |
|---|---|---|---|
| unknown: never seen, core restarted, or entry evicted | OK, a new attempt starts | starts, then waits ≤ 60 s: result, error, or `Unavailable` | `NotFound` |
| pending | `AlreadyExists` | attaches, waits ≤ 60 s: result or `Unavailable` | waits ≤ 60 s, then `Unavailable` |
| done, succeeded | `AlreadyExists` | the stored result | the stored result |
| done, failed | OK, entry reset to pending, **redo** starts | redo, then as "pending" | `Internal`, or `Aborted` if the error mentions abort (`meta_store.rs:1200-1226`) |
| deleted | `AlreadyExists` | `NotFound` | `NotFound` |

Code: `public_decryptor.rs:373` (async), `:654-675` (sync: `AlreadyExists` is defused into an
attach), `:678-730` (result); `user_decryptor.rs:576`, `:622-640`, `:646`. Two concurrent sends of
one ID to one core: exactly one gets OK (the insert-or-redo runs under one write lock).

**Redo caveat (lead, not a finding).** A redo re-derives the same MPC session IDs
(`public_decryptor.rs:395`). If the failed attempt had created its network session, that session is
`Active`/`Completed` in this core's session store until `session_cleanup_interval_secs` (86400 s)
passes (`core/threshold-networking/src/grpc/manager.rs:72-131`), and creating it again fails with
"already exists and is not inactive" (`manager.rs:258-275`). So the redo runs, fails at once, and
the entry is `Done(Err)` again. Only a core restart (empty session store) or 24 h lets a redo of an
in-session failure succeed. The reply is still in the documented set; the result never comes.

**Eviction.** Completed entries stay until the store reaches `dec_capacity` (10000), then the oldest
beyond `min_dec_cache` (6000) are evicted (`meta_store.rs:464-530`). A resend of an evicted ID starts
a new attempt. At the workload's rate this doesn't happen within a run unless tuned
([tuning.md](../tuning.md)).

## Can kms-core-client send a chosen request ID?

**No.** Precisely:

- `public-decrypt` and `user-decrypt` have no request-ID flag (`core-client/src/lib.rs:716-800`,
  `DecryptParameters`, `DecryptFile`). Every run draws a fresh ID: `RequestId::new_random(rng)` at
  `core-client/src/decrypt.rs:1129` (public), `:1951` (user), `:1211` and `:2029` (rate mode), with
  `rng = AesRng::from_entropy()` (`lib.rs:1913`).
- The CLI prints the ID only on success (`core-client/src/bin.rs`, `<msg> - "request_id": "<id>"`). A
  failed run doesn't print or log it before sending, so the workload can't learn the ID of a failed
  attempt.
- The only ID-taking decryption command is `public-decrypt-result -i <id> --handle <hex>…
  [--context-id --epoch-id]` (`lib.rs:988-1020`, dispatch `:2646`): poll-only
  (`GetPublicDecryptionResult` on every core, retried while `Unavailable`), with full verification.
  That's the connector's "poll after restart" half, for IDs from successful runs. There is no
  user-decryption equivalent.
- `encrypt … --ciphertext-output-path F` and `public-decrypt from-file --input-path F`
  (`lib.rs:1633`, `:1702`) reuse the **ciphertext bytes**, but under a fresh request ID.
- **What the stock CLI already covers:** with `--sync`, the CLI re-sends the identical request
  (same ID, same bytes) to a core whenever that core answers `Unavailable` (including transport
  errors while it restarts) or `ResourceExhausted` (`decrypt.rs:859-905` public, `:1701-1750` user).
  After a core restart, that resend lands on an empty meta store and starts a new attempt. It only
  happens while the CLI still waits for that core (with `-a`, or when fewer than `num_majority`
  others have answered), and it never exercises the async `AlreadyExists` reply or the redo of a
  failed attempt (the CLI stops polling a core on `Internal`).

## What a byte-identical resend requires (workload-side helper)

Encryption is randomized, so re-encrypting the value gives different bytes; sending those under the
old ID breaks the binding the core relies on, and a mismatch would be workload misuse. A resend must
reuse the first attempt's exact request:

- **Public decryption.** `PublicDecryptionRequest` (`core/grpc/proto/kms.v1.proto:373-403`): request
  ID, ciphertexts (bytes, FHE type, external handle, format), key ID, EIP-712 domain, `extra_data`
  (from context and epoch), context ID, epoch ID, signing schemes. No client signature or secret, so
  saving the serialized protobuf and sending the same bytes again is enough. The expected plaintexts
  are the original values.
- **User decryption.** `UserDecryptionRequest` (`kms.v1.proto:459-496`) also carries the client
  address and an ephemeral ML-KEM public key; the helper must save the matching secret key to
  un-signcrypt the result (`Client::user_decryption_request` returns `(request, enc_pk, enc_sk)`,
  `core/service/src/client/user_decryption_non_wasm.rs:23`).
- **Recommended helper:** a small Rust binary in the client image, built from this workspace, that
  uses `Client::public_decryption_request` (`core/service/src/client/public_decryption.rs:18`, takes
  `&RequestId`) and the generated `CoreServiceEndpointClient`. Subcommands: `make` (encrypt a value or
  load a `--ciphertext-output-path` file, pick a random ID, write the request protobuf to
  `/tmp/kms-workload-state/requests/<id>.pb` with the expected value), `send <id> <core> async|sync`
  (send the saved bytes to one core, print the gRPC code and any payload), and `result <id> <core>`.
  Verification of returned payloads can reuse `public-decrypt-result -i <id> --handle <hex>`; the CLI's
  handles are deterministic (`integration_test_handles`, `lib.rs:1290-1300`: 32 bytes of `0x17` with
  the first 8 bytes the big-endian slot index). This needs an image rebuild.
- **Not recommended:** `grpcurl` with JSON requests (no grpcurl in the image; ciphertext bytes would
  have to be extracted from the CLI's bincode file).

## Client semantics the checker must respect

- Judge each reply against the state the checker **knows**: after a core restart (the workload can
  see it as a connect failure, or a `NotFound` poll), "unknown" is expected; after an earlier
  `Internal`, "failed" (redo) is expected; while the first attempt may still run, "pending" or
  "done" are both possible, so `AlreadyExists` and OK-after-redo are both allowed. When in doubt,
  allow every reply the table permits for any state the core could be in.
- `NotFound` on a result poll right after a restart is documented behaviour, not a lost result.
- A result that arrives must carry `payload.request_id == id` and the original plaintexts: checked by
  the same comparison as Guarantee 1.
- Results from different cores for one ID may come from different attempts (one core redid it, one
  restarted). All of them must still carry the original plaintexts.

## Known closed issues

None recorded yet. Candidates from [system-brief.md](../system-brief.md#known-bugs-and-fixes): #58
(`64a1b45a`, a failed request's meta-store entry was deleted instead of keeping the error), #2404
(`b6979bae`, MPC session ID derived by hashing the request ID), #887 (reaching a restarted peer).
