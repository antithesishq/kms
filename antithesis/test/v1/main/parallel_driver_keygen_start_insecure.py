#!/usr/bin/env python3
"""Insecure key generation: InsecureKeyGen on every core, then its result, from a
preprocessing ID the preprocessing driver pooled; compressed (default) or uncompressed (-u),
and sometimes from an existing key's secret shares (existing_keyset_args; such keygens have
their own budget of 3 per container, since the key cap is spent within minutes).

Keys add memory and boot time to every core, so once MAX_KEYS keys exist the driver sends
only preprocessing IDs that can't start a keygen (already consumed, or unknown). So does it
when the pool is empty. No keygen runs while a reshare does (helper_common.lifecycle)."""
from helper_common import (MAX_KEYS, chance, cli_outcome, enter_scratch_dir, existing_keyset_args, exit_unless_active,
                           key_count, lifecycle, log_outcome, paced, pick, pick_count, pool, rand_hex, record,
                           request_id_from, run_cli, take, timeline_choice)

OP = "keygen.start_insecure"

exit_unless_active(OP, "keygen_start_insecure", 80)
enter_scratch_dir()
for _ in range(pick_count(1, 2)):
    with lifecycle("generate", wait=120) as held:
        if not held:
            log_outcome(OP, "skipped=epoch_change_running")
            continue
        uncompressed = chance(timeline_choice("uncompressed_pct", [0, 25, 75]))
        existing = existing_keyset_args(uncompressed) if len(pool("existing-keygens")) < 3 else []
        if existing:
            preproc_id = take("preproc")
        else:
            preproc_id = take("preproc") if paced(key_count(), MAX_KEYS, "keys") else None
        if preproc_id is None:  # a spent or unknown ID, which fails before the existing key matters
            existing, preproc_id = [], pick(pool("preproc-taken") + [rand_hex(32)])
        elif existing:
            record("existing-keygens", preproc_id)
        args = ["--max-iter", 600, "insecure-key-gen", "--preproc-id", preproc_id] + (["-u"] if uncompressed else [])
        args += existing
        rc, out = run_cli(args, timeout=600)
        log_outcome(OP, cli_outcome(rc, out))
        if rc == 0 and request_id_from(out):
            record("keys", request_id_from(out), preproc_id)
