# How the tests work

The tests drive a four-party Zama KMS cluster (threshold multi-party computation, n = 4, t = 1) through the stock `kms-core-client` command-line client, the way an operator or the KMS connector would. Antithesis injects the faults (network partitions and slowdowns, pod stops and kills, clock jumps). The test commands never script a failure. Every command is a short shell script in [antithesis/test/v1/public_decrypt/](../antithesis/test/v1/public_decrypt/). The scripts ship to the cluster in a ConfigMap and run inside the client pod.

## How a test run goes

1. **Setup**, before any command: Kubernetes jobs generate each party's signing keys into MinIO, and `kms-init` creates the default MPC context and epoch on all four cores. Antithesis starts testing once every core is ready.
2. **First:** [`first_generate_key.sh`](#first_generate_key) generates the FHE key that the other commands decrypt under and reshare.
3. **Drivers, while faults are injected:** [`parallel_driver_public_decrypt.sh`](#parallel_driver_public_decrypt) and [`parallel_driver_user_decrypt.sh`](#parallel_driver_user_decrypt) run many decryptions in parallel at random times. [`anytime_reshare_key.sh`](#anytime_reshare_key) reshares the key into new epochs while they run, as an operator would.
4. **After faults stop:** [`eventually_recovers_after_faults.sh`](#eventually_recovers_after_faults) checks that every core comes back and that the cluster again answers a decryption that needs all four cores.

## Ideas the commands share

- **Ground truth instead of a ledger.** Every decryption decrypts a value the command itself just encrypted under the cluster's public key, so each result is checked against the exact value expected, with no shared record needed. The helpers that encrypt, call the client and emit assertions are in [helper_lib.sh](../antithesis/test/v1/public_decrypt/helper_lib.sh).
- **Unknown outcomes are allowed.** A decryption that times out, loses its connection or gets too few responses is not a failure. Only a successful, signed response with the wrong plaintext breaks Guarantee 1 or Guarantee 4. A failed reshare is allowed, as long as the earlier epoch keeps serving correct results.
- **Shapes vary per timeline.** Each timeline draws, once, how often a command uses three or four cores, synchronous or asynchronous calls, all four responses or a majority, batches, FHE types, compressed ciphertexts and reshared epochs (`timeline_choice` in the helper). Each command then picks values at random within those choices, so different timelines exercise different mixes.
- **Randomness comes from Antithesis:** the helpers read `/dev/urandom`, which Antithesis controls (the fallback SDK's source of randomness, `rand_below` and `pick` in the helper), so Antithesis can steer the choices.
- **Assertions use the fallback SDK:** each command writes JSON lines to `$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`. Every assertion's details name its guarantee (`guarantee-<n>`) and property.
- **A client limit to know:** `kms-core-client` connects to every core in its configuration before sending anything, so while a core is down a four-core run can't start. The decryption drivers therefore sometimes use a configuration with three of the four cores. User decryption can't, because the client derives the reconstruction threshold from the number of cores configured.

## Which commands check each guarantee

| Guarantee | Commands |
|---|---|
| [Guarantee 1](speedrun-report.md#guarantee-1): public decryption returns the encrypted plaintext | [`parallel_driver_public_decrypt.sh`](#parallel_driver_public_decrypt), [`eventually_recovers_after_faults.sh`](#eventually_recovers_after_faults) |
| [Guarantee 2](speedrun-report.md#guarantee-2): the cluster serves decryptions again after faults stop | [`eventually_recovers_after_faults.sh`](#eventually_recovers_after_faults) |
| [Guarantee 3](speedrun-report.md#guarantee-3): resharing keeps the key | [`anytime_reshare_key.sh`](#anytime_reshare_key), [`parallel_driver_public_decrypt.sh`](#parallel_driver_public_decrypt), [`parallel_driver_user_decrypt.sh`](#parallel_driver_user_decrypt) |
| [Guarantee 4](speedrun-report.md#guarantee-4): user decryption returns the encrypted plaintext | [`parallel_driver_user_decrypt.sh`](#parallel_driver_user_decrypt) |
| [Guarantee 5](speedrun-report.md#guarantee-5): retries under one request ID | not tested: the stock client can't choose request IDs |

## Every command

The commands, grouped by when Antithesis runs them.

### Drivers

Run at random times, many at once, while Antithesis injects faults.

<a id="parallel_driver_public_decrypt"></a>
#### `parallel_driver_public_decrypt.sh`

**Kind:** parallel driver · **Guarantees:** [Guarantee 1](speedrun-report.md#guarantee-1), [Guarantee 3](speedrun-report.md#guarantee-3) · **Code:** [parallel_driver_public_decrypt.sh](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh)

Runs one public decryption of a fresh value, retrying when an attempt ends without a verdict.

<details><summary>The command's own description (its docstring)</summary>

kms-core-client does the checking. It encrypts the value under the cluster's public key and
sends the request to the cores in its config. It collects 2 responses (every configured
core's with -a) and checks their signatures, their agreement and their request link. It then
compares every collected plaintext with the encrypted value. This script picks the inputs at
random and classifies the exit of the CLI. A wrong result is a property failure. Any other
error is an attempt without a verdict, which is expected under faults: the request may or
may not still complete on the cores, and nothing here depends on which.

Inputs: FHE type and value (zero, one, max, top bit, random), batch size, compressed or not,
SnS precomputed by the client or left to the cores, the async endpoint with result polling
or the sync endpoint, and the epoch. Until anytime_reshare_key.sh reshares the key, every
run decrypts under the kms-init epoch. After that, up to 3 runs in 5 decrypt under a
reshared epoch instead (see pick_epoch), so the same check covers the shares that a reshare
produced.

Cores. The CLI connects to every core in its config before it sends anything, so while one
core does not accept connections a four-core config fails before reaching the cluster. A run
therefore starts either with all four cores or with three (a random one left out, still
num_parties = 4). -a is used only with four cores: with three it would wait for a fourth
response that never comes. How often a run uses three cores, -a and --sync is drawn once per
timeline (timeline_choice), so some timelines lean one way and some the other.

Retries. A run makes up to 3 attempts. Each attempt is a new CLI run, so a new random request
ID and a fresh encryption of the same value; a request ID is never reused here (that is
[Guarantee 5](speedrun-report.md#guarantee-5)). An attempt without a verdict is retried after 10 s. If it did not get past
connecting, the CLI's log (-l) names the core it was connecting to, and the next attempt
leaves that core out, as a client would fail over to the cores it can reach.

Checks ([Guarantee 1](speedrun-report.md#guarantee-1); the reshared-epoch checks are [Guarantee 3](speedrun-report.md#guarantee-3)):
- Always: a public decryption the CLI accepts carries the encrypted plaintext, and the CLI
  never fails with an error that only a validly signed wrong result causes.
- AlwaysOrUnreachable ([Guarantee 3](speedrun-report.md#guarantee-3)): the same check for decryptions under a reshared epoch,
  confirmed or not, so a wrong plaintext there also counts against the reshare.
- Unreachable: a response from a KMS party fails authentication.
- Sometimes: a decryption succeeded on a retry after an attempt without a verdict (judged on
  every retry).
- Sometimes: a decryption succeeded after the client left out a core it could not connect to
  (judged on every attempt that fails over).
- Reachable: a decryption succeeded with -a, with --sync, with a batch, with SnS left to the
  cores, through three cores, and under a reshared epoch; an attempt ended without a verdict.

</details>

| Assertion | Type | Guarantee | Where |
|---|---|---|---|
| public decryption response carries the encrypted plaintext | `always` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 103](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L103) |
| public decryption under a reshared epoch carries the encrypted plaintext | `always_or_unreachable` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 110](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L110) |
| batched public decryption succeeded | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 107](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L107) |
| public decryption attempt ended without a verdict | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 143](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L143) |
| public decryption succeeded through the sync endpoint | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 106](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L106) |
| public decryption succeeded through three of the four cores | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 105](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L105) |
| public decryption succeeded under a reshared epoch | `reachable` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 111](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L111) |
| public decryption succeeded with SnS left to the cores | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 108](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L108) |
| public decryption succeeded with every party's response checked | `reachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 104](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L104) |
| public decryption succeeded after the client left out a core it could not connect to | `sometimes` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 102](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L102) |
| public decryption succeeded on a retry after an attempt without a verdict | `sometimes` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 101](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L101) |
| public decryption response from a KMS party fails authentication | `unreachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 126](../antithesis/test/v1/public_decrypt/parallel_driver_public_decrypt.sh#L126) |

<a id="parallel_driver_user_decrypt"></a>
#### `parallel_driver_user_decrypt.sh`

**Kind:** parallel driver · **Guarantees:** [Guarantee 3](speedrun-report.md#guarantee-3), [Guarantee 4](speedrun-report.md#guarantee-4) · **Code:** [parallel_driver_user_decrypt.sh](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh)

Runs one user decryption of a fresh value, retrying when an attempt ends without a verdict.

<details><summary>The command's own description (its docstring)</summary>

kms-core-client does the checking. It encrypts the value under the cluster's public key,
sends a user-decryption request with a fresh request ID and a fresh ephemeral ML-KEM key to
the four cores, and collects 3 responses (all four with -a). It authenticates each response
(signature, link to the request, agreement on degree and slot metadata), un-signcrypts the
shares, reconstructs the plaintext with error correction and compares it with the encrypted
value. Only that comparison's error, "user decryption result mismatch", means authenticated
shares rebuilt a wrong value; this script classifies the CLI's exit on it. Every other error
(too few responses, failed authentication or reconstruction, transport errors, timeouts) is
an attempt without a verdict, which the guarantee allows ("the value or an error"). Its
outcome on the cores is unknown and nothing here depends on it.

Inputs: FHE type and value (zero, one, max, top bit, random), batch size, compressed or not,
SnS precomputed by the client or left to the cores, the async endpoint with result polling
or the sync endpoint, -a or not, and the epoch: the kms-init epoch, or after
anytime_reshare_key.sh has run, up to 3 runs in 5 under a reshared epoch (pick_epoch). How
often a run uses --sync and -a is drawn once per timeline (timeline_choice).

Cores. Unlike public decryption, user decryption always uses the pod's four-core config. The
client derives the threshold from the cores in its config, (n - 1) / 3, so with three it
expects degree-0 shares and rejects the cores' degree-1 shares (UserDecTrustedValidationContext
and the pivot check in core/service/src/engine/validation_wasm.rs). While a core does not
accept connections, every attempt therefore fails at connect, which is an allowed error.

Retries. A run makes up to 3 attempts, 10 s apart. Each attempt is a new CLI run, so a new
request ID, a new ephemeral key and a fresh encryption of the same value.

Checks ([Guarantee 4](speedrun-report.md#guarantee-4); the reshared-epoch check is [Guarantee 3](speedrun-report.md#guarantee-3)):
- Always: a user decryption the CLI completes reconstructs the encrypted plaintext; the CLI
  never reports a result mismatch.
- AlwaysOrUnreachable ([Guarantee 3](speedrun-report.md#guarantee-3)): the same check for decryptions under a reshared epoch.
- Sometimes: a decryption succeeded on a retry after an attempt without a verdict (judged on
  every retry).
- Sometimes: a decryption under a reshared epoch succeeded (judged on every such attempt).
- Sometimes: a batched decryption succeeded (judged on every batched attempt).
- Reachable: a decryption succeeded with -a, with --sync, with SnS left to the cores; an
  attempt ended without a verdict.

</details>

| Assertion | Type | Guarantee | Where |
|---|---|---|---|
| user decryption reconstructs the encrypted plaintext | `always` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 91](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L91) |
| user decryption under a reshared epoch reconstructs the encrypted plaintext | `always_or_unreachable` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 93](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L93) |
| user decryption attempt ended without a verdict | `reachable` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 128](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L128) |
| user decryption succeeded through the sync endpoint | `reachable` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 99](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L99) |
| user decryption succeeded with SnS left to the cores | `reachable` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 100](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L100) |
| user decryption succeeded with every party's response collected | `reachable` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 98](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L98) |
| batched user decryption succeeded | `sometimes` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 97](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L97) |
| user decryption succeeded on a retry after an attempt without a verdict | `sometimes` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 96](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L96) |
| user decryption succeeded under a reshared epoch | `sometimes` | [Guarantee 4](speedrun-report.md#guarantee-4) | [line 94](../antithesis/test/v1/public_decrypt/parallel_driver_user_decrypt.sh#L94) |

### Run first

Run once, before the drivers start.

<a id="first_generate_key"></a>
#### `first_generate_key.sh`

**Kind:** first · **Guarantees:** none (setup) · **Code:** [first_generate_key.sh](../antithesis/test/v1/public_decrypt/first_generate_key.sh)

Generates the FHE key that the drivers decrypt under and reshare. kms-init creates only the MPC context and epoch, so a fresh cluster has no key.

<details><summary>The command's own description (its docstring)</summary>

Antithesis runs this once per timeline, before any driver and with no faults. The default
is insecure keygen because it is fast. Set KMS_WORKLOAD_KEYGEN=secure to run the real
distributed keygen instead.

</details>

| Assertion | Type | Guarantee | Where |
|---|---|---|---|
| workload generated an FHE key | `reachable` | – | [line 30](../antithesis/test/v1/public_decrypt/first_generate_key.sh#L30) |

### Checkers that run during faults

Run periodically while the drivers and faults run.

<a id="anytime_reshare_key"></a>
#### `anytime_reshare_key.sh`

**Kind:** anytime · **Guarantees:** [Guarantee 3](speedrun-report.md#guarantee-3) · **Code:** [anytime_reshare_key.sh](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh)

Reshares the workload's FHE key into a new epoch, then checks that the key is still the same key: its public key is unchanged and the epoch it was reshared from still decrypts correctly.

<details><summary>The command's own description (its docstring)</summary>

kms-core-client new-epoch sends the reshare to all four cores and polls each core for the
result. It then checks that every result names the key and preprocessing IDs that were
sent, and that the signature of every result verifies over the published key material. The
CLI succeeds only when all four cores report success, but the protocol tolerates one faulty
party. A failed run can therefore leave an epoch that some cores hold and others do not.
Such an epoch is recorded as unconfirmed, and the decryption drivers try it less often. The
drivers decrypt under the epochs that this command records (pick_epoch in helper_lib.sh),
so their plaintext checks cover the reshared key shares too.

Public key. Public material is stored per key ID, not per epoch, so a reshare must leave it
byte-identical. Before the reshare the command reads PUB-p<i>/PublicKey/<key_id> of all four
parties from MinIO and takes each one's digest; after new-epoch returns, done or not, it
reads them again. A party whose object could not be read either time (a network fault) is
left out; one that was there before and is gone after (404) counts as changed.

Source epoch. After the reshare, done or not, the command runs one public decryption of a
fresh value under the epoch it reshared from, with up to 2 attempts. A reshare that panicked
or timed out may have taken effect on some cores and not on others, but either way the
source epoch must keep its key shares. Availability is not checked here: an attempt without
a verdict is allowed, only a wrong plaintext is a failure. As in the driver, an attempt that
could not connect to a core is followed by one that leaves that core out (three-core config).

This is an anytime command. It runs alongside the decryption drivers, as an operator's
reshare would, and copies of it can run at the same time. Each run uses a fresh epoch ID.

Checks ([Guarantee 3](speedrun-report.md#guarantee-3)):
- Always: every core's reshare result names the reshared key and its signature verifies over
  the published key material (new-epoch's own checks).
- Always: the public key every party publishes for the key is unchanged by the reshare.
- Always: a public decryption under the source epoch after the reshare carries the encrypted
  plaintext.
- Sometimes: the public key was read back unchanged after a reshare that ended without a
  verdict (judged on every such reshare).
- Sometimes: a decryption under the source epoch succeeded after a reshare that ended without
  a verdict (judged on every attempt after such a reshare).
- Reachable: a reshare from an epoch that a reshare created succeeded; a reshare ended
  without a verdict.

</details>

| Assertion | Type | Guarantee | Where |
|---|---|---|---|
| key reshare result from every KMS party matches the reshared key | `always` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 115](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L115) |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare | `always` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 190](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L190) |
| public key that every party publishes for a key is unchanged by a reshare | `always` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 162](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L162) |
| key reshare attempt ended without a verdict | `reachable` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 139](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L139) |
| key reshare succeeded from an epoch that a reshare created | `reachable` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 117](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L117) |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict | `sometimes` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 191](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L191) |
| public key read back unchanged after a reshare that ended without a verdict | `sometimes` | [Guarantee 3](speedrun-report.md#guarantee-3) | [line 164](../antithesis/test/v1/public_decrypt/anytime_reshare_key.sh#L164) |

### Checkers that run after faults stop

The drivers have stopped and faults are off. Each one judges the system once it has had a chance to recover.

<a id="eventually_recovers_after_faults"></a>
#### `eventually_recovers_after_faults.sh`

**Kind:** eventually · **Guarantees:** [Guarantee 1](speedrun-report.md#guarantee-1), [Guarantee 2](speedrun-report.md#guarantee-2) · **Code:** [eventually_recovers_after_faults.sh](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh)

Checks that once faults stop, every core accepts connections again and the cluster then serves a public decryption that all four cores answer.

<details><summary>The command's own description (its docstring)</summary>

Faults. Antithesis stops all faults when an eventually_ command starts, kills the other
running commands, and runs nothing alongside it (Test Composer reference, "Eventually
command": "All faults stop across all containers when an eventually command starts"). This
command also opens a quiet window with $ANTITHESIS_STOP_FAULTS that covers its whole check
(the documented way to pause faults from a workload), so the check holds even if the
launcher's pod-fault injector did not follow the eventually phase. A pod deleted just before
faults stopped is recreated by its StatefulSet; nothing here restarts anything.

Probe. kms-core-client -a public-decrypt with the pod's own four-core config: a fresh value
of a random type under the workload's key and the kms-init epoch (so a failed reshare can't
make it fail), through the async endpoint with result polling or through --sync. -a makes
the CLI wait for all four cores' responses and check each of them, so a success means every
core took part. Each attempt is a new request with a new random request ID; an attempt that
fails has an unknown outcome on the cores, which does not matter because nothing depends on
it. Attempts are bounded by 90 s (and by the time left in the window) and are 10 s apart.

Windows ([Guarantee 2](speedrun-report.md#guarantee-2) as written in guarantees.md). The CLI connects to every core before it
sends anything and logs (-l) when it has, which is the client's view of "every core accepts
connections". That must happen within 600 s of this command's start (Kubernetes' restart
back-off cap of 300 s plus boot and readiness). From the start of the first attempt that got
that far, a probe must succeed within 300 s (the deployment's MPC network_timeout). A core
still down when its window ends is a failure, and so is a cluster that accepts connections
but cannot answer. Durations use seconds since boot (/proc/uptime), which clock faults don't
move.

Checks:
- Always ([Guarantee 2](speedrun-report.md#guarantee-2)): every core accepts client connections within 600 s after faults stop.
- Always ([Guarantee 2](speedrun-report.md#guarantee-2)): a public decryption answered by all four cores succeeds within 300 s
  of every core accepting connections.
- Sometimes ([Guarantee 2](speedrun-report.md#guarantee-2)): a core the client could not connect to after faults stopped
  accepted connections again.
- Sometimes ([Guarantee 2](speedrun-report.md#guarantee-2)): a decryption answered by all four cores succeeded after the first
  attempt failed.
- Always ([Guarantee 1](speedrun-report.md#guarantee-1), shared with parallel_driver_public_decrypt.sh): a decryption the CLI
  accepts carries the encrypted plaintext.
- Unreachable ([Guarantee 1](speedrun-report.md#guarantee-1), shared): a response from a KMS party fails authentication.

</details>

| Assertion | Type | Guarantee | Where |
|---|---|---|---|
| every core accepts client connections within 600 s after faults stop | `always` | [Guarantee 2](speedrun-report.md#guarantee-2) | [line 146](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L146) |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections | `always` | [Guarantee 2](speedrun-report.md#guarantee-2) | [line 150](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L150) |
| a core the client could not connect to after faults stopped accepted connections again | `sometimes` | [Guarantee 2](speedrun-report.md#guarantee-2) | [line 157](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L157) |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped | `sometimes` | [Guarantee 2](speedrun-report.md#guarantee-2) | [line 160](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L160) |
| public decryption response carries the encrypted plaintext (shared with [`parallel_driver_public_decrypt.sh`](#parallel_driver_public_decrypt)) | `always` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 114](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L114) |
| public decryption response from a KMS party fails authentication (shared with [`parallel_driver_public_decrypt.sh`](#parallel_driver_public_decrypt)) | `unreachable` | [Guarantee 1](speedrun-report.md#guarantee-1) | [line 124](../antithesis/test/v1/public_decrypt/eventually_recovers_after_faults.sh#L124) |

## Shared code

The `helper_*` files aren't commands: Antithesis ignores them. They hold what several commands share.

| Helper | What it holds |
|---|---|
| <a id="helper_lib"></a>[`helper_lib.sh`](../antithesis/test/v1/public_decrypt/helper_lib.sh) | Shared helpers for the public_decrypt test template: assertions, client configs, randomness. |

