#!/usr/bin/env bash
# speedrun iterate #1: first run of the speedrun workload for Guarantees 1 and 2
# (workload content hash e3587b5624f9, rendered to antithesis/build/config-iter1), network faults only.
set -euo pipefail
cd /home/exedev/kms
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config antithesis/build/config-iter1 \
  --duration 30 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun iterate #1: new Guarantee 1 driver (3/4-core configs, retries) and Guarantee 2 recovery check, init-container cert retry; network faults only" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=iterate --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
