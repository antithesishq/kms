#!/usr/bin/env bash
#=============================================================================
# Runs the test commands in the kms-core-client pod in the order Antithesis
# would, without faults: keygen once, the public and user decrypt drivers, a
# reshare, both drivers again, then the recovery check. Stops at the first command that fails.
#
#   antithesis/local/test.sh
#
# Each run generates a new key. Override DRIVER_RUNS (default 3) to change how
# many times the driver runs before and after the reshare.
#=============================================================================
set -euo pipefail

NS=kms-threshold-staging
POD=kms-core-client-0
T=/opt/antithesis/test/v1/public_decrypt
DRIVER_RUNS="${DRIVER_RUNS:-3}"

# The pod may still be starting, e.g. right after make up or a pod delete.
kubectl wait -n "${NS}" --for=condition=Ready "pod/${POD}" --timeout=5m

run() { echo; echo "=== $1 ==="; kubectl exec -n "${NS}" "${POD}" -- "${T}/$1"; }

run first_generate_key.sh
for _ in $(seq "${DRIVER_RUNS}"); do run parallel_driver_public_decrypt.sh; run parallel_driver_user_decrypt.sh; done
run anytime_reshare_key.sh
for _ in $(seq "${DRIVER_RUNS}"); do run parallel_driver_public_decrypt.sh; run parallel_driver_user_decrypt.sh; done
run eventually_recovers_after_faults.sh

echo
echo "All test commands exited 0."
