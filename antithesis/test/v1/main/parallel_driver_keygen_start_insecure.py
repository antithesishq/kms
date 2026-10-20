#!/usr/bin/env python3
"""Insecure key generation: InsecureKeyGen on every core, then its result, from a
preprocessing ID the preprocessing driver pooled; compressed (default) or uncompressed (-u).

Keys add memory and boot time to every core, so once MAX_KEYS keys exist the driver sends
only preprocessing IDs that can't start a keygen (already consumed, or unknown). So does it
when the pool is empty. No keygen runs while a reshare does (helper_common.lifecycle)."""
from helper_common import (MAX_KEYS, chance, cli_outcome, enter_scratch_dir, key_count, lifecycle, log_outcome,
                           pick, pick_count, pool, rand_hex, record, request_id_from, run_cli, take)

OP = "keygen.start_insecure"

enter_scratch_dir()
for _ in range(pick_count(1, 2)):
    with lifecycle("generate", wait=120) as held:
        if not held:
            log_outcome(OP, "skipped=epoch_change_running")
            continue
        preproc_id = take("preproc") if key_count() < MAX_KEYS else None
        if preproc_id is None:
            preproc_id = pick(pool("preproc-taken") + [rand_hex(32)])
        args = ["--max-iter", 600, "insecure-key-gen", "--preproc-id", preproc_id]
        if chance(25):
            args.append("-u")
        rc, out = run_cli(args, timeout=600)
        log_outcome(OP, cli_outcome(rc, out))
        if rc == 0 and request_id_from(out):
            record("keys", request_id_from(out), preproc_id)
