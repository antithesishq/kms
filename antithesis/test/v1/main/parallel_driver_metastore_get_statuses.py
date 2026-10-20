#!/usr/bin/env python3
"""GetRequestStatuses (MetaStoreStatusService) on random cores: 0–5 request IDs the drivers
pooled, mixed with unknown or malformed ones, for one meta store, for all of them (ALL, or
the field unset), or for a type that doesn't exist (9)."""
from helper_common import log_outcome, pick, pick_count, pick_request_id, pool
from helper_grpc import METASTORE_SERVICE, call, pb_string, pb_varint, pick_core

OP = "metastore.get_statuses"
# MetaStoreType -> the pools holding that store's request IDs.
POOLS = {1: ["keys"], 2: ["pubdec"], 3: ["userdec"], 4: ["crs"], 5: ["preproc", "preproc-taken"]}

for _ in range(pick_count(1, 3)):
    store = pick([None, 0, 1, 2, 3, 4, 5, 9])
    names = POOLS.get(store) or [n for ns in POOLS.values() for n in ns]
    ids = [i for n in names for i in pool(n)]
    payload = b"".join(pb_string(1, pick_request_id(ids)) for _ in range(pick_count(0, 5)))
    if store is not None:
        payload += pb_varint(2, store)
    _, address = pick_core()
    log_outcome(OP, call(address, METASTORE_SERVICE + "GetRequestStatuses", payload, timeout=30))
