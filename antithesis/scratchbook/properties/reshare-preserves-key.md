---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# reshare-preserves-key

Checks [Guarantee 3](../guarantees.md#guarantee-3) (resharing keeps the key). Catalog entry:
[property-catalog.md](../property-catalog.md#reshare-preserves-key).

## Evidence trail

- **Claim.** Resharing changes "the pseudorandom values that each party hold … but with the public
  key remaining the same" ([entry_points.md](../../../docs/guides/entry_points.md), "Key reshare").
- **Claim.** "A storage failure during resharing rolls the new epoch back on the party that fails …
  Public material that existed before the storage phase remains unchanged"
  ([ARCHITECTURE.md](../../../ai-docs/ARCHITECTURE.md), lines 306-316).
- **History.** Five resharing fixes in August–October 2026, including #792 (a failed reshare deleted
  public keys), #873 (over-eager deletion of epoch data on failure) and #910 (signed digests of
  re-serialized keys that didn't match the stored ones).

## How the CLI reshares

`kms-core-client new-epoch --new-epoch-id <E> --new-context-id <C> --previous-epoch-params
"context_id:<C>;epoch_id:<S>;previous_keys:[key_id=<K>,preproc_id=<P>,xof_key_digest=<D1>,public_key_digest=<D2>]"`
(`core-client/src/lib.rs:1080-1120`, `PreviousEpochParameters` and `NewEpochParameters`). The workload's
[anytime_reshare_key.sh](../../test/v1/public_decrypt/anytime_reshare_key.sh) builds exactly this.
The caller must supply the preprocessing ID the key came from (no public object records it; the
workload keeps it in the client pod's `/tmp`) and the digests of the key's public material
(SHAKE-256/32 of `PDAT_KEY` + the object's bytes, `key_digest` in
[helper_lib.sh](../../test/v1/public_decrypt/helper_lib.sh)).

`do_new_epoch` (`core-client/src/mpc_epoch.rs:113`):

1. Sends `NewMpcEpoch` to every core; **any** core's error fails the run (`:168-172`).
2. Polls `GetEpochResult` on every core every 500 ms while `Unavailable`, up to `--max-iter` times
   (`:192-226`); after that it keeps the last error. `GetEpochResult` doesn't block server-side.
3. Checks every core's result names the expected key and preprocessing IDs (`:235-270`).
4. Downloads the reshared key's public material from **all** parties' public storage (`:300-327`,
   "Did not fetch keys from all parties after resharing"), loads it from the first one, and checks
   every core's signature over it, accepting the new epoch's or the source epoch's `extra_data`
   (`:375-428`, "Signature verification failed for the reshared key").
5. Returns the epoch ID. The CLI's dispatcher calls `do_new_epoch(...).await.unwrap()`
   (`lib.rs:2861-2872`), so **every failure is a panic, exit 101**, with only the gRPC code and a
   generic message.

The CLI does **not** compare the public key before and after: it verifies signatures over whatever
party 1's storage holds now. That's the gap check (b) in the catalog fills.

## Server path

| Path | What happens |
|---|---|
| `core/service/src/engine/threshold/service/epoch_manager.rs:1858` `new_mpc_epoch` | Rate-limiter permit (`:1862`, cost 25); validates; takes an epoch-creation lease (`:1891`, `FailedPrecondition` while a destroy holds it) |
| `epoch_manager.rs:1902-1909` | An epoch ID that already exists → `InvalidArgument` |
| `epoch_manager.rs:1954` `add_req_to_meta_store` | A known epoch request ID → `AlreadyExists` (no redo for epochs) |
| `epoch_manager.rs:1977-2010` (background task) | PRSS init first (`init_epoch`, `:478-540`): writes `EpochData` and **registers the epoch** (`:533-535`). Then the reshare; failure → `Done(Err)` "Resharing failed during epoch creation" |
| `epoch_manager.rs:1680-1720` `initiate_resharing_and_crs_resign` | Session ID from the epoch ID; two-sets session in `NetworkMode::Sync` (per-message wait `network_timeout` = 300 s) |
| `epoch_manager.rs:806` `store_reshared_keys` | Under one lock per party: checks or restores the verified public bytes (`:976`, `reshare_utils.rs:216`), then writes the new private shares and signed metadata |
| `epoch_manager.rs:996-1039` | **Storage** failure → rollback: delete this reshare's private material and the public objects it created, forget the epoch when nothing else is under it, purge the in-memory cache |
| `epoch_manager.rs:2067` `get_epoch_result` | `Unavailable` while pending, `Internal`/`Aborted` after failure, `NotFound` if unknown; on success one `KeyGenResult` per key with `key_digests` (incl. `PublicKey`) and signatures over the new epoch's `extra_data` (`:2108-2123`) |
| `kms_impl.rs:549-566` | At boot, every epoch's key shares are loaded; the keygen-result store takes each key's metadata from the epoch with the byte-wise largest ID |

**A failed reshare, as the client sees it.** The CLI panics (exit 101). Per core, two cases:

- MPC part failed (timeout, missing party): the epoch stays **registered** on cores that finished
  PRSS init, with no key share. A decryption under it on such a core gets `NotFound` ("fhe key not
  found"); the source epoch is untouched. Re-running `new-epoch` with the same epoch ID gets
  `InvalidArgument`, so a retry needs a fresh epoch ID (the workload uses one each run).
- Storage part failed: the documented rollback; afterwards the epoch is gone on that core
  (`NotFound` for context/epoch).

Since the protocol tolerates t = 1, a reshare the CLI reports as failed may still have completed on
three cores; decryptions under such an "unconfirmed" epoch can then succeed with three shares.

## How a client reads the public key and its digest per epoch

- Public material is stored per **key ID**, not per epoch: `PUB-p<i>/PublicKey/<key_id>` and
  `PUB-p<i>/CompressedXofKeySet/<key_id>` (or `ServerKey`) in the `kms-public` bucket, readable
  anonymously over HTTP. A reshare must leave these bytes unchanged on every party.
- Digest: SHAKE-256 with 32-byte output over `PDAT_KEY` followed by the object bytes
  (`hash_versioned`, `core/threshold-hashing/src/lib.rs`), computed by the workload with `openssl dgst
  -shake256 -xoflen 32`.
- The per-epoch **signed** digests come back in the reshare result (`GetEpochResult`), signed over
  that epoch's `extra_data`. `kms-core-client key-gen-result -i <key_id> --epoch-id <E>` re-fetches
  a keygen result and checks its signature for a named epoch (`lib.rs:947-970`); after a reshare and a
  restart, a core answers from the largest epoch ID (catalog open question).

## Client semantics the checker must respect

- **Exit codes:** 0 and "New epoch created" = every core reported success and every check passed;
  101 = any failure (a core rejected or failed, the poll ran out, IDs or signatures wrong). The script
  separates "wrong result" by error text (`Resharing response did not contain the expected`,
  `No resharing response found`, `Signature verification failed for the reshared key`) from "no
  verdict".
- **All four cores required.** The CLI needs all four to accept and finish; a single slow or
  restarted core fails the run. Expect most reshares under pod faults to fail; that's not a
  violation.
- **Concurrency.** Several reshares from one source run concurrently on a core under the lease; their
  storage phases are serialized by a per-party lock.
- **Source epoch while resharing.** Decryptions under the source epoch must keep working during and
  after the reshare; the key read guard is shared, so they aren't blocked by the reshare.
- **Ambiguity.** A failed CLI run doesn't say which cores completed. The checker must not assume the
  new epoch is absent; it records it as "unconfirmed" (the workload does).

## Instrumentation status

| Assertion | Location | Status |
|---|---|---|
| `Always(ok, "key reshare result from every KMS party matches the reshared key")` | `anytime_reshare_key.sh` | present |
| `Always(ok, "public key that every party publishes for a key is unchanged by a reshare")` | `anytime_reshare_key.sh` | present: digests of `PUB-p1..4/PublicKey/<key_id>` before and after `new-epoch`, done or not; a 404 after counts as changed, an unreadable object is skipped. The signed-digest half (result digests) is not checked: the CLI doesn't print them |
| `Always(ok, "public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare")` | `anytime_reshare_key.sh` | present: after every reshare, up to 2 attempts (three-core failover); only a wrong plaintext fails it, availability is not required |
| `AlwaysOrUnreachable` "public decryption under a reshared epoch carries the encrypted plaintext" / "user decryption under a reshared epoch reconstructs the encrypted plaintext" | the two drivers | present: Guarantee 3 attribution of a wrong result under a reshared (confirmed or unconfirmed) epoch |
| `Sometimes` public key read back unchanged / source-epoch decryption succeeded, after a reshare that ended without a verdict | `anytime_reshare_key.sh` | present |
| `Reachable` for a chained reshare, "ended without a verdict", and a public decryption under a reshared epoch | reshare command, public driver | present |

The epoch record and the preprocessing IDs live in the client pod's `/tmp`; a restart of that pod
loses them (the pod is excluded from pod faults for this reason).

## Known closed issues

None recorded yet. Candidates from [system-brief.md](../system-brief.md#known-bugs-and-fixes): #792 (a
failed reshare deleted public keys), #873 (over-aggressive deletion of epoch data on reshare
failure), #907 (reshare failed with `InvalidArgument` when a party's URL changed between contexts),
#910 (signed digests of re-serialized material differed from what was stored), #752.
