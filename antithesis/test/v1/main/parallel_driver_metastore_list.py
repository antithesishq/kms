#!/usr/bin/env python3
"""ListRequests (MetaStoreStatusService) on random cores: one meta store or all, an optional
status filter (one that doesn't exist too), a page size that is unset, non-positive, small,
at the 1000 cap or past it, and a page token that is unset, a valid offset, or unparsable."""
from helper_common import log_outcome, pick, pick_count
from helper_grpc import METASTORE_SERVICE, call, pb_string, pb_varint, pick_core

OP = "metastore.list"

for _ in range(pick_count(1, 3)):
    payload = pb_varint(1, pick([0, 1, 2, 3, 4, 5, 9]))
    status = pick([None, None, 0, 1, 2, 3, 4, 7])
    if status is not None:
        payload += pb_varint(2, status)
    size = pick([None, 0, -1, 1, 10, 1000, 5000])
    if size is not None:
        payload += pb_varint(3, size)
    token = pick([None, None, "0", "1", "5", "100", "18446744073709551615", "x", "-1"])
    if token is not None:
        payload += pb_string(4, token)
    _, address = pick_core()
    log_outcome(OP, call(address, METASTORE_SERVICE + "ListRequests", payload, timeout=30))
