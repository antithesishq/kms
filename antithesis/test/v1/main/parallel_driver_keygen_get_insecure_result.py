#!/usr/bin/env python3
"""GetInsecureKeyGenResult on random cores, for generated or published key IDs and for
unknown or malformed ones."""
from helper_common import log_outcome, pick_count, pick_request_id, pool, published_keys
from helper_grpc import call_with_request_id, pick_core

OP = "keygen.get_insecure_result"

ids = pool("keys") or published_keys()
for _ in range(pick_count(1, 10)):
    _, address = pick_core()
    outcome = call_with_request_id(address, "GetInsecureKeyGenResult", pick_request_id(ids), timeout=30)
    log_outcome(OP, outcome)
