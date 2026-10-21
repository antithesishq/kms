#!/usr/bin/env python3
"""AbortKeyGen on random cores. It takes a preprocessing ID, not a keygen ID: mostly one a
keygen driver took, whose keygen may still be running, and sometimes an unknown or malformed
one. Insecure keygens finish within seconds, so most calls answer NOT_FOUND. No abort is sent
while a reshare runs (helper_common.lifecycle)."""
import sys

from helper_common import exit_unless_active, lifecycle, log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "keygen.abort"

exit_unless_active(OP, "keygen_abort", 60)
ids = pool("preproc-taken") or pool("preproc")
with lifecycle("generate", wait=120) as held:
    if not held:
        log_outcome(OP, "skipped=epoch_change_running")
        sys.exit(0)
    for _ in range(pick_count(1, 3)):
        _, address = pick_core()
        log_outcome(OP, call_with_request_id(address, "AbortKeyGen", pick_request_id(ids), timeout=30))
