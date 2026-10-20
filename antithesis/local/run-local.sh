#!/usr/bin/env bash
#=============================================================================
# One local coverage run on k3s: deploy the coverage build from scratch, run the
# workload with local_composer.py (a stand-in for Test Composer: no faults, no
# eventually_ commands), stop the cores so their last counters reach the
# profiles, and convert the profiles to LCOV.
#
#   antithesis/local/run-local.sh <label> [seed]
#
# Writes antithesis/local/out/<label>/:
#   workload.log   the composer's output: every command's output, then a summary
#   ops.txt        count of OP lines per operation and outcome
#   sdk.jsonl      the assertions the commands emitted
#   raw/<core>/    each core's .profraw files
#   coverage.lcov  kms-server coverage of all four cores, for
#                  coverage_report.py normalize --format lcov (see
#                  scratchbook/coverage-setup.md for its arguments)
#
# Needs make build, images/build-coverage.sh and make k3s. Takes about
# DURATION + 5 minutes. It deletes and redeploys the kapp app kms, MinIO's
# volume included, so every run starts from the same state.
#=============================================================================
set -euo pipefail

# ---- settings ---------------------------------------------------------------
DURATION="${DURATION:-480}"        # seconds of driver activity
CONCURRENCY="${CONCURRENCY:-4}"    # drivers running at once
COMMAND_TIMEOUT=900                # above every driver's worst case
NS=kms-threshold-staging
CLIENT_POD=kms-core-client-0
COVERAGE_DIR=/var/lib/kms-coverage # host folder that coverage-config.py mounts
# -----------------------------------------------------------------------------

label="${1:?usage: run-local.sh <label> [seed]}"
seed="${2:-0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
. "${ROOT}/images/settings.sh"
need_tag
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
out="${HERE}/out/${label}"
rm -rf "${out}" && mkdir -p "${out}"
COVERAGE_IMAGE="${REG}/kms/core-service:${TAG}-coverage"
TOOLS_IMAGE="localhost/kms-antithesis/kms-coverage-tools:intermediate"

# k3s starts deleting unused images and evicting pods at 85 % disk use, which silently
# ruins a run. Each run leaves about 600 MB here (coverage.lcov is most of it; delete it
# once the snapshot is normalized, raw/ can regenerate it).
used="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
if [[ "${used}" -ge 82 ]]; then
    echo "ERROR: / is ${used}% full; k3s evicts at 85%. Free space (old local/out/*/coverage.lcov) first." >&2
    exit 1
fi

echo "== images (${TAG})"
"${ROOT}/config/render.sh" >/dev/null
present="$(sudo k3s ctr images ls -q)"
for img in $(grep -hE '^[[:space:]-]*image:' "${ROOT}"/build/config/manifests/*.yaml | awk '{ print $NF }' | sort -u); do
    grep -qxF "${img}" <<<"${present}" || { "${HERE}/load.sh"; break; }
done
# A rebuild of the coverage image keeps its tag, so the image ID decides whether k3s has it.
coverage_id="$("${ENGINE}" image inspect --format '{{.Id}}' "${COVERAGE_IMAGE}" 2>/dev/null)" ||
    { echo "ERROR: ${COVERAGE_IMAGE} not found; run images/build-coverage.sh" >&2; exit 1; }
imported="${ROOT}/build/coverage-image-imported"
if ! grep -qxF "${COVERAGE_IMAGE}" <<<"${present}" || [[ "$(cat "${imported}" 2>/dev/null)" != "${coverage_id}" ]]; then
    "${ENGINE}" save "${COVERAGE_IMAGE}" | sudo k3s ctr images import -
    echo "${coverage_id}" >"${imported}"
fi

echo "== deploying the coverage build"
statefulsets="$(python3 "${HERE}/coverage-config.py")"
kapp delete -a kms --yes >/dev/null 2>&1 || true
sudo rm -rf "${COVERAGE_DIR}"
for s in ${statefulsets}; do sudo install -d -m 0777 "${COVERAGE_DIR}/${s}"; done
kapp deploy -a kms -f "${ROOT}/build/config-coverage/manifests" --yes >"${out}/deploy.log" 2>&1 ||
    { tail -20 "${out}/deploy.log"; exit 1; }
kubectl wait -n "${NS}" --for=condition=Ready "pod/${CLIENT_POD}" --timeout=5m

echo "== running the workload for ${DURATION} s (seed ${seed}, concurrency ${CONCURRENCY})"
kubectl exec -i -n "${NS}" "${CLIENT_POD}" -- sh -c 'cat > /tmp/local_composer.py' <"${HERE}/local_composer.py"
kubectl exec -n "${NS}" "${CLIENT_POD}" -- python3 /tmp/local_composer.py --template main \
    --duration "${DURATION}" --concurrency "${CONCURRENCY}" --seed "${seed}" \
    --command-timeout "${COMMAND_TIMEOUT}" >"${out}/workload.log" 2>&1 || true
grep '^OP ' "${out}/workload.log" | sort | uniq -c | sort -k2,2 -k1,1nr >"${out}/ops.txt" || true
kubectl exec -n "${NS}" "${CLIENT_POD}" -- cat /tmp/antithesis-sdk.jsonl >"${out}/sdk.jsonl" 2>/dev/null || true

echo "== stopping the cores, so their last counters reach the profiles"
for s in ${statefulsets}; do kubectl scale -n "${NS}" "statefulset/${s}" --replicas=0 >/dev/null; done
kubectl wait -n "${NS}" --for=delete pod -l app=kms-core --timeout=3m
mkdir -p "${out}/raw"
sudo cp -r "${COVERAGE_DIR}/." "${out}/raw/"
sudo chown -R "$(id -u):$(id -g)" "${out}/raw"
[[ -n "$(find "${out}/raw" -name '*.profraw' -size +0)" ]] ||
    { echo "ERROR: no coverage profiles written; see scratchbook/coverage-setup.md" >&2; exit 1; }

echo "== converting the profiles to LCOV"
# llvm-cov export ignores -Xdemangler, so the function names go through rustfilt after it.
"${ENGINE}" run --rm -v "${out}:/work" "${TOOLS_IMAGE}" sh -c '
    set -e
    llvm-profdata merge -sparse /work/raw/*/*.profraw -o /work/merged.profdata
    llvm-cov export -format=lcov -instr-profile=/work/merged.profdata /out/kms-server |
        /root/.cargo/bin/rustfilt >/work/coverage.lcov
    rm /work/merged.profdata
    chown -R '"$(id -u):$(id -g)"' /work'

kapp delete -a kms --yes >/dev/null 2>&1 || true
echo
tail -n 12 "${out}/workload.log" | grep '^\[local_composer\]' || true
cat "${out}/ops.txt"
echo "== done: ${out}"
