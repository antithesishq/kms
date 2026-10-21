#!/usr/bin/env python3
"""Short sequence for crs.abort: start a CRS generation in the background (insecure 7 times in
10, a ceremony otherwise), find its request ID among the CRS requests party 1 reports as
PROCESSING (ListRequests), and send AbortCrsGen after a short delay: to every core, or for an
insecure one sometimes to a single core (a ceremony aborted on some cores stalls the others).
crs.abort on its own only meets finished CRSes, so this targets the cancel path of a running
generation. Its own budget, MAX_RUNS per container (the CRS drivers use up theirs early), one
CRS generation at a time, and never while a reshare runs (lifecycle)."""
import sys

from helper_common import (chance, cli_outcome, enter_scratch_dir, exclusive, exit_unless_active, lifecycle,
                           log_outcome, paced, pick, pool, record, request_id_from, sleep, start_cli, wait_cli)
from helper_grpc import call_with_request_id, core_addresses, pending_request_ids

OP = "crs.abort"
MAX_RUNS = 3

exit_unless_active(OP, "crs_abort_running", 60)
with lifecycle("generate", wait=120) as held, exclusive("crs-generation") as alone:
    if not (held and alone and paced(len(pool("crs-abort-runs")), MAX_RUNS, "crs_abort_runs")):
        log_outcome(OP, "skipped=busy_or_budget")
        sys.exit(0)
    insecure = chance(70)
    record("crs-abort-runs", f"run{len(pool('crs-abort-runs'))}")
    enter_scratch_dir()
    try:
        crs = start_cli(["--max-iter", 600, "insecure-crs-gen" if insecure else "crs-gen", "--max-num-bits",
                         pick([16, 64, 256])])
    except OSError as e:
        log_outcome("crs.start_insecure" if insecure else "crs.start", f"error=exit126 ({e})")
        sys.exit(0)
    cores = core_addresses()
    pending = []
    for _ in range(20):
        sleep(0.5)
        pending = pending_request_ids(cores[0][1], 4)
        if pending:
            break
    sleep(pick([0, 0.5, 1, 3, 10]))
    for _, address in cores if chance(70) or not insecure else [pick(cores)]:
        log_outcome(OP, call_with_request_id(address, "AbortCrsGen", pick(pending), timeout=30) if pending
                    else "skipped=no_pending_crs")
    rc, out = wait_cli(crs, timeout=300)
    log_outcome("crs.start_insecure" if insecure else "crs.start", cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("crs", request_id_from(out), "insecure" if insecure else "secure")
