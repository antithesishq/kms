#!/usr/bin/env bash
# speedrun setup #2: same as setup #1 (HEAD manifests and workload, speedrun-3095d82a images,
# network faults only), now with the KMS images pushed first. Rendered from git HEAD so the
# workload being edited in the working tree doesn't leak into this run.
set -euo pipefail
cd /home/exedev/kms
OUT=antithesis/build/config-setup2
rm -rf "$OUT"; mkdir -p "$OUT/manifests"
for f in $(git ls-tree --name-only HEAD antithesis/config/manifests/); do
    git show "HEAD:$f" | sed "s/@KMS_TAG@/speedrun-3095d82a/g" > "$OUT/manifests/${f##*/}"
done
antithesis/build/bin/snouty validate "$OUT" > antithesis/scratchbook/logs/validate-setup-2.txt 2>&1
antithesis/build/bin/snouty --json launch \
  --launcher advanced_k8s_test \
  --config "$OUT" \
  --duration 15 \
  --source speedrun \
  --test-name "speedrun/zama-kms/kms@3095d82a" \
  --description "speedrun setup #2: setup #1 again with the KMS images pushed (setup #1 couldn't pull them); existing public_decrypt workload, network faults only" \
  --param attrs.tool=speedrun --param attrs.customer=zama-kms --param attrs.system=kms \
  --param attrs.purpose=setup --param attrs.build=current --param attrs.ref=3095d82a \
  --param custom.enabled_faults=network \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-'
