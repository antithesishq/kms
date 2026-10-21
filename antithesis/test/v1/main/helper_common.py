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
#   epochs/<epoch_id>   epochs a reshare created; the file holds the reshared key IDs and then
#                       "confirmed" (every core reported it done) or "unconfirmed" (the CLI
#                       failed, so some cores can hold the epoch and others not)
#   epochs-rejected/<epoch_id>  epochs of reshare requests meant to fail; the file holds why
#   epochs-prss/<epoch_id>      PRSS-only epochs parallel_driver_epoch_create.py made
#   epochs-destroyed/<epoch_id> epochs parallel_driver_epoch_destroy.py took out of the pools
#   epoch-locks/<epoch_id>      flock files: shared while a command decrypts or reshares under
#                               the epoch, exclusive while it is destroyed (epoch_in_use)
#   crs/<crs_id>        CRSes the CLI generated; the file holds "secure" or "insecure"
#   crs-requests/<n>    one file per valid CRS generation request sent
#   abort-runs/<id>     preprocessing IDs parallel_driver_keygen_abort_running.py used (its budget)
#   profile/<name>      this timeline's draw of a workload knob (timeline_choice)
STATE_DIR = "/tmp/kms-workload-state"

# Keys add memory and boot time to every core, so the drivers stop making new ones here.
MAX_KEYS = 3
# Every reshared epoch holds a copy of its keys' shares on each core, loaded at boot, so the
# reshare driver stops here. With the test parameters a key's shares are small.
MAX_EPOCHS = 12
# CRSes are stored on every core and in MinIO, so the CRS drivers stop generating valid ones
# here. A CRS generation keeps going on the cores after its CLI is killed, and each one costs
# a core's only CPU for a while (party 1 samples every insecure CRS alone), so the drivers
# also send at most MAX_CRS_REQUESTS valid requests per container (crs-requests/).
MAX_CRS = 6
MAX_CRS_REQUESTS = 10

DATA_TYPES = ["ebool", "euint8", "euint16", "euint32", "euint64", "euint128", "euint160", "euint256"]


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
    """A decryption's inputs. The largest batch is a per-timeline choice (1, 3 or 6); within
    it, half the batches are single ciphertexts."""
    data_type = pick(DATA_TYPES)
    max_batch = timeline_choice("max_batch", [1, 3, 3, 6])
    batch = 1 if chance(50) else pick_count(1, max_batch)
    return {"data_type": data_type, "value_hex": pick_value(data_type), "batch": batch,
            "no_compression": pick([False, False, False, True]),
            "no_precompute_sns": pick([False, False, False, True])}


def paced(used, cap, name):
    """Whether a per-container budget of cap slots, used of them spent, has room for one more.
    How fast its slots open is a per-timeline choice: all at once, or one every 120 or 300 s
    from the first time a command asked, so that Antithesis branches from later in a run still
    have slots to spend. Seconds since boot, which clock faults don't move."""
    pace = timeline_choice(f"pace_{name}", [0, 120, 300])
    start = timeline_choice("budget_start", [now_s()])
    opened = cap if pace == 0 else min(cap, 1 + (now_s() - start) // pace)
    return used < opened


def crs_request_allowed():
    """Whether a CRS driver may send a valid generation request now; if so, counts it. The
    caller holds exclusive("crs-generation"), so one is in flight at a time."""
    if len(pool("crs")) >= MAX_CRS or not paced(len(pool("crs-requests")), MAX_CRS_REQUESTS, "crs_requests"):
        return False
    record("crs-requests", rand_hex(8))
    return True


def pick_crs_bits(valid=True):
    """--max-num-bits for a CRS: a power of 2 from 1 to 2048 (the server's limit), mostly
    small, since larger ones make a larger CRS and a longer ceremony; with valid=False, or 1
    time in 10, a value the cores must reject (not a power of 2, 0, or past 2048)."""
    if not valid or chance(10):
        return pick([0, 3, 100, 4096])
    return pick([1, 2, 16, 16, 64, 64, 256, 1024, 2048])


def pick_request_id(ids):
    """A request ID for a result RPC: one from the pool, or an unknown one, or a malformed or
    differently spelled one, from the request-ID limits in api-surface.md (all-zero and short
    IDs are invalid; upper case and 0x are accepted). How often it is not a pooled ID is a
    per-timeline choice: 10, 35 or 70 %."""
    noise = timeline_choice("request_id_noise_pct", [10, 35, 70])
    kind = pick(["fresh", "zero", "upper", "prefixed", "short"]) if chance(noise) else "pool"
    if not ids or kind == "fresh":
        return rand_hex(32)
    rid = pick(ids)
    return {"pool": rid, "zero": "0" * 64, "upper": rid.upper(), "prefixed": "0x" + rid,
            "short": rid[:-2]}[kind]


def exit_unless_active(op, name, percent):
    """Per timeline, a driver runs in percent of timelines and does nothing in the others, so
    that operations that undo each other (aborts and keygens, destroys and reshares) don't
    always run together. Logs the skip and exits when inactive."""
    if not timeline_choice(f"active_{name}", [0] * (100 - percent) + [1] * percent):
        log_outcome(op, "skipped=inactive_in_timeline")
        raise SystemExit(0)


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


def existing_keyset_args(uncompressed):
    """Flags for a keygen that reuses an existing key's secret shares (UseExisting: party 1
    rebuilds the key and re-shares it under the new ID), in a per-timeline share of keygens
    (0, 20 or 50 %): a key every core holds, half the time keeping its tag, and for a
    compressed keygen 3 times in 10 copying the result back over the existing key's public
    material (--copy-compressed-key-to-original). [] otherwise."""
    everywhere = set(keys_on_every_core())
    keys = [k for k in pool("keys") if k in everywhere]
    if not keys or not chance(timeline_choice("from_existing_pct", [0, 20, 50])):
        return []
    args = ["--existing-keyset-id", pick(keys)]
    if chance(50):
        args.append("--use-existing-key-tag")
    if not uncompressed and chance(30):
        args.append("--copy-compressed-key-to-original")
    return args


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
    """The next ID for an epoch to create. NewMpcEpochRequest (kms.v1.proto) requires every new
    epoch ID to be greater than the previous one, as a big-endian integer, and a core picks a
    key's and a CRS's latest epoch by ID at boot. So IDs come from a counter in STATE_DIR,
    above the kms-init epoch (08…01) and with the 08 prefix fhevm expects. Callers that create
    an epoch take the ID while they hold exclusive("new-epoch"), so requests go out in order."""
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(f"{STATE_DIR}/epoch-counter", "a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        n = int(f.read().strip() or "1") + 1
        f.seek(0)
        f.truncate()
        f.write(str(n))
        f.flush()  # before the lock goes, or the next caller reads the old count
        fcntl.flock(f, fcntl.LOCK_UN)
    return f"08{n:062x}"


def unknown_epoch_id():
    """An epoch ID no core knows, for requests that must fail; it never names an epoch to
    create, so it needn't be in order."""
    return "08" + rand_hex(31)


def epoch_record(epoch):
    """(key IDs, status) of a recorded reshared epoch, or ([], None) if it can't be read."""
    try:
        with open(f"{STATE_DIR}/epochs/{epoch}") as f:
            tokens = f.read().split()
    except FileNotFoundError:
        return [], None
    return (tokens[:-1], tokens[-1]) if len(tokens) >= 2 else ([], None)


def epochs_of(key_id, status):
    """The recorded epochs with status (confirmed or unconfirmed) that key_id was reshared into."""
    return [e for e in pool("epochs") if epoch_record(e)[1] == status and key_id in epoch_record(e)[0]]


def pick_epoch(key_id):
    """(epoch ID, status) to decrypt under key_id: the kms-init epoch ("default"), a confirmed
    reshared epoch or an unconfirmed one, in a mix drawn per timeline (2:2:1, mostly default,
    or mostly reshared), falling back to the default when there is no reshared epoch of the
    chosen kind."""
    mix = {0: [2, 2, 1], 1: [8, 1, 1], 2: [1, 3, 2]}[timeline_choice("epoch_mix", [0, 1, 2])]
    status = pick(["default"] * mix[0] + ["confirmed"] * mix[1] + ["unconfirmed"] * mix[2])
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
def epoch_in_use(epoch_id):
    """Hold a reshared epoch while a command decrypts or reshares under it, so that
    parallel_driver_epoch_destroy.py doesn't destroy it meanwhile (the proto asks callers not
    to destroy an epoch while requests on it run). Yields True while held; False, holding
    nothing that matters, if the epoch is being destroyed or has left the pools. The kms-init
    epoch is never destroyed, so it is always usable."""
    if epoch_id == DEFAULT_EPOCH_ID:
        yield True
        return
    os.makedirs(f"{STATE_DIR}/epoch-locks", exist_ok=True)
    with open(f"{STATE_DIR}/epoch-locks/{epoch_id}", "a") as f:
        try:
            fcntl.flock(f, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        try:
            yield os.path.exists(f"{STATE_DIR}/epochs/{epoch_id}")
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


@contextlib.contextmanager
def epoch_exclusive(epoch_id, wait):
    """The destroy side of epoch_in_use: an exclusive flock on the epoch, waiting at most wait
    seconds for the commands using it to finish. Yields True while held, else False."""
    os.makedirs(f"{STATE_DIR}/epoch-locks", exist_ok=True)
    with open(f"{STATE_DIR}/epoch-locks/{epoch_id}", "a") as f:
        deadline = time.monotonic() + wait
        while True:
            try:
                fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    yield False
                    return
                time.sleep(1)
        try:
            yield True
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


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
