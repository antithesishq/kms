#!/usr/bin/env bash
# speedrun iterate #2: same workload as iterate #1 (configmap@e3587b5624f9, frozen in
# antithesis/build/config-iter1), fault level 2: network plus pod kills (median 600 s apart).
set -euo pipefail
cd /home/exedev/kms
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config antithesis/build/config-iter1 \
  --duration 30 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun iterate #2: iterate #1's workload with pod kills added (fault level 2: network,pod_kill, interval 600 s)" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=iterate --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network,pod_kill \
  --param custom.pod_fault_interval_seconds=600 \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
