#!/usr/bin/env python3
"""Reshares a key every core holds into a fresh epoch (kms-core-client new-epoch), from the
kms-init epoch or one a reshare created, while decryptions run; the CLI checks every core's
result against the key and its published material. Then Guarantee 3's checks: every party's
public key is unchanged, and the source epoch still decrypts. The new epoch is recorded for
the decryption drivers. No keygen or keygen abort runs meanwhile (helper_common.lifecycle)."""
import sys

from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, MAX_EPOCHS, chance, cli_outcome, enter_scratch_dir,
                           epochs_of, lifecycle, log_outcome, new_epoch_id, pick, pool, record, run_cli)
from helper_properties import declare_catalog, judge_public_key, judge_reshare
from helper_reshare import (check_source_epoch, pick_reshare_key, previous_epoch_params, public_key_digests,
                            wait_epoch_settled)

OP = "epoch.reshare"

declare_catalog()
key = pick_reshare_key() if len(pool("epochs")) < MAX_EPOCHS else None
if key is None:
    log_outcome(OP, "skipped=no_key_or_max_epochs")
    sys.exit(0)
key_id, preproc_id = key
chained = epochs_of(key_id, "confirmed")
source_epoch = pick(chained) if chained and chance(50) else DEFAULT_EPOCH_ID
new_epoch = new_epoch_id()
enter_scratch_dir()
previous = previous_epoch_params(key_id, preproc_id, source_epoch)
if previous is None:
    log_outcome(OP, "skipped=key_material_unreadable")
    sys.exit(0)
before = public_key_digests(key_id)
with lifecycle("epoch", wait=300) as held:
    if not held:
        log_outcome(OP, "skipped=generation_running")
        sys.exit(0)
    rc, out = run_cli(["--max-iter", 1200, "new-epoch", "--new-epoch-id", new_epoch, "--new-context-id",
                       DEFAULT_CONTEXT_ID, "--previous-epoch-params", previous], timeout=900)
    log_outcome(OP, cli_outcome(rc, out))
    details = dict(key_id=key_id, preproc_id=preproc_id, source_epoch=source_epoch, new_epoch=new_epoch,
                   exit_code=rc)
    outcome = judge_reshare(rc, out, details)
    if outcome != "done":
        wait_epoch_settled(new_epoch)
if outcome == "args":
    sys.exit(1)
record("epochs", new_epoch, f"{key_id} {'confirmed' if outcome == 'done' else 'unconfirmed'}")
details["outcome"] = outcome
unchanged = judge_public_key(before, public_key_digests(key_id), details)
source_ok = check_source_epoch(key_id, source_epoch, details)
sys.exit(0 if unchanged and source_ok and outcome != "wrong" else 1)
