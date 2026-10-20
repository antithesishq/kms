#!/usr/bin/env python3
"""GetKeyMaterialAvailability (empty request) on random cores: which keys, CRSes and
preprocessing material each core holds."""
from helper_common import log_outcome, pick_count
from helper_grpc import SERVICE, call, pick_core

OP = "material.list"

for _ in range(pick_count(1, 3)):
    _, address = pick_core()
    log_outcome(OP, call(address, SERVICE + "GetKeyMaterialAvailability", b"", timeout=30))
