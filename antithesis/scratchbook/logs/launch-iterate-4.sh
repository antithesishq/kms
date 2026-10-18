#!/usr/bin/env bash
# speedrun iterate #4: full workload (3cce831073f5), fault level 3 = the launcher's default set
# (network, pod_stop, pod_kill, clock_jitter; pod faults median 300 s apart).
set -euo pipefail
cd /home/exedev/kms
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config antithesis/build/config-w3cce831073f5 \
  --duration 30 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun iterate #4: full workload, first run with the default fault set (network,pod_stop,pod_kill,clock_jitter)" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=iterate --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network,pod_stop,pod_kill,clock_jitter \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
