#!/usr/bin/env python3
"""GetPublicDecryptionResult on random cores: request IDs of public decryptions the CLI
completed, plus unknown and malformed IDs. A pending request makes the core wait up to 60 s."""
from helper_common import log_outcome, pick_count, pick_request_id, pool
from helper_grpc import call_with_request_id, pick_core

OP = "pubdec.get_result"

ids = pool("pubdec")
for _ in range(pick_count(1, 10)):
    _, address = pick_core()
    log_outcome(OP, call_with_request_id(address, "GetPublicDecryptionResult", pick_request_id(ids), 75))
