---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# user-decrypt-returns-encrypted-plaintext

Checks [Guarantee 4](../guarantees.md#guarantee-4) (user decryption returns the encrypted
plaintext). Catalog entry:
[property-catalog.md](../property-catalog.md#user-decrypt-returns-encrypted-plaintext).

## Evidence trail

- **Claim.** "up to `t` of the `n` parties may be malicious, and the protocol still protects the
  secret key and produces correct results" ([trust_model.md](../../../docs/explanations/trust_model.md)).
- **Mechanism.** Each party computes a partial decryption of the ciphertext, masks it with noise
  (noise flooding), and signcrypts the share to the user's ephemeral ML-KEM key. The client
  un-signcrypts at least `2t + 1` shares and reconstructs with error correction
  ([system-brief.md](../system-brief.md#the-system)).
- **History.** `e3c79fa7` (#2552, 2025): user decryption returned 0 when all signcryptions failed,
  a plausible wrong value instead of an error. The guarantee is "the value or an error, never a
  different value".

## Server path

| Path | What happens |
|---|---|
| `core/service/src/engine/threshold/service/user_decryptor.rs:467` `user_decrypt` | Rate-limiter permit (`:477`), request validation, context and epoch check (`:514`, `NotFound`), signcryption key from the request's `enc_key` and `client_address` (`:550`), FHE key read guard (`NotFound` if this core lacks the key for that epoch) |
| `user_decryptor.rs:576` `add_or_redo_failed_in_meta_store` | Same request-ID rules as public decryption: new → insert; failed → redo; pending, done or deleted → `AlreadyExists` |
| `user_decryptor.rs:211` | Session ID `req_id.derive_session_id_with_counter(ctr)` per ciphertext (deterministic) |
| `user_decryptor.rs:344-375` | Partial decryption share signcrypted per ciphertext; the payload carries the signcrypted shares, the party's verification key, degree, link and slot metadata, signed by the party |
| `user_decryptor.rs:622` `user_decrypt_sync` | `AlreadyExists` means attach (`:632`) |
| `user_decryptor.rs:646` `get_result` | Like public decryption: blocks up to 60 s while pending, then `Unavailable`; `Internal`/`Aborted` after failure; `NotFound` if unknown |

## What the CLI's `user-decrypt` does and checks

`kms-core-client user-decrypt from-args --to-encrypt <hex> --data-type <t> --key-id <K>
[--context-id --epoch-id] [-b N] [--sync] [--no-compression] [--no-precompute-sns]`
(dispatch at `core-client/src/lib.rs:2206-2300`):

1. Same start as public decryption: reads verification keys from MinIO, connects to **every**
   configured core (fails with exit 1 if one refuses, `lib.rs:2029, 2038`), encrypts locally. The
   batch repeats one ciphertext with one dummy handle (`lib.rs:2254-2262`).
2. Builds the request with a fresh random request ID and a fresh ephemeral ML-KEM key pair
   (`core-client/src/decrypt.rs:1951-1962`).
3. Async (`decrypt.rs:1755`): per core, sends `UserDecrypt`, then polls `GetUserDecryptionResult`
   while `Unavailable` (500 ms apart, `--max-iter`); a failed submit or any other code ends that
   core's task. Sync (`decrypt.rs:1701`): sends `UserDecryptSync` and re-sends the identical request
   on `Unavailable` or `ResourceExhausted`.
4. Stops at `num_reconstruct` (3) OK responses, or 4 with `-a` (`lib.rs:2211-2215`;
   `decrypt.rs:780`), and drops the rest.
5. Reconstructs (`decrypt.rs:1875` → `core/service/src/client/user_decryption_wasm.rs:160`):
   - authenticates each response (identity, signature, EIP-712 external signature, one per role),
     needs at least `2t + 1` = 3 authenticated (`core/service/src/engine/validation_wasm.rs:730-800`,
     "Not enough correct responses to user-decrypt the data!");
   - majority vote (≥ t + 1) on the invariants: degree, the request link, per-slot type and packing
     ("Cannot find user decryption pivot"); the link must match this request ("not linked to the
     correct request");
   - un-signcrypts each authenticated share; a share that doesn't un-signcrypt or decode is rejected
     as one fault (`user_decryption_wasm.rs:673-760`);
   - reconstructs with error correction, `num_bots = n − accepted`; more than t → "Too many faulty
     user decryption responses"; inconsistent shares → "Not enough shares to reconstruct" or "Error
     reconstructing all blocks" (`user_decryption_wasm.rs:785-830`).
6. Compares every reconstructed plaintext with the encrypted value: `user decryption result
   mismatch: expected …, got …` (`decrypt.rs:1905-1919`). On success prints `User decrypted
   Plaintext … - "request_id": "<id>"` and exits 0.

## Client semantics the checker must respect

- **Wrong vs failed.** Exit 0 = correct value. Exit 1 with `user decryption result mismatch` =
  authenticated shares reconstructed a wrong value: the violation. Every other exit-1 error
  (connect refused, "Only got 2/4 user decrypt responses", authentication, pivot, reconstruction
  failures, transport errors, timeouts) is the "or an error" side of the guarantee. Reconstruction
  and authentication failures are suspicious under crash-only faults (honest parties shouldn't send
  bad shares) and are worth a `Sometimes`-free log line and a look in triage, but they don't break
  the guarantee.
- **No slack.** With one core down, all three remaining responses must authenticate and decode; any
  further fault fails the run (an error, allowed).
- **A core that restarted mid-request** answers `NotFound` to the poll; the CLI drops that core.
- **Request mix-ups can't decode.** Shares are signcrypted to this request's ephemeral key and bound
  to its link, so another request's share is rejected rather than reconstructed. A wrong value can
  only come from authenticated shares of this request that rebuild a wrong plaintext.
- **Fewer configured cores** (to run while a core is down): the client derives the threshold as
  `(n − 1) / 3` from the configured servers when none is given (`core/service/src/engine/validation_wasm.rs:58`),
  so a three-core config gives t = 0, and the pivot check then rejects the cores' degree-1 shares
  ("Pivot user decrypt responses gave degree 1 which does not match expected threshold 0").
  The driver therefore always uses the four-core config.
- **Randomness.** Each request uses a fresh ephemeral key, so a byte-identical resend needs the
  saved request and its secret key (see [decrypt-request-id-retries](decrypt-request-id-retries.md)).

## Workload sketch

A `parallel_driver_user_decrypt.sh` mirroring the public-decryption driver: pick a key from MinIO, an
epoch with `pick_epoch`, a random type and value from the value menu, `-b`, `--sync`, `-a`,
`--no-compression` and `--no-precompute-sns` at random; run under `timeout 300 kms-core-client -f
config.toml --max-iter 120 user-decrypt from-args …`; classify:

- exit 0 → `Always(true, "user decryption reconstructs the encrypted plaintext")`;
- `user decryption result mismatch` → the same `Always` with `false`, plus the CLI output;
- anything else → `Reachable("user decryption attempt ended without a verdict")` with the error.

`Sometimes`/`Reachable` markers: success with `-a`, with `--sync`, with a batch, under a reshared
epoch, and a success while one core's response was missing (3 of 4 collected after the fourth
failed).

## Known closed issues

None recorded yet. Candidates from [system-brief.md](../system-brief.md#known-bugs-and-fixes): #2552
(`e3c79fa7`, user decryption returned 0 when all signcryptions failed), #58 (a failed request's
meta-store entry deleted instead of keeping the error).

## Instrumentation status

Implemented in [parallel_driver_user_decrypt.sh](../../test/v1/public_decrypt/parallel_driver_user_decrypt.sh),
four-core config only (see above).

| Assertion | Status |
|---|---|
| `Always(ok, "user decryption reconstructs the encrypted plaintext")` (exit 0 → true, `user decryption result mismatch` → false) | present |
| `AlwaysOrUnreachable(ok, "user decryption under a reshared epoch reconstructs the encrypted plaintext")` (Guarantee 3 attribution) | present |
| `Sometimes`: success on a retry after an attempt without a verdict; success under a reshared epoch; batched success | present |
| `Reachable`: success with `-a`, with `--sync`, with SnS left to the cores; an attempt without a verdict | present |
| A success with one core's response missing (3 of 4 after the fourth failed) | missing: the CLI logs that only at debug level |
