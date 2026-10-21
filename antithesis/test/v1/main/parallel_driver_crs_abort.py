#!/usr/bin/env python3
"""AbortCrsGen on random cores, for generated CRS IDs (whose ceremony is over, so mostly
NOT_FOUND) and for unknown or malformed ones. Never while a reshare runs (lifecycle)."""
import sys

from helper_common import exit_unless_active, lifecycle, log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "crs.abort"

exit_unless_active(OP, "crs_abort", 60)
ids = pool("crs")
with lifecycle("generate", wait=120) as held:
    if not held:
        log_outcome(OP, "skipped=epoch_change_running")
        sys.exit(0)
    for _ in range(pick_count(1, 3)):
        _, address = pick_core()
        log_outcome(OP, call_with_request_id(address, "AbortCrsGen", pick_request_id(ids), timeout=30))
