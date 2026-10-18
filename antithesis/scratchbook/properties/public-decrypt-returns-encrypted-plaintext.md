---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# public-decrypt-returns-encrypted-plaintext

Checks [Guarantee 1](../guarantees.md#guarantee-1) (public decryption returns the encrypted
plaintext). Catalog entry: [property-catalog.md](../property-catalog.md#public-decrypt-returns-encrypted-plaintext).

## Evidence trail

- **Product role.** [ARCHITECTURE.md](../../../ai-docs/ARCHITECTURE.md) ("System context") describes
  public decryption as the path by which the gateway obtains plaintexts that it publishes on chain.
  The threat model counts "breaking … the correctness of a result" with at most `t` malicious
  parties as in scope.
- **Claimed robustness.** The litepaper and ARCHITECTURE.md call the MPC protocol robust for up to
  `t` corrupt parties. A claim to test, and the reason a wrong result with ≤ t faulted parties is a
  defect.
- **Client's own defense** (`core/service/src/client/public_decryption.rs:57-115`,
  `core/service/src/engine/validation_non_wasm.rs:772`): responses are partitioned by signature
  validity and `min_agree_count` of them must agree. That protects against one deviating party,
  not against a defect that shifts every honest party the same way.
- **Existing encrypt-then-check logic** (`core-client/src/decrypt.rs:266-310`,
  `check_external_decryption_signature`): compares each collected plaintext to the encrypted value
  and bails with `decryption result mismatch: expected …, got …`.

## Relevant code paths

| Path | What happens |
|---|---|
| `core/service/src/engine/threshold/service/public_decryptor.rs:266` `public_decrypt` | Takes a rate-limiter permit (`:275`), validates the request, checks context and epoch (`:303`, `NotFound` for an unknown context or epoch, `session.rs:1221`), takes the FHE key read guard (`NotFound` if this core lacks the key for that epoch) |
| `public_decryptor.rs:373` → `core/service/src/util/meta_store.rs:1026` `add_or_redo_failed_in_meta_store` | Inserts the request ID, or resets a **failed** entry for a redo (`meta_store.rs:818`). Pending, successful or deleted IDs → `AlreadyExists` |
| `public_decryptor.rs:395` `req_id.derive_session_id_with_counter(ctr)` | **Deterministic** MPC session ID per (request ID, ciphertext index). A redo or resubmit reuses the same session IDs |
| `public_decryptor.rs:183-190` | Decryption sessions run in `NetworkMode::Async` |
| `public_decryptor.rs:562-640` | All slots succeed → the payload (plaintexts, verification key, request ID) is signed once and stored; any slot fails → the entry becomes `Done(Err)` |
| `public_decryptor.rs:654` `public_decrypt_sync` | Sync variant. `AlreadyExists` from the async path means "attach" (`:663`) |
| `public_decryptor.rs:678` `get_result` | Waits up to 60 s for a pending entry (`DURATION_WAITING_ON_RESULT_SECONDS`, `consts.rs:66`), then `Unavailable`; checks the stored payload's request ID (`Internal` on mismatch, `:715`) |
| `core/threshold-networking/src/grpc/session_store.rs:19` `SessionStatus` | `Inactive` (messages buffered for an unknown session) / `Active` / `Completed` |
| `core/threshold-networking/src/grpc/manager.rs:72-131` | Background task every `session_update_interval_secs` (60 s): `Active` with a dropped session → `Completed`; `Completed` removed after `session_cleanup_interval_secs` (86400 s); `Inactive` discarded after `discard_inactive_sessions_interval` (900 s) |
| `manager.rs:258-275` | Creating a session whose ID is `Active` or `Completed` → error `Session … already exists and is not inactive` |
| `core/threshold-networking/src/sending_service/session.rs:378-382` | Per-message wait: `network_timeout` (300 s) in Sync mode, `discard_inactive_sessions_interval` (900 s) in Async mode, which decryption uses |
| `core/threshold-execution/src/sharing/open.rs:474-482` | Async robust open tries reconstruction once more than `degree + t` parties are accounted for, so with n = 4 and t = 1 a decryption can finish without the fourth party (assuming degree t) |
| `core/threshold-networking/src/sending_service/session.rs:142-235` `receive` | Round classification: `Less` → dropped as stale, `Equal` → delivered, `Greater` → buffered |
| `core-client/src/decrypt.rs:1108` `do_public_decrypt_once` | Random request ID (`:1129`), send, collect, verify |

Deployment knobs (`antithesis/config/manifests/31-kms-core-1.yaml`): `decryption_mode =
"NoiseFloodSmall"` (`:402`), `network_timeout = 300` (`:409`), `timeout_secs = 360` (`:387`).
Client: `NUM_MAJORITY=2`, `NUM_RECONSTRUCT=3` (`40-kms-core-init.yaml:59-62`).

## Client semantics the checker must respect

What `kms-core-client public-decrypt from-args` does, in order:

1. Reads every core's verification key and address from MinIO (`core-client/src/lib.rs:1953`), and
   connects to **every** configured core (`lib.rs:2029`, `:2038`): seven attempts 100 ms apart
   (`retry!`, `lib.rs:81-97`), with no connect timeout. If one core's Service has no ready pod, the
   connect is refused and the whole run fails with exit 1 **before any request is sent**. If the
   client is partitioned from a core, the connect hangs on the OS SYN timeout (~2 min per attempt)
   and the script's `timeout 300` ends it. So the stock CLI reaches the plaintext check only while
   all four cores accept connections. A per-run `config.toml` listing three cores with
   `num_parties = 4` (`lib.rs:413`) avoids this for public decryption.
2. Fetches the public key and encrypts locally (randomized encryption; `encrypt`, `lib.rs:1702`).
   The batch repeats one ciphertext with distinct handles (`lib.rs:2140-2150`).
3. Async mode (`decrypt.rs:913`): sends `PublicDecrypt` to all cores and needs at least
   `num_expected` accepted (2, or 4 with `-a`). Then polls `GetPublicDecryptionResult`
   (`decrypt.rs:956`), retrying **only** on `Unavailable` (which tonic also returns for transport
   errors), 500 ms apart, at most `--max-iter` times; each poll can block 60 s server-side.
   `NotFound` (core restarted and forgot the ID), `Internal` or `Aborted` (attempt failed) end that
   core's task.
4. Sync mode (`--sync`, `decrypt.rs:859`): sends `PublicDecryptSync` and **re-sends the same
   request** on `Unavailable` or `ResourceExhausted`. That's a byte-identical resend under the same
   request ID; after a core restart it lands as a new request on that core.
5. Stops at the first `num_expected` OK responses (`decrypt.rs:780`) and drops the rest unchecked.
6. Verifies (`decrypt.rs:2172`): signatures, the request link and agreement
   (`process_decryption_resp`), then every collected plaintext against the encrypted value.

Meanings of codes for this property: `Unavailable` = still running or transport error, retry;
`NotFound` = this core doesn't know the request ID (e.g. it restarted), or doesn't hold the
context, epoch or key; `AlreadyExists` = the ID is pending, done or deleted on this core (async
only); `Internal`/`Aborted` = the attempt failed; `ResourceExhausted` = rate limiter or meta store
full. None of these is a wrong result. Only an OK response with a verified signature is evaluated.

## Failure scenario

The workload encrypts `m` and requests public decryption. Faults hit while the request runs: for
example, core 3 restarts mid-session, and the workload resubmits the same request ID. One or more
parties then return OK with `plaintexts[0] = m' ≠ m`, signed under their real key. If two or more
return the same `m'`, the stock client accepts it as the consensus value, and the gateway would
publish it.

## Instrumentation status

| Assertion | Location | Status |
|---|---|---|
| `Always(ok, "public decryption response carries the encrypted plaintext")` | [parallel_driver_public_decrypt.sh](../../test/v1/public_decrypt/parallel_driver_public_decrypt.sh); also evaluated by [eventually_recovers_after_faults.sh](../../test/v1/public_decrypt/eventually_recovers_after_faults.sh) on every `-a` probe | present |
| `Unreachable("public decryption response from a KMS party fails authentication")` | same two commands | present |
| `Sometimes("public decryption succeeded on a retry after an attempt without a verdict")` | driver | present |
| `Sometimes("public decryption succeeded after the client left out a core it could not connect to")` | driver | present |
| `Reachable` markers: `-a`, `--sync`, batches, server-side SnS, three-core config, an attempt without a verdict; reshared epochs (Guarantee 3) | driver | present |

The driver is a thin wrapper around the stock CLI and uses the fallback SDK
(`$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`, [helper_lib.sh](../../test/v1/public_decrypt/helper_lib.sh));
every evaluation carries `{"guarantee": "guarantee-1", "property": "public-decrypt-returns-encrypted-plaintext"}`
in its details, and [assertion-map.json](../assertion-map.json) lists every message.
`Always` is true when the CLI exits 0, and false when the CLI fails with an error that only a
validly signed wrong result causes (the mismatch, no pivot, too few agreeing responses, the
consensus checks); the helper lists the exact strings. The CLI checks every response it collected
(`process_decryption_resp` with `min_agree_count` = the number collected, then the plaintext of
each), so one wrong signed response among the collected ones fails the run.

What a run varies: FHE type and value menu, batch size, compression, client- or server-side SnS,
async with polling or `--sync`, the epoch (kms-init, confirmed or unconfirmed reshares), and the
client config. A run starts with all four cores or with three (one left out at random,
`num_parties = 4`); `-a` only with four. How often a run uses three cores, `-a` and `--sync` is
drawn once per timeline (`timeline_choice`, stored under `/tmp/kms-workload-state/profile/`).
A run makes up to 3 attempts, each a new CLI run (new request ID, fresh encryption of the same
value); an attempt without a verdict is retried after 10 s, and if it didn't get past connecting
(the CLI's `-l` log names the core it was connecting to) the next attempt leaves that core out.
That keeps decryptions going while a core pod is down, which the four-core stock CLI can't.
`first_generate_key.sh` runs insecure keygen with `Test` parameters; `anytime_reshare_key.sh`
reshares into new epochs, which the driver then decrypts under (weights 2:2:1 for kms-init,
confirmed and unconfirmed epochs).

Remaining limits of the stock CLI:

- Without `-a`, only the first 2 responses are checked (with `-a`, all of them).
- The CLI picks a new random request ID per run, so angles (3), (4) and (5) are reached only through
  `--sync` re-sends (see [decrypt-request-id-retries](decrypt-request-id-retries.md)).
- `-b` repeats one ciphertext, so slot mix-ups aren't detectable.
- Authentication runs before the plaintext check, so a request mix-up reports through the
  `Unreachable`, not the `Always`.
- A three-core run sends the request to three cores only, so the fourth core never joins that
  decryption; such runs tolerate no further fault among the three.

## Key observations

- **A redo on the same core fails at once.** After a failed attempt whose MPC session was created,
  that core's network session for the ID stays `Active`/`Completed` for 24 h
  (`session_cleanup_interval_secs`). A redo resets the meta-store entry, but session creation then
  fails with "already exists and is not inactive". Expect this as an availability error.
- **Restart + resubmit.** A restarted core has empty meta and session stores and accepts the
  resubmitted ID as new. Peers whose sessions are `Completed` answer with that status; peers still
  `Active` drop its earlier-round messages as stale. The expected outcome is a failed or timed-out
  attempt on the restarted core, not a wrong value.
- **No false positives from FHE noise under `Test` parameters** (investigation log below).

### Investigation Log

#### Can a restarted party's new attempt line up in round number with a peer's still-running old session?

- Examined: `sending_service/session.rs:142-235`, `grpc/server.rs:355-470`,
  `grpc/manager.rs:72-135, 250-300`, `grpc/session_store.rs`.
- Found: every message carries `(session_id, sender, round_counter)`; only exact-round messages are
  delivered. A restarted party starts at round 0 and needs peer messages it never got to reach a
  peer's round k.
- Not found: whether the robust protocol, after a wait runs out, moves on with a party marked
  missing, which could let a restarted party advance alone (needs more than t missing; should abort).
- Conclusion: `(partial: …)`; alignment looks infeasible but isn't ruled out.

#### Does a restarted core lose its epoch?

- Context: an earlier deployment kit (not in this repo) claimed that a restart rewrites the
  context with an empty epoch list.
- Examined: `kms_impl.rs:543` (`ensure_default_threshold_context_in_storage` on every boot),
  `kms_impl.rs:592-603` and `epoch_manager.rs:456` (every stored `EpochData` is loaded and
  registered at boot).
- Conclusion: `(partial: no code found that drops epochs on restart; not observed in a run)`.

#### Can the `Test` FHE parameters themselves produce a wrong decryption?

- Examined: `core/service/src/consts.rs:21` (`TEST_PARAM = PARAMS_TEST_BK_SNS`),
  `core/threshold-execution/src/tfhe_internals/parameters.rs:1651-1720`.
- Found: all key, encryption, packing key-switch and noise-squashing noise is `t_uniform(0)`.
- Conclusion: **resolved.** A mismatch points to a real defect, so the `Always` needs no tolerance.
  Holds only for keys generated with `Test` parameters.

## Known closed issues

None recorded yet. Candidates from [system-brief.md](../system-brief.md#known-bugs-and-fixes) in this
area: #624 (dropped MPC message), #658 (networking deadlock), #738 (early future-round messages),
#775 (broadcast counted votes twice), #834 (idle active sessions evicted), #887 (no reconnect to a
restarted peer), #58 (failed meta-store entry deleted instead of kept).
