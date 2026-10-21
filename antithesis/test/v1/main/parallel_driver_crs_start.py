#!/usr/bin/env python3
"""CRS generation by ceremony (CrsGen: each party takes a sequential turn): kms-core-client
crs-gen polls GetCrsGenResult on every core, downloads the CRS and checks the signatures.

A ceremony keeps every core's CPUs busy for about a minute, whatever max_num_bits is, so one
CRS generation of either kind runs at a time, at most MAX_SECURE_CRS ceremonies per run, and
within the CRS budget (crs_request_allowed). Otherwise the driver sends a max_num_bits the
cores reject before any ceremony starts, as it does 1 time in 10 anyway. Never while a
reshare runs (lifecycle)."""
import sys

from helper_common import (cli_outcome, crs_request_allowed, enter_scratch_dir, exclusive, exit_unless_active,
                           lifecycle, log_outcome, pick_crs_bits, pool_matching, record, request_id_from, run_cli)

OP = "crs.start"
MAX_SECURE_CRS = 2

exit_unless_active(OP, "crs_start", 60)
enter_scratch_dir()
with lifecycle("generate", wait=120) as held, exclusive("crs-generation") as alone:
    if not held:
        log_outcome(OP, "skipped=epoch_change_running")
        sys.exit(0)
    bits = pick_crs_bits(valid=alone and len(pool_matching("crs", "secure")) < MAX_SECURE_CRS
                         and crs_request_allowed())
    rc, out = run_cli(["--max-iter", 600, "crs-gen", "--max-num-bits", bits], timeout=300)
    log_outcome(OP, cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("crs", request_id_from(out), "secure")
