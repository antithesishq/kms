#!/usr/bin/env bash
#=============================================================================
# Reproduces the key-migration share split (scratchbook/workload-ledger.md,
# Status, 2026-10-21) on k3s, without faults or concurrency: a keygen with
# --existing-keyset-id K --copy-compressed-key-to-original while core 3 is
# down replaces K's shares on cores 1, 2 and 4 and leaves core 3 with the old
# one. Decrypts K through all four cores and through each three-core subset,
# before and after.
#
#   antithesis/local/repro-key-migration-split.sh [label]
#
# Expected (2026-10-21, cded1193): every decryption succeeds before. After,
# four cores succeed only by correcting core 3's share ("Share of party 3 ...
# is invalid"), cores 1, 2, 4 succeed, and the subsets with core 3 never
# finish: robust open waits for the missing core's share for 30 min, then
# fails "Could not reconstruct the sharing" (killed here at 15 min).
#
# Writes antithesis/local/out/<label>/ (label defaults to key-migration-split):
# steps.log, each CLI run's output, and each core's log. Needs make build and
# make k3s, like run-local.sh; deletes and redeploys the kapp app kms.
#=============================================================================
set -uo pipefail

NS=kms-threshold-staging
POD=kms-core-client-0
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config}"
OUT="${HERE}/out/${1:-key-migration-split}"
rm -rf "${OUT}" && mkdir -p "${OUT}"
n=0

log() { echo "[$(date -u +%T)] $*" | tee -a "${OUT}/steps.log"; }
kx() { kubectl exec -n "${NS}" "${POD}" -- "$@"; }

# cli NAME CONFIG ARGS...: one kms-core-client run in /tmp/repro, output in OUT/NN-NAME.log.
cli() {
    local name=$1 cfg=$2
    shift 2
    n=$((n + 1))
    local f
    f="${OUT}/$(printf %02d ${n})-${name}.log"
    log "${name}: kms-core-client -l -f ${cfg} $*"
    kx sh -c "cd /tmp/repro && timeout 900 kms-core-client -l -f ${cfg} $*" >"${f}" 2>&1
    local rc=$?
    log "  -> exit ${rc} $(grep -oE 'Error: .{0,160}' "${f}" | tail -1)"
    return ${rc}
}

request_id() { grep -oE '"request_id": "[0-9a-fA-F]+"' "$1" | tail -1 | grep -oE '[0-9a-fA-F]{64}'; }

core_down() {
    log "scale kms-core-$1-core to 0"
    kubectl scale -n "${NS}" "statefulset/kms-core-$1-core" --replicas=0 >/dev/null
    kubectl wait -n "${NS}" --for=delete "pod/kms-core-$1-core-$1" --timeout=3m >/dev/null 2>&1 || true
    sleep 5
}

core_up() {
    log "scale kms-core-$1-core to 1"
    kubectl scale -n "${NS}" "statefulset/kms-core-$1-core" --replicas=1 >/dev/null
    sleep 5
    kubectl wait -n "${NS}" --for=condition=Ready "pod/kms-core-$1-core-$1" --timeout=5m >/dev/null
    sleep 10
}

# decrypt NAME CONFIG KEY: -a (every response, each checked) only with all four cores; with a
# three-core config it would still wait for four responses.
decrypt() {
    local all=()
    [[ "$2" == all.toml ]] && all=(-a)
    cli "$1" "$2" --max-iter 120 "${all[@]}" public-decrypt from-args --to-encrypt 0x2a --data-type euint8 \
        --key-id "$3" --batch-size 1
}

log "deploy"
"${ROOT}/config/render.sh" >/dev/null
kapp delete -a kms --yes >/dev/null 2>&1 || true
kapp deploy -a kms -f "${ROOT}/build/config/manifests" --yes >"${OUT}/deploy.log" 2>&1 ||
    { tail -20 "${OUT}/deploy.log"; exit 1; }
kubectl wait -n "${NS}" --for=condition=Ready "pod/${POD}" --timeout=5m >/dev/null
kubectl wait -n "${NS}" --for=condition=complete job/kms-core-init-threshold-init --timeout=10m >/dev/null

log "first key"
kx /opt/antithesis/test/v1/main/first_generate_key.py >"${OUT}/first-key.log" 2>&1 || { log "first key failed"; exit 1; }
KEY=$(kx ls /tmp/kms-workload-state/first-key)
log "key ${KEY}"

# Client configs: all four cores, and each three-core subset (as helper_common.write_client_config).
kx sh -c 'mkdir -p /tmp/repro && cd /tmp/repro && cp /app/kms-core-client/config.toml all.toml && python3 -c "
import re
text = open(\"all.toml\").read()
head, *blocks = text.split(\"[[cores]]\")
for left in (1, 2, 3, 4):
    kept = [b for b in blocks if not re.search(rf\"(?m)^party_id *= *{left} *$\", b)]
    open(f\"no{left}.toml\", \"w\").write(head + \"num_parties = 4\n\" + \"\".join(\"[[cores]]\" + b for b in kept))
"'

log "== before the migration"
decrypt before-all all.toml "${KEY}"
decrypt before-no4 no4.toml "${KEY}"
decrypt before-no1 no1.toml "${KEY}"
decrypt before-no3 no3.toml "${KEY}"

log "== preprocessing for the migration (all four cores)"
cli preproc all.toml --max-iter 1200 insecure-preproc-key-gen
PREPROC=$(request_id "${OUT}/$(printf %02d ${n})-preproc.log")
log "preproc ${PREPROC}"

core_down 3
log "== migration with core 3 down"
cli migrate no3.toml --max-iter 1200 insecure-key-gen --preproc-id "${PREPROC}" \
    --existing-keyset-id "${KEY}" --copy-compressed-key-to-original
core_up 3

log "== after the migration, core 3 back"
decrypt after-all all.toml "${KEY}"
decrypt after-no4 no4.toml "${KEY}"
decrypt after-no1 no1.toml "${KEY}"
decrypt after-no3 no3.toml "${KEY}"

log "== server logs"
for c in 1 2 3 4; do
    kubectl logs -n "${NS}" "kms-core-${c}-core-${c}" -c kms-core >"${OUT}/core-${c}.log" 2>&1 || true
    log "core ${c}: $(grep -c 'Copied compressed key' "${OUT}/core-${c}.log") copies," \
        "$(grep -c 'is invalid after iteration' "${OUT}/core-${c}.log") invalid-share warnings," \
        "$(grep -c 'Could not reconstruct the sharing' "${OUT}/core-${c}.log") failed reconstructions"
done
kapp delete -a kms --yes >/dev/null 2>&1 || true
log "done: ${OUT}"
