#!/usr/bin/env python3
"""epoch.reshare with a request that must fail: a wrong key digest or preprocessing ID, an
unknown source epoch, or the kms-init epoch as the new epoch. The last is rejected at once;
for the others the cores set up the new epoch's PRSS before the reshare fails, leaving an
epoch without keys, so at most REJECTED_EPOCHS of them (epochs-rejected/, never decrypted
under). No Guarantee 3 checks: they would trivially pass the ones judged after a failed
reshare. An accepted request is printed for triage. No keygen or keygen abort runs meanwhile
(helper_common.lifecycle)."""
import re
import sys

from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, cli_outcome, enter_scratch_dir, exclusive,
                           exit_unless_active, lifecycle, log_outcome, new_epoch_id, pick, pool, rand_hex, record,
                           run_cli, unknown_epoch_id)
from helper_reshare import pick_reshare_key, previous_epoch_params, wait_epoch_settled

OP = "epoch.reshare"
REJECTED_EPOCHS = 3

exit_unless_active(OP, "epoch_reshare_rejected", 60)
key = pick_reshare_key()
if key is None:
    log_outcome(OP, "skipped=no_key")
    sys.exit(0)
key_id, preproc_id = key
kind = pick(["digest", "preproc", "unknown_source", "existing_epoch"])
if len(pool("epochs-rejected")) >= REJECTED_EPOCHS:
    kind = "existing_epoch"
source_epoch = unknown_epoch_id() if kind == "unknown_source" else DEFAULT_EPOCH_ID
enter_scratch_dir()
previous = previous_epoch_params([(key_id, rand_hex(32) if kind == "preproc" else preproc_id)], source_epoch)
if previous is None:
    log_outcome(OP, "skipped=key_material_unreadable")
    sys.exit(0)
if kind == "digest":
    previous = re.sub(r"((?:xof|server)_key_digest)=[0-9a-f]+", lambda m: f"{m.group(1)}={rand_hex(32)}", previous)
with exclusive("new-epoch") as alone, lifecycle("epoch", wait=300 if alone else 0) as held:
    if not (alone and held):
        log_outcome(OP, "skipped=epoch_busy_or_generation_running")
        sys.exit(0)
    new_epoch = DEFAULT_EPOCH_ID if kind == "existing_epoch" else new_epoch_id()
    if new_epoch != DEFAULT_EPOCH_ID:
        record("epochs-rejected", new_epoch, kind)
    rc, out = run_cli(["--max-iter", 120, "new-epoch", "--new-epoch-id", new_epoch, "--new-context-id",
                       DEFAULT_CONTEXT_ID, "--previous-epoch-params", previous], timeout=300)
    log_outcome(OP, cli_outcome(rc, out))
    if rc != 0 and new_epoch != DEFAULT_EPOCH_ID:
        wait_epoch_settled(new_epoch)
if rc == 0:
    print(f"a reshare request with {kind} was accepted: key {key_id}, new epoch {new_epoch}", flush=True)
