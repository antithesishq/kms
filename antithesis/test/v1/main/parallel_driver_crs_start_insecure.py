#!/usr/bin/env python3
"""Insecure CRS generation (InsecureCrsGen; party 1 samples the CRS): kms-core-client
insecure-crs-gen polls GetInsecureCrsGenResult on every core, downloads the CRS and checks the
signatures. max_num_bits is a power of 2 up to 2048, or sometimes a value the cores must
reject; past MAX_CRS CRSes only such values. Never while a reshare runs (lifecycle)."""
import sys

from helper_common import (MAX_CRS, cli_outcome, enter_scratch_dir, lifecycle, log_outcome, pick_crs_bits, pool,
                           record, request_id_from, run_cli)

OP = "crs.start_insecure"

enter_scratch_dir()
with lifecycle("generate", wait=600) as held:
    if not held:
        log_outcome(OP, "skipped=epoch_change_running")
        sys.exit(0)
    bits = pick_crs_bits(valid=len(pool("crs")) < MAX_CRS)
    rc, out = run_cli(["--max-iter", 600, "insecure-crs-gen", "--max-num-bits", bits], timeout=600)
    log_outcome(OP, cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("crs", request_id_from(out), "insecure")
