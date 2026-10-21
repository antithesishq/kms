#!/usr/bin/env python3
"""GetEpochResult on random cores, for epochs the workload created, failed to create or
destroyed, the kms-init epoch, and unknown or malformed IDs."""
from helper_common import DEFAULT_EPOCH_ID, log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "epoch.get_result"

ids = pool("epochs") + pool("epochs-rejected") + pool("epochs-prss") + pool("epochs-destroyed") + [DEFAULT_EPOCH_ID]
for _ in range(pick_count(1, 5)):
    _, address = pick_core()
    log_outcome(OP, call_with_request_id(address, "GetEpochResult", pick_request_id(ids), timeout=30))
