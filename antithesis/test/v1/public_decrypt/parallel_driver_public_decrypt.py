#!/usr/bin/env python3
"""Runs one public decryption of a fresh value and turns the outcome into assertions.

kms-core-client does the checking. It encrypts the value under the cluster's public key and
sends the request to all four cores. It collects 2 responses (all 4 with -a) and checks their
signatures, their agreement and their request link. It then compares every collected plaintext
with the encrypted value. This script picks the inputs at random and classifies the exit of the
CLI. A wrong result is a property failure. Any other error is a transient failure, which is
expected under faults.

Until anytime_reshare_key.py reshares the key, every run decrypts under the kms-init epoch.
After that, up to 3 runs in 5 decrypt under a reshared epoch instead (see pick_epoch), so the
same check covers the shares that a reshare produced.
"""

import sys

import helper_lib as h  # first: it sets up the SDK's output before the SDK loads
from antithesis.assertions import always, reachable, unreachable

h.declare_catalog()

key_id = h.find_key_id()
if key_id is None:
    print("no FHE key published in MinIO yet; nothing to decrypt")
    sys.exit(0)

epoch_id, epoch_status = h.pick_epoch(key_id)
data_type = h.pick("ebool", "euint8", "euint16", "euint32", "euint64", "euint128", "euint160", "euint256")
value = h.pick_value(data_type)
batch = h.pick(1, 1, 1, 2, 3)
all_parties = h.pick(False, False, True)
sync = h.pick(False, True)
no_compression = h.pick(False, False, False, True)
no_sns = h.pick(False, False, False, True)

# --max-iter counts 0.5 s result polls per party.
args = ["-f", "config.toml", "--max-iter", "120"]
if all_parties:
    args.append("-a")
args += ["public-decrypt", "from-args", "--to-encrypt", f"0x{value}", "--data-type", data_type,
         "--key-id", key_id, "--batch-size", str(batch)]
if epoch_status != "default":
    args += ["--context-id", h.DEFAULT_CONTEXT_ID, "--epoch-id", epoch_id]
if sync:
    args.append("--sync")
if no_compression:
    args.append("--no-compression")
if no_sns:
    args.append("--no-precompute-sns")

h.enter_scratch_dir()
rc, output = h.run_cli(args, timeout=300)

inputs = {
    "data_type": data_type,
    "value_hex": value,
    "batch": batch,
    "all_parties": all_parties,
    "sync": sync,
    "no_compression": no_compression,
    "no_precompute_sns": no_sns,
    "key_id": key_id,
    "epoch_id": epoch_id,
    "epoch_status": epoch_status,
    "exit_code": rc,
}

# Errors that the CLI raises only when a validly signed response carries a wrong plaintext, a
# wrong plaintext count or type, or a wrong request ID. Sources: the plaintext check in
# core-client/src/decrypt.rs and validate_public_decrypt_responses in
# core/service/src/engine/validation_non_wasm.rs.
WRONG_RESULT = [
    "decryption result mismatch",
    "Cannot find public decryption pivot",
    "Not enough agreeing public decryption responses",
    "The number of ciphertexts in the public decryption response is wrong",
    "Plaintext type mismatch in public decryption response",
    "The public decryption response is not linked to the correct public decryption request",
    "Request ID is not set in public decryption response",
]

if rc == 0:
    details = {**inputs, "request_id": h.request_id_from(output) or ""}
    always(True, "public decryption response carries the encrypted plaintext", details)
    if all_parties:
        reachable("public decryption succeeded with every party's response checked", details)
    if sync:
        reachable("public decryption succeeded through the sync endpoint", details)
    if batch > 1:
        reachable("batched public decryption succeeded", details)
    if no_sns:
        reachable("public decryption succeeded with SnS left to the cores", details)
    if epoch_status != "default":
        reachable("public decryption succeeded under a reshared epoch", details)
    sys.exit(0)

err = h.first_line_with(output, WRONG_RESULT)
if err is not None:
    always(
        False,
        "public decryption response carries the encrypted plaintext",
        {**inputs, "error": h.clip(err)},
    )
    print(output)
    sys.exit(1)

# A response that fails authentication never comes from a correct party. One case is a
# response for another request, whose signature does not cover this request's handles.
err = h.first_line_with(output, ["Not enough authenticated public decryption responses"])
if err is not None:
    unreachable(
        "public decryption response from a KMS party fails authentication",
        {**inputs, "error": h.clip(err)},
    )
    print(output)
    sys.exit(1)

reachable(
    "public decryption attempt ended without a verdict",
    {**inputs, "error": h.clip(h.tail(output, 3))},
)
print(h.tail(output, 20))
sys.exit(0)
