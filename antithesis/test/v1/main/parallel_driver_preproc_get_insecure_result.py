#!/usr/bin/env python3
"""GetInsecureKeyGenPreprocResult on random cores, for pooled preprocessing IDs (unused and
already consumed by a keygen) and for unknown or malformed ones."""
from helper_common import log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "preproc.get_insecure_result"

ids = pool("preproc") + pool("preproc-taken")
for _ in range(pick_count(1, 10)):
    _, address = pick_core()
    outcome = call_with_request_id(address, "GetInsecureKeyGenPreprocResult", pick_request_id(ids), timeout=30)
    log_outcome(OP, outcome)
