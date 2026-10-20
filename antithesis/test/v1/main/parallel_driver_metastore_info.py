#!/usr/bin/env python3
"""GetMetaStoreInfo (MetaStoreStatusService, empty request) on random cores: each meta
store's capacity and current count."""
from helper_common import log_outcome, pick_count
from helper_grpc import METASTORE_SERVICE, call, pick_core

OP = "metastore.info"

for _ in range(pick_count(1, 3)):
    _, address = pick_core()
    log_outcome(OP, call(address, METASTORE_SERVICE + "GetMetaStoreInfo", b"", timeout=30))
