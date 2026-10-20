#!/usr/bin/env python3
"""GetUserDecryptionResult on random cores: request IDs of user decryptions the CLI
completed, plus unknown and malformed IDs. kms-core-client has no command for this RPC."""
from helper_common import log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "userdec.get_result"

ids = pool("userdec")
for _ in range(pick_count(1, 10)):
    _, address = pick_core()
    log_outcome(OP, call_with_request_id(address, "GetUserDecryptionResult", pick_request_id(ids), 75))
