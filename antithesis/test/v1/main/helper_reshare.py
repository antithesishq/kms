"""What the reshare driver needs besides the reshare itself: the key to reshare and the
digests its request carries, every party's public-key digest, and the decryption under the
source epoch afterwards. Not a command; Test Composer skips helper_ files.
"""
from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, STATE_DIR, cli_connected, cli_unreached_party,
                           fetch_public, key_digest, keys_on_every_core, now_s, pick, pick_value, pool, run_cli,
                           sleep, write_client_config)
from helper_grpc import call_with_request_id, core_addresses
from helper_properties import judge_source_decrypt


def pick_reshare_key():
    """(key ID, preprocessing ID) of a key every core holds, among those this container
    generated (the file in keys/ holds the preprocessing ID), or None."""
    everywhere = set(keys_on_every_core())
    keys = [k for k in pool("keys") if k in everywhere]
    if not keys:
        return None
    key_id = pick(keys)
    try:
        with open(f"{STATE_DIR}/keys/{key_id}") as f:
            preproc_id = f.read().strip()
    except FileNotFoundError:
        return None
    return (key_id, preproc_id) if preproc_id else None


def previous_epoch_params(key_id, preproc_id, source_epoch):
    """new-epoch's --previous-epoch-params for resharing key_id from source_epoch, or None when
    the key material can't be read from MinIO. The request carries the digests of the key's
    public material, and every core compares them with its own copy before it takes part.
    Party 1's copy is the reference: a compressed key has a CompressedXofKeySet, an
    uncompressed one (-u) a ServerKey."""
    status, keyset = fetch_public(f"PUB-p1/CompressedXofKeySet/{key_id}")
    field = "xof_key_digest"
    if status != "ok":
        status, keyset = fetch_public(f"PUB-p1/ServerKey/{key_id}")
        field = "server_key_digest"
    pk_status, public_key = fetch_public(f"PUB-p1/PublicKey/{key_id}")
    if status != "ok" or pk_status != "ok":
        return None
    return (f"context_id:{DEFAULT_CONTEXT_ID};epoch_id:{source_epoch};previous_keys:[key_id={key_id},"
            f"preproc_id={preproc_id},{field}={key_digest(keyset)},public_key_digest={key_digest(public_key)}]")


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
    False only on a wrong plaintext or malformed arguments."""
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
