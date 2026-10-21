#!/usr/bin/env python3
"""DestroyMpcEpoch (kms-core-client destroy-mpc-epoch, sent to every core) on an epoch this
workload made: a reshared one while more than 2 are left, a PRSS-only one, or one a rejected
reshare left; sometimes one already destroyed or one that never existed. Never the kms-init
epoch. The epoch first leaves its pool, then the driver waits until no command decrypts or
reshares under it (epoch_exclusive; the proto asks callers not to destroy an epoch while
requests on it run). No keygen or CRS generation meanwhile (lifecycle)."""
import os
import sys

from helper_common import (STATE_DIR, chance, cli_outcome, enter_scratch_dir, epoch_exclusive, exit_unless_active,
                           lifecycle, log_outcome, pick, pool, run_cli, unknown_epoch_id)

OP = "epoch.destroy"

exit_unless_active(OP, "epoch_destroy", 50)
made = [("epochs-prss", e) for e in pool("epochs-prss")] + [("epochs-rejected", e) for e in pool("epochs-rejected")]
if len(pool("epochs")) > 2:
    made += [("epochs", e) for e in pool("epochs")]
epoch = None
if made and chance(80):
    source, epoch = pick(made)
    try:
        os.makedirs(f"{STATE_DIR}/epochs-destroyed", exist_ok=True)
        os.rename(f"{STATE_DIR}/{source}/{epoch}", f"{STATE_DIR}/epochs-destroyed/{epoch}")
    except FileNotFoundError:
        epoch = None  # a concurrent destroy took it
if epoch is None:
    epoch = pick(pool("epochs-destroyed")) if pool("epochs-destroyed") and chance(50) else unknown_epoch_id()
enter_scratch_dir()
with epoch_exclusive(epoch, wait=300) as alone, lifecycle("epoch", wait=120 if alone else 0) as held:
    if not (alone and held):
        log_outcome(OP, "skipped=generation_running_or_epoch_in_use")
        sys.exit(0)
    rc, out = run_cli(["destroy-mpc-epoch", "--epoch-id", epoch], timeout=120)
    log_outcome(OP, cli_outcome(rc, out))
