#!/usr/bin/env python3
"""GetCrsGenResult on random cores, for generated CRS IDs (secure or insecure: both RPCs read the same
store) and for unknown or malformed ones."""
from helper_common import log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "crs.get_result"

ids = pool("crs")
for _ in range(pick_count(1, 5)):
    _, address = pick_core()
    log_outcome(OP, call_with_request_id(address, "GetCrsGenResult", pick_request_id(ids), timeout=30))
