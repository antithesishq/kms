#!/usr/bin/env python3
"""NewMpcEpoch without a previous epoch (kms-core-client new-epoch without
--previous-epoch-params): a PRSS-only epoch in the default context, recorded in epochs-prss/
(decryptions never use it). At most 3 alive and 8 made per container; 1 time in 10 an ID that
already exists, which the cores must reject. One new epoch at a time (exclusive "new-epoch",
shared with the reshare driver), and no keygen or CRS generation meanwhile (lifecycle)."""
import sys

from helper_common import (DEFAULT_CONTEXT_ID, DEFAULT_EPOCH_ID, chance, cli_outcome, enter_scratch_dir, exclusive,
                           exit_unless_active, lifecycle, log_outcome, new_epoch_id, pick, pool, record, run_cli)

OP = "epoch.create"

exit_unless_active(OP, "epoch_create", 60)
existing = pool("epochs-prss") + pool("epochs") + [DEFAULT_EPOCH_ID]
budget = len(pool("epochs-prss")) < 3 and len(pool("epochs-prss")) + len(pool("epochs-prss-made")) < 8
reuse = chance(10) or not budget
enter_scratch_dir()
with exclusive("new-epoch") as alone, lifecycle("epoch", wait=120 if alone else 0) as held:
    if not (alone and held):
        log_outcome(OP, "skipped=epoch_busy_or_generation_running")
        sys.exit(0)
    epoch = pick(existing) if reuse else new_epoch_id()
    rc, out = run_cli(["--max-iter", 600, "new-epoch", "--new-epoch-id", epoch, "--new-context-id",
                       DEFAULT_CONTEXT_ID], timeout=600)
    log_outcome(OP, cli_outcome(rc, out))
if rc == 0 and epoch not in existing:
    record("epochs-prss", epoch)
    record("epochs-prss-made", epoch)
