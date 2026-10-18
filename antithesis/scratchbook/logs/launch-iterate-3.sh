#!/usr/bin/env bash
# speedrun iterate #3: the full workload for Guarantees 1-4 (content hash 3cce831073f5, frozen in
# antithesis/build/config-w3cce831073f5), fault level 2 like iterate #2, so the only change is the workload.
set -euo pipefail
cd /home/exedev/kms
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config antithesis/build/config-w3cce831073f5 \
  --duration 30 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun iterate #3: adds the Guarantee 3 public-key check and source-epoch decrypt, and the Guarantee 4 user-decryption driver; fault level 2 (network,pod_kill, 600 s)" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=iterate --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network,pod_kill \
  --param custom.pod_fault_interval_seconds=600 \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
