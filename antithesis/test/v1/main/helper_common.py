"""Shared by the test commands: SDK output, randomness, value menus, state pools, the
kms-core-client runner and the OP outcome lines.

Every command runs in the kms-core-client container, as user kms. The files whose names
start with helper_ are not commands; Test Composer skips them.
"""
import atexit
import contextlib
import fcntl
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

# The Python SDK writes through libvoidstar when it can load it. Otherwise it writes only to
# $ANTITHESIS_SDK_LOCAL_OUTPUT, so point that at the fallback-SDK file
# ($ANTITHESIS_OUTPUT_DIR/sdk.jsonl) that the shell harness used, or at a local file when
# run by hand. The SDK still prefers libvoidstar. This must happen before the first import
# of antithesis.
_out = os.environ.get("ANTITHESIS_OUTPUT_DIR")
os.environ.setdefault("ANTITHESIS_SDK_LOCAL_OUTPUT", f"{_out}/sdk.jsonl" if _out else "/tmp/antithesis-sdk.jsonl")

from antithesis.random import get_random, random_choice  # noqa: E402

TEMPLATE_DIR = "/opt/antithesis/test/v1/main"
CLIENT_DIR = "/app/kms-core-client"  # config.toml is written here when the pod starts
S3_PUBLIC = "http://minio:9000/kms-public"

# The context and epoch that exist from deploy: kms-server writes the context at boot and
# kms-init creates the epoch (DEFAULT_MPC_CONTEXT, DEFAULT_EPOCH_ID in core/service/src/consts.rs).
DEFAULT_CONTEXT_ID = "07" + "0" * 61 + "1"
DEFAULT_EPOCH_ID = "08" + "0" * 61 + "1"

# State shared by the commands, in the container's /tmp; lost when the container restarts,
# which is harmless. One directory per pool, one file per ID:
#   preproc/<id>        insecure preprocessing IDs not yet given to a keygen
#   preproc-taken/<id>  preprocessing IDs a keygen driver took
#   keys/<key_id>       keys this container generated; the file holds the preprocessing ID
#   first-key/<key_id>  the key first_generate_key.py generated, before faults started
#   pubdec/<id>, userdec/<id>  request IDs of decryptions the CLI completed
#   epochs/<epoch_id>   epochs a reshare created; the file holds "<key_id> confirmed" (every
#                       core reported it done) or "<key_id> unconfirmed" (the CLI failed, so
#                       some cores can hold the epoch and others not)
#   epochs-rejected/<epoch_id>  epochs of reshare requests meant to fail; the file holds why
#   crs/<crs_id>        CRSes the CLI generated; the file holds "secure" or "insecure"
#   profile/<name>      this timeline's draw of a workload knob (timeline_choice)
STATE_DIR = "/tmp/kms-workload-state"

# Keys add memory and boot time to every core, so the drivers stop making new ones here.
MAX_KEYS = 3
# Every reshared epoch holds a copy of a key's shares on each core, loaded at boot, so the
# reshare driver stops here.
MAX_EPOCHS = 6
# CRSes are stored on every core and in MinIO, so the CRS drivers stop generating valid ones here.
MAX_CRS = 6

DATA_TYPES = ["ebool", "euint8", "euint16", "euint32", "euint64", "euint128", "euint160", "euint256"]
BATCH_SIZES = [1, 1, 1, 2, 3]


def pick(options):
    return random_choice(list(options))


def chance(percent):
    return get_random() % 100 < percent


def pick_count(low=1, high=5):
    return pick(range(low, high + 1))


def rand_hex(n_bytes):
    return "".join(f"{get_random() & 0xFF:02x}" for _ in range(n_bytes))


def pick_value(data_type):
    """A little-endian hex value for data_type, as kms-core-client --to-encrypt reads it:
    zero, one, the maximum, only the top bit set, or random bits."""
    if data_type == "ebool":
        return pick(["00", "01"])
    n = int(data_type[len("euint"):]) // 8
    kind = pick(["zero", "one", "max", "top", "random", "random"])
    return {"zero": "00" * n, "one": "01" + "00" * (n - 1), "max": "ff" * n,
            "top": "00" * (n - 1) + "80", "random": rand_hex(n)}[kind]


def pick_decrypt_inputs():
    data_type = pick(DATA_TYPES)
    return {"data_type": data_type, "value_hex": pick_value(data_type), "batch": pick(BATCH_SIZES),
            "no_compression": pick([False, False, False, True]),
            "no_precompute_sns": pick([False, False, False, True])}


def pick_crs_bits(valid=True):
    """--max-num-bits for a CRS: a power of 2 from 1 to 2048 (the server's limit), mostly
    small, since larger ones make a larger CRS and a longer ceremony; with valid=False, or 1
    time in 10, a value the cores must reject (not a power of 2, 0, or past 2048)."""
    if not valid or chance(10):
        return pick([0, 3, 100, 4096])
    return pick([1, 2, 16, 16, 64, 64, 256, 1024, 2048])


def pick_request_id(ids):
    """A request ID for a result RPC: mostly one from the pool, sometimes an unknown one, and
    sometimes a malformed or differently spelled one, from the request-ID limits in
    api-surface.md (all-zero and short IDs are invalid; upper case and 0x are accepted)."""
    kind = pick(["pool"] * 6 + ["fresh", "zero", "upper", "prefixed", "short"])
    if not ids or kind == "fresh":
        return rand_hex(32)
    rid = pick(ids)
    return {"pool": rid, "zero": "0" * 64, "upper": rid.upper(), "prefixed": "0x" + rid,
            "short": rid[:-2]}[kind]


def timeline_choice(name, options):
    """One of options, drawn on the first call in a timeline and kept, so each timeline leans
    its own way. Concurrent first calls can draw differently; the first one stored wins."""
    path = f"{STATE_DIR}/profile/{name}"
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = f"{path}.{os.getpid()}"
        with open(tmp, "w") as f:
            f.write(str(pick(options)))
        try:
            os.link(tmp, path)
        except FileExistsError:
            pass
        os.unlink(tmp)
    with open(path) as f:
        return type(options[0])(f.read())


def record(pool, item, content=""):
    os.makedirs(f"{STATE_DIR}/{pool}", exist_ok=True)
    with open(f"{STATE_DIR}/{pool}/{item}", "w") as f:
        f.write(content)


def pool(name):
    try:
        return sorted(os.listdir(f"{STATE_DIR}/{name}"))
    except FileNotFoundError:
        return []


def pool_matching(name, content):
    """The items of pool name whose file holds content."""
    found = []
    for item in pool(name):
        try:
            with open(f"{STATE_DIR}/{name}/{item}") as f:
                if f.read() == content:
                    found.append(item)
        except FileNotFoundError:
            pass
    return found


def take(name):
    """Move one random ID from pool name to name-taken and return it, or None if empty."""
    os.makedirs(f"{STATE_DIR}/{name}-taken", exist_ok=True)
    for _ in range(5):
        items = pool(name)
        if not items:
            return None
        item = pick(items)
        try:
            os.rename(f"{STATE_DIR}/{name}/{item}", f"{STATE_DIR}/{name}-taken/{item}")
            return item
        except FileNotFoundError:
            continue  # a concurrent driver took it
    return None


def published_keys(party=1):
    """IDs of the keys a party published in MinIO, or [] when MinIO can't be listed."""
    url = f"{S3_PUBLIC}?list-type=2&prefix=PUB-p{party}/PublicKey/"
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            body = resp.read().decode()
    except Exception:
        return []
    return re.findall(rf"<Key>PUB-p{party}/PublicKey/([0-9a-fA-F]+)</Key>", body)


def keys_on_every_core():
    """IDs of the keys all four parties published. A party publishes a key only when its own
    keygen completed, and a keygen driver's key can be missing from a core for good: the CLI
    accepts a keygen two cores finished, and an AbortKeyGen can cancel it on some cores only."""
    everywhere = set(published_keys(1))
    for party in (2, 3, 4):
        everywhere &= set(published_keys(party))
    return sorted(everywhere)


def probe_key():
    """A key every core holds, for a check that needs all four cores to decrypt, preferring
    the one first_generate_key.py made before faults started. None if no such key can be
    confirmed."""
    everywhere = keys_on_every_core()
    preferred = [k for k in pool("first-key") if k in everywhere]
    candidates = preferred or everywhere
    return pick(candidates) if candidates else None


def pick_key():
    """A key to decrypt under: one this container generated, else one party 1 published.
    Nine times in ten only a key every core holds, when there is one: a decryption under a
    key some cores lack waits out the MPC timeout (300 s) and gives no verdict."""
    keys = pool("keys") or published_keys()
    if chance(90):
        everywhere = keys_on_every_core()
        keys = [k for k in keys if k in everywhere] or everywhere or keys
    return pick(keys) if keys else None


def key_count():
    """Keys that exist on at least one core: this container's, or any party's published
    ones, so a key that an abort left on some cores counts too."""
    published = set()
    for party in (1, 2, 3, 4):
        published |= set(published_keys(party))
    return max(len(pool("keys")), len(published))


def new_epoch_id():
    """A random epoch ID. It starts with 08 like DEFAULT_EPOCH_ID, the prefix fhevm expects."""
    return "08" + rand_hex(31)


def epochs_of(key_id, status):
    """The recorded epochs with status (confirmed or unconfirmed) that key_id was reshared into."""
    found = []
    for epoch in pool("epochs"):
        try:
            with open(f"{STATE_DIR}/epochs/{epoch}") as f:
                if f.read().split() == [key_id, status]:
                    found.append(epoch)
        except FileNotFoundError:
            pass
    return found


def pick_epoch(key_id):
    """(epoch ID, status) to decrypt under key_id: the kms-init epoch ("default") 2 times in 5,
    a confirmed reshared epoch 2 in 5 and an unconfirmed one 1 in 5, falling back to the
    default when there is no reshared epoch of the chosen kind."""
    status = pick(["default", "default", "confirmed", "confirmed", "unconfirmed"])
    epochs = epochs_of(key_id, status) if status != "default" else []
    return (pick(epochs), status) if epochs else (DEFAULT_EPOCH_ID, "default")


def fetch_public(path):
    """An object of the kms-public bucket: ("ok", bytes), ("missing", None) when MinIO answers
    404, or ("unread", None) when it can't be read (a network fault)."""
    try:
        with urllib.request.urlopen(f"{S3_PUBLIC}/{path}", timeout=60) as resp:
            return "ok", resp.read()
    except urllib.error.HTTPError as e:
        return ("missing", None) if e.code == 404 else ("unread", None)
    except Exception:
        return "unread", None


def key_digest(data):
    """The digest the KMS takes of a public key object: SHAKE-256/32 of the PDAT_KEY domain
    separator followed by the object's bytes as stored (hash_element in
    core/threshold-hashing/src/lib.rs, DSEP_PUBDATA_KEY)."""
    return hashlib.shake_256(b"PDAT_KEY" + data).hexdigest(32)


@contextlib.contextmanager
def lifecycle(group, wait):
    """Keep key and CRS generation apart from epoch changes. The proto forbids KeyGen,
    AbortKeyGen, CrsGen and AbortCrsGen while NewMpcEpoch runs (the Conditions in
    core/grpc/proto/kms-service.v1.proto), and the server doesn't enforce it, so the workload
    does: group "generate" (keygen, keygen abort) and group "epoch" (new-epoch) exclude each
    other, and calls of one group may overlap. Yields True while held, or False, holding
    nothing, if the other group stayed busy for wait seconds.

    Each group's members hold a shared flock on the group's file. A newcomer takes the gate
    lock, checks that nobody holds the other group's file (a non-blocking exclusive flock on
    it succeeds), joins its own, and lets the gate go. The kernel drops a dead driver's
    locks, so nothing goes stale."""
    os.makedirs(STATE_DIR, exist_ok=True)
    other = "epoch" if group == "generate" else "generate"
    with open(f"{STATE_DIR}/lifecycle-gate.lock", "a") as gate, \
            open(f"{STATE_DIR}/lifecycle-{group}.lock", "a") as mine, \
            open(f"{STATE_DIR}/lifecycle-{other}.lock", "a") as theirs:
        deadline = time.monotonic() + wait
        while True:
            fcntl.flock(gate, fcntl.LOCK_EX)
            try:
                fcntl.flock(theirs, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(theirs, fcntl.LOCK_UN)
                fcntl.flock(mine, fcntl.LOCK_SH)
                held = True
            except BlockingIOError:
                held = False
            fcntl.flock(gate, fcntl.LOCK_UN)
            if held or time.monotonic() >= deadline:
                break
            time.sleep(0.5)
        try:
            yield held
        finally:
            if held:
                fcntl.flock(mine, fcntl.LOCK_UN)


@contextlib.contextmanager
def exclusive(name):
    """A non-blocking exclusive flock on STATE_DIR/<name>.lock. Yields True if this process
    holds it, False if another one does."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(f"{STATE_DIR}/{name}.lock", "a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        try:
            yield True
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def enter_scratch_dir():
    """cd into a fresh directory with a copy of config.toml. The CLI downloads key material
    into ./keys on every run, so concurrent runs must not share a directory."""
    path = tempfile.mkdtemp(prefix="kms-workload.")
    atexit.register(shutil.rmtree, path, True)
    shutil.copy(f"{CLIENT_DIR}/config.toml", path)
    os.chdir(path)


def write_client_config(left_out=None):
    """Write ./config.toml. left_out None keeps all four cores; a party ID drops that core.
    The CLI connects to every configured core before it sends a request, so a three-core
    config is how a client keeps decrypting while one core refuses connections.
    num_parties = 4 keeps the party IDs and threshold of the four-party deployment."""
    with open(f"{CLIENT_DIR}/config.toml") as f:
        text = f.read()
    if left_out is not None:
        head, *blocks = text.split("[[cores]]")
        kept = [b for b in blocks if not re.search(rf"(?m)^party_id *= *{left_out} *$", b)]
        text = head + "num_parties = 4\n" + "".join("[[cores]]" + b for b in kept)
    with open("config.toml", "w") as f:
        f.write(text)


def start_cli(args):
    """Start kms-core-client with args in the background; wait_cli collects it. Its output
    goes to a file, so a caller busy with other calls meanwhile can't stall it on a full
    pipe. Raises OSError when it can't be started."""
    cmd = ["kms-core-client", "-l", "-f", "config.toml"] + [str(a) for a in args]
    print("$ " + " ".join(cmd), flush=True)
    out = tempfile.TemporaryFile()
    proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
    proc.output_file = out
    return proc


def wait_cli(proc, timeout):
    """Wait for a start_cli process. Returns (exit code, combined output); on timeout it
    kills the process and returns 124, as timeout(1) reports it."""
    try:
        rc = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        rc = 124
    proc.output_file.seek(0)
    out = proc.output_file.read().decode(errors="replace")
    proc.output_file.close()
    return rc, out


def run_cli(args, timeout):
    """Run kms-core-client with args. Returns (exit code, combined output); 124 on timeout,
    and 126 when the CLI could not be started (e.g. no memory)."""
    try:
        return wait_cli(start_cli(args), timeout)
    except OSError as e:
        return 126, f"could not start kms-core-client: {e}"


def decrypt_args(command, key_id, inputs, all_parties, max_iter=120, sync=False, epoch_id=DEFAULT_EPOCH_ID):
    """Arguments for a public-decrypt or user-decrypt run of inputs under epoch_id (the CLI
    defaults to the kms-init epoch). --max-iter counts result polls per core, 0.5 s apart;
    each poll can wait up to 60 s. With --sync it counts re-sends of the sync request instead."""
    args = ["--max-iter", max_iter] + (["-a"] if all_parties else [])
    args += [command, "from-args", "--to-encrypt", "0x" + inputs["value_hex"],
             "--data-type", inputs["data_type"], "--key-id", key_id, "--batch-size", inputs["batch"]]
    if inputs["no_compression"]:
        args.append("--no-compression")
    if inputs["no_precompute_sns"]:
        args.append("--no-precompute-sns")
    if epoch_id != DEFAULT_EPOCH_ID:
        args += ["--context-id", DEFAULT_CONTEXT_ID, "--epoch-id", epoch_id]
    if sync:
        args.append("--sync")
    return args


def cli_connected(out):
    """Whether the CLI connected to every core in its config (it logs this with -l)."""
    return "Threshold Client setup done" in out


def cli_unreached_party(out):
    """The party the CLI was connecting to when it failed before connecting, or None."""
    found = re.findall(r"Connecting to party (\d+) via URL", out)
    return int(found[-1]) if found else None


def request_id_from(out):
    found = re.findall(r'"request_id": "([0-9a-fA-F]+)"', out)
    return found[-1] if found else None


def cli_outcome(rc, out):
    """The OP outcome of a CLI run: ok, or error=<what went wrong>."""
    if rc == 0:
        return "ok"
    if rc == 124:
        return "error=timeout"
    if "Threshold Client setup done" not in out and "Connecting to party" in out:
        return "error=connect"
    codes = re.findall(r"code: '([^']+)'", out)
    return f"error={TONIC_CODES.get(codes[-1], 'UNKNOWN')}" if codes else f"error=exit{rc}"


# How the CLI's gRPC library (tonic 0.14) prints a status code, mapped to the code names the
# Python gRPC library uses, so CLI and direct-gRPC outcomes count alike.
TONIC_CODES = {
    "The operation was cancelled": "CANCELLED",
    "Unknown error": "UNKNOWN",
    "Client specified an invalid argument": "INVALID_ARGUMENT",
    "Deadline expired before operation could complete": "DEADLINE_EXCEEDED",
    "Some requested entity was not found": "NOT_FOUND",
    "Some entity that we attempted to create already exists": "ALREADY_EXISTS",
    "The caller does not have permission to execute the specified operation": "PERMISSION_DENIED",
    "Some resource has been exhausted": "RESOURCE_EXHAUSTED",
    "The system is not in a state required for the operation's execution": "FAILED_PRECONDITION",
    "The operation was aborted": "ABORTED",
    "Operation was attempted past the valid range": "OUT_OF_RANGE",
    "Operation is not implemented or not supported": "UNIMPLEMENTED",
    "Internal error": "INTERNAL",
    "The service is currently unavailable": "UNAVAILABLE",
    "Unrecoverable data loss or corruption": "DATA_LOSS",
    "The request does not have valid authentication credentials": "UNAUTHENTICATED",
}


def log_outcome(op_id, outcome):
    """One line per call. Measures which operations run; it is not a check."""
    print(f"OP {op_id} {outcome}", flush=True)


def now_s():
    """Whole seconds since boot. Clock faults don't move it, unlike the wall clock."""
    with open("/proc/uptime") as f:
        return int(float(f.read().split()[0]))


def sleep(seconds):
    time.sleep(seconds)
