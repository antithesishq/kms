#!/usr/bin/env python3
"""Generate one FHE key before the drivers run, so decryption has a key from the start.

Antithesis runs first_ commands once per timeline, before any driver and with no faults.
This is one-time preparation, not a check: insecure preprocessing, then insecure keygen
(each CLI command also polls its result RPC), up to 5 tries 10 s apart.
"""
import sys

from helper_common import cli_outcome, enter_scratch_dir, log_outcome, record, request_id_from, run_cli, sleep
from helper_properties import MSG_KEYGEN, declare_catalog, reachable

declare_catalog()
enter_scratch_dir()
for attempt in range(1, 6):
    rc, out = run_cli(["--max-iter", 1200, "insecure-preproc-key-gen"], timeout=900)
    log_outcome("preproc.start_insecure", cli_outcome(rc, out))
    preproc_id = request_id_from(out) if rc == 0 else None
    if preproc_id:
        record("preproc-taken", preproc_id)
        rc, out = run_cli(["--max-iter", 1200, "insecure-key-gen", "--preproc-id", preproc_id], timeout=900)
        log_outcome("keygen.start_insecure", cli_outcome(rc, out))
        key_id = request_id_from(out) if rc == 0 else None
        if key_id:
            # A reshare must name the preprocessing ID a key came from; no public object has it.
            record("keys", key_id, preproc_id)
            record("first-key", key_id)
            reachable(MSG_KEYGEN, {"key_id": key_id, "keygen": "insecure-key-gen", "attempt": attempt})
            sys.exit(0)
    print(out[-2000:])
    sleep(10)
print("keygen failed 5 times")
sys.exit(1)
