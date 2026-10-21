#!/usr/bin/env python3
"""Insecure CRS generation (InsecureCrsGen; party 1 samples the CRS): kms-core-client
insecure-crs-gen polls GetInsecureCrsGenResult on every core, downloads the CRS and checks the
signatures. max_num_bits is a power of 2 up to 2048, or a value the cores must reject: 1 time
in 10, and whenever another CRS generation is in flight or the CRS budget is spent
(crs_request_allowed), since each one takes party 1's CPU for a while. Never while a reshare
runs (lifecycle)."""
import sys

from helper_common import (cli_outcome, crs_request_allowed, enter_scratch_dir, exclusive, exit_unless_active,
                           lifecycle, log_outcome, pick_crs_bits, record, request_id_from, run_cli)

OP = "crs.start_insecure"

exit_unless_active(OP, "crs_start_insecure", 60)
enter_scratch_dir()
with lifecycle("generate", wait=120) as held, exclusive("crs-generation") as alone:
    if not held:
        log_outcome(OP, "skipped=epoch_change_running")
        sys.exit(0)
    bits = pick_crs_bits(valid=alone and crs_request_allowed())
    rc, out = run_cli(["--max-iter", 600, "insecure-crs-gen", "--max-num-bits", bits], timeout=600)
    log_outcome(OP, cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("crs", request_id_from(out), "insecure")
