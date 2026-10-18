#!/usr/bin/env bash
# speedrun setup #1: first run of the speedrun-3095d82a images, fault level 1 (network only)
set -euo pipefail
cd /home/exedev/kms
TAG=speedrun-3095d82a antithesis/config/render.sh
antithesis/build/bin/snouty validate antithesis/build/config > antithesis/scratchbook/logs/validate-setup-1.txt 2>&1
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config antithesis/build/config \
  --duration 15 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun setup #1: first run of the instrumented speedrun-3095d82a images, existing public_decrypt workload, network faults only" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=setup --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
