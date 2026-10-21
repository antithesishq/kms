#!/usr/bin/env python3
"""epoch.reshare with Guarantee 3's checks; what it reshares, and the locks, in helper_reshare.py."""
import sys

from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, MAX_EPOCHS, cli_outcome, enter_scratch_dir,
                           epoch_in_use, exclusive, exit_unless_active, lifecycle, log_outcome, new_epoch_id, pick,
                           pool, record, run_cli)
from helper_properties import declare_catalog, judge_public_key, judge_reshare
from helper_reshare import (check_source_epoch, pick_crs_to_resign, plan_reshare, previous_epoch_params,
                            public_key_digests, wait_epoch_settled)

OP = "epoch.reshare"

declare_catalog()
exit_unless_active(OP, "epoch_reshare", 80)
plan = plan_reshare() if len(pool("epochs")) < MAX_EPOCHS else None
if plan is None:
    log_outcome(OP, "skipped=no_key_or_max_epochs")
    sys.exit(0)
keys, source_epoch = plan
crs = pick_crs_to_resign() if source_epoch == DEFAULT_EPOCH_ID else []
enter_scratch_dir()
previous = previous_epoch_params(keys, source_epoch, crs)
if previous is None:
    log_outcome(OP, "skipped=key_material_unreadable")
    sys.exit(0)
key_ids = [k for k, _ in keys]
with exclusive("new-epoch") as alone, epoch_in_use(source_epoch) as usable, \
        lifecycle("epoch", wait=300 if alone and usable else 0) as held:
    if not (alone and usable and held):
        log_outcome(OP, "skipped=epoch_busy_or_generation_running")
        sys.exit(0)
    before = {k: public_key_digests(k) for k in key_ids}  # no keygen can change them meanwhile
    new_epoch = new_epoch_id()
    rc, out = run_cli(["--max-iter", 1200, "new-epoch", "--new-epoch-id", new_epoch, "--new-context-id",
                       DEFAULT_CONTEXT_ID, "--previous-epoch-params", previous], timeout=900)
    log_outcome(OP, cli_outcome(rc, out))
    details = dict(key_ids=key_ids, crs_ids=[c for c, _ in crs], source_epoch=source_epoch, new_epoch=new_epoch,
                   exit_code=rc)
    outcome = judge_reshare(rc, out, details)
    if outcome != "done":
        wait_epoch_settled(new_epoch)
    after = {k: public_key_digests(k) for k in key_ids}
if outcome == "args":
    sys.exit(1)
record("epochs", new_epoch, " ".join(key_ids + ["confirmed" if outcome == "done" else "unconfirmed"]))
details["outcome"] = outcome
unchanged = [judge_public_key(before[k], after[k], dict(details, key_id=k)) for k in key_ids]
source_ok = check_source_epoch(pick(key_ids), source_epoch, details)
sys.exit(0 if all(unchanged) and source_ok and outcome != "wrong" else 1)
