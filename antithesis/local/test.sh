#!/usr/bin/env bash
#=============================================================================
# Runs the test commands in the kms-core-client pod without faults: the first_
# keygen once, then every parallel driver DRIVER_RUNS times (default 2), first
# one at a time and then all at once, then the eventually_ recovery check.
# Unlike Test Composer it runs every command; it is a check that each one works,
# not a stand-in for exploration.
#
#   antithesis/local/test.sh [label]
#
# Writes antithesis/local/out/<label>/ (label defaults to check):
#   workload.log  every command's output, with an "EXIT <command> <code>" line
#   ops.txt       count of OP lines per operation and outcome
#   sdk.jsonl     the assertions the commands emitted (declarations and evaluations)
# Exits 1 if any command exited non-zero.
#=============================================================================
set -uo pipefail

NS=kms-threshold-staging
POD=kms-core-client-0
T=/opt/antithesis/test/v1/main
DRIVER_RUNS="${DRIVER_RUNS:-2}"
OUT="$(cd "$(dirname "$0")" && pwd)/out/${1:-check}"
mkdir -p "${OUT}"
LOG="${OUT}/workload.log"
RUNS="${OUT}/runs"
rm -rf "${RUNS}" && mkdir -p "${RUNS}"

# The pod may still be starting, e.g. right after make up or a pod delete.
kubectl wait -n "${NS}" --for=condition=Ready "pod/${POD}" --timeout=5m || exit 1

# run COMMAND: one run, logged to its own file so concurrent runs don't interleave. The
# name starts with the start time, so the logs sort in start order.
run() {
    local log
    log="${RUNS}/$(date +%s%N)-${BASHPID}-$1.log"
    echo "=== $1 ===" >"${log}"
    kubectl exec -n "${NS}" "${POD}" -- "${T}/$1" >>"${log}" 2>&1
    local rc=$?
    echo "EXIT $1 ${rc}" | tee -a "${log}"
}

drivers=$(kubectl exec -n "${NS}" "${POD}" -- ls "${T}" | grep '^parallel_driver_')

run first_generate_key.py
for _ in $(seq "${DRIVER_RUNS}"); do
    for d in ${drivers}; do run "${d}"; done
    for d in ${drivers}; do run "${d}" & done
    wait
done
run eventually_recovers_after_faults.py

cat "${RUNS}"/*.log >"${LOG}"
grep '^OP ' "${LOG}" | sort | uniq -c | sort -k2,2 -k1,1nr >"${OUT}/ops.txt"
kubectl exec -n "${NS}" "${POD}" -- cat /tmp/antithesis-sdk.jsonl >"${OUT}/sdk.jsonl" 2>/dev/null || true
failures=$(grep -c '^EXIT .* [1-9][0-9]*$' "${LOG}")
echo
cat "${OUT}/ops.txt"
echo
echo "${failures} command run(s) exited non-zero; output in ${OUT}/"
[[ ${failures} -eq 0 ]]
