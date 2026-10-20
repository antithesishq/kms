#!/usr/bin/env python3
"""Insecure keygen preprocessing: InsecureKeyGenPreproc on every core, then its result.
Successful IDs go to the pool the keygen driver takes from. Now and then the request names
an epoch the cluster doesn't have."""
from helper_common import (DEFAULT_CONTEXT_ID, chance, cli_outcome, enter_scratch_dir, log_outcome,
                           pick_count, rand_hex, record, request_id_from, run_cli)

OP = "preproc.start_insecure"

enter_scratch_dir()
for _ in range(pick_count(1, 3)):
    args = ["--max-iter", 60, "insecure-preproc-key-gen"]
    if chance(15):
        args += ["--context-id", DEFAULT_CONTEXT_ID, "--epoch-id", "08" + rand_hex(31)]
    rc, out = run_cli(args, timeout=300)
    log_outcome(OP, cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("preproc", request_id_from(out))
