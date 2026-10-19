#!/usr/bin/env python3
"""Generates the FHE key that the drivers decrypt under and reshare. kms-init creates only the
MPC context and epoch, so a fresh cluster has no key.

Antithesis runs this once per timeline, before any driver and with no faults. The default is
insecure keygen because it is fast. Set KMS_WORKLOAD_KEYGEN=secure to run the real distributed
keygen instead.
"""

import os
import sys
import time

import helper_lib as h  # first: it sets up the SDK's output before the SDK loads
from antithesis.assertions import reachable

h.declare_catalog()
h.enter_scratch_dir()

if os.environ.get("KMS_WORKLOAD_KEYGEN", "insecure") == "secure":
    preproc_cmd, keygen_cmd = "preproc-key-gen", "key-gen"
else:
    preproc_cmd, keygen_cmd = "insecure-preproc-key-gen", "insecure-key-gen"

# --max-iter counts 0.5 s result polls; keygen can take minutes.
common = ["-f", "config.toml", "--max-iter", "1200"]
for attempt in range(1, 6):
    print(f"attempt {attempt}: kms-core-client {preproc_cmd}, then {keygen_cmd}")
    rc, output = h.run_cli([*common, preproc_cmd])
    preproc_id = h.request_id_from(output) if rc == 0 else None
    if preproc_id:
        rc, output = h.run_cli([*common, keygen_cmd, "--preproc-id", preproc_id])
        key_id = h.request_id_from(output) if rc == 0 else None
        if key_id:
            print(f"generated key {key_id} (preproc {preproc_id})")
            h.record_preproc(key_id, preproc_id)  # anytime_reshare_key.py needs it
            reachable(
                "workload generated an FHE key",
                {"key_id": key_id, "keygen": keygen_cmd, "attempt": attempt},
            )
            sys.exit(0)
    print(h.tail(output, 5))
    time.sleep(10)
print("keygen failed 5 times")
sys.exit(1)
