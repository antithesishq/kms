#!/usr/bin/env bash
# speedrun: launches one hunt run.
#   launch-hunt.sh <variant: current|prefix> <n> <fault level: 3|4> <minutes> <description> [extra --param pairs...]
set -euo pipefail
PURPOSE="${PURPOSE:-hunt}"
VARIANT="$1"; N="$2"; LEVEL="$3"; MIN="$4"; DESC="$5"; shift 5
cd /home/exedev/kms
case "${VARIANT}" in
    current) CFG=antithesis/build/config-w3cce831073f5; REF=3095d82a ;;
    prefix)  CFG=antithesis/config-prefix;               REF=3095d82a-prefix887 ;;
    fixverify-decryption-stalls-after-core-restart)
             CFG=antithesis/config-fixverify-decryption-stalls-after-core-restart; REF=3095d82a-fix-decryption-stalls ;;
    *) echo "unknown variant ${VARIANT}" >&2; exit 2 ;;
esac
FAULTS=(--param custom.enabled_faults=network,pod_stop,pod_kill,clock_jitter)
if [[ "${LEVEL}" == "4" ]]; then
    FAULTS+=(--param custom.strobe_quiet_max_seconds=120 --param custom.strobe_quiet_min_seconds=60)
fi
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config "${CFG}" \
  --duration "${MIN}" \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@${REF}" \
  --description "speedrun ${PURPOSE} ${VARIANT} #${N}: ${DESC}" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param "attrs.purpose=${PURPOSE}" --param "attrs.build=${VARIANT}" --param "attrs.ref=${REF}" \
  --param antithesis.performance_tier=turbo \
  "${FAULTS[@]}" "$@" \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
