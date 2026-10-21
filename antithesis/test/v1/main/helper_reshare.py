"""What the reshare drivers need besides the reshare itself: the keys, source epoch and CRSes
to reshare and the digests the request carries, every party's public-key digest, and the
decryption under the source epoch afterwards. Not a command; Test Composer skips helper_ files.
"""
import hashlib

from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, STATE_DIR, chance, cli_connected,
                           cli_unreached_party, epoch_in_use, epoch_record, fetch_public, key_digest,
                           keys_on_every_core, now_s, pick, pick_value, pool, run_cli, sleep, write_client_config)
from helper_grpc import call_with_request_id, core_addresses
from helper_properties import judge_source_decrypt


def reshare_candidates():
    """{key ID: preprocessing ID} of the keys every core holds, among those this container
    generated (the file in keys/ holds the preprocessing ID)."""
    everywhere = set(keys_on_every_core())
    found = {}
    for key_id in pool("keys"):
        if key_id in everywhere:
            try:
                with open(f"{STATE_DIR}/keys/{key_id}") as f:
                    preproc_id = f.read().strip()
            except FileNotFoundError:
                continue
            if preproc_id:
                found[key_id] = preproc_id
    return found


def pick_reshare_key():
    """(key ID, preprocessing ID) of a key every core holds, or None."""
    candidates = reshare_candidates()
    key_id = pick(sorted(candidates)) if candidates else None
    return (key_id, candidates[key_id]) if key_id else None


def plan_reshare():
    """([(key ID, preprocessing ID)], source epoch) for a reshare, or None: one key, or two 1
    time in 3, from the kms-init epoch, or half the time from a confirmed reshared epoch (then
    among that epoch's keys, which it holds)."""
    candidates = reshare_candidates()
    chained = [e for e in pool("epochs") if epoch_record(e)[1] == "confirmed"
               and all(k in candidates for k in epoch_record(e)[0])]
    source, keys = DEFAULT_EPOCH_ID, sorted(candidates)
    if chained and chance(50):
        source = pick(chained)
        keys = epoch_record(source)[0]
    chosen = []
    for _ in range(min(pick([1, 1, 2]), len(keys))):
        chosen.append(pick([k for k in keys if k not in chosen]))
    return ([(k, candidates[k]) for k in chosen], source) if chosen else None


def pick_crs_to_resign():
    """[(CRS ID, digest)] of 1 or 2 CRSes from crs/ to re-sign in a reshare from the kms-init
    epoch, which holds them, half the time, or []. The digest is SHAKE-256/32 of the PDAT_CRS
    domain separator and party 1's CRS object (DSEP_PUBDATA_CRS in core/service/src/engine/base.rs)."""
    crs_ids = pool("crs")
    if not crs_ids or not chance(50):
        return []
    chosen = []
    for _ in range(min(pick([1, 2]), len(crs_ids))):
        crs_id = pick([c for c in crs_ids if c not in [x for x, _ in chosen]])
        status, data = fetch_public(f"PUB-p1/CRS/{crs_id}")
        if status == "ok":
            chosen.append((crs_id, hashlib.shake_256(b"PDAT_CRS" + data).hexdigest(32)))
    return chosen


def previous_epoch_params(keys, source_epoch, crs=()):
    """new-epoch's --previous-epoch-params for resharing keys ([(key ID, preprocessing ID)])
    and re-signing crs ([(CRS ID, digest)]) from source_epoch, or None when key material can't
    be read from MinIO. The request carries the digests of each key's public material, and
    every core compares them with its own copy before it takes part. Party 1's copy is the
    reference: a compressed key has a CompressedXofKeySet, an uncompressed one (-u) a ServerKey."""
    entries = []
    for key_id, preproc_id in keys:
        status, keyset = fetch_public(f"PUB-p1/CompressedXofKeySet/{key_id}")
        field = "xof_key_digest"
        if status != "ok":
            status, keyset = fetch_public(f"PUB-p1/ServerKey/{key_id}")
            field = "server_key_digest"
        pk_status, public_key = fetch_public(f"PUB-p1/PublicKey/{key_id}")
        if status != "ok" or pk_status != "ok":
            return None
        entries.append(f"key_id={key_id},preproc_id={preproc_id},{field}={key_digest(keyset)},"
                       f"public_key_digest={key_digest(public_key)}")
    params = f"context_id:{DEFAULT_CONTEXT_ID};epoch_id:{source_epoch};previous_keys:[{';'.join(entries)}]"
    if crs:
        params += ";previous_crs:[" + ";".join(f"crs_id={c},digest={d}" for c, d in crs) + "]"
    return params


def wait_epoch_settled(epoch_id, bound=300):
    """After a new-epoch run that didn't finish, wait (at most bound seconds) until no core
    answers GetEpochResult with UNAVAILABLE, which is how a core reports an epoch still in
    progress (or that it can't be reached): the cores keep resharing after the CLI gives up,
    and the caller holds the lifecycle lock until then."""
    deadline = now_s() + bound
    while now_s() < deadline:
        outcomes = [call_with_request_id(a, "GetEpochResult", epoch_id, timeout=20) for _, a in core_addresses()]
        if "error=UNAVAILABLE" not in outcomes:
            return
        sleep(5)
    print(f"epoch {epoch_id} still in progress or unreachable on some core after {bound} s", flush=True)


def public_key_digests(key_id):
    """{party: digest of PUB-p<party>/PublicKey/<key_id>, or "missing" or "unread"}."""
    digests = {}
    for party in (1, 2, 3, 4):
        status, data = fetch_public(f"PUB-p{party}/PublicKey/{key_id}")
        digests[party] = key_digest(data) if status == "ok" else status
    return digests


def check_source_epoch(key_id, source_epoch, details):
    """One public decryption of a fresh value under the source epoch, up to 2 attempts; an
    attempt that couldn't connect to a core is followed by one that leaves it out. Returns
    False only on a wrong plaintext or malformed arguments. Skipped (True) if the source epoch
    is being destroyed or is gone."""
    data_type = pick(["ebool", "euint8", "euint16", "euint32", "euint64", "euint128"])
    value = pick_value(data_type)
    left_out = None
    for attempt in (1, 2):
        write_client_config(left_out)
        args = ["--max-iter", 120, "public-decrypt", "from-args", "--to-encrypt", "0x" + value,
                "--data-type", data_type, "--key-id", key_id]
        if source_epoch != DEFAULT_EPOCH_ID:
            args += ["--context-id", DEFAULT_CONTEXT_ID, "--epoch-id", source_epoch]
        if pick(["async", "async", "sync"]) == "sync":
            args.append("--sync")
        with epoch_in_use(source_epoch) as usable:
            if not usable:
                print(f"source epoch {source_epoch} was destroyed; no source epoch check", flush=True)
                return True
            rc, out = run_cli(args, timeout=300)
        verdict = judge_source_decrypt(rc, out, dict(details, check_data_type=data_type, check_value_hex=value,
                                                     check_left_out=left_out, check_attempt=attempt,
                                                     check_exit_code=rc))
        if verdict in ("wrong", "args"):
            return False
        if verdict == "ok":
            return True
        if not cli_connected(out) and cli_unreached_party(out):
            left_out = cli_unreached_party(out)
        if attempt == 1:
            sleep(10)
    return True
