#!/usr/bin/env bash
#=============================================================================
# Renders manifests/ into ../build/config/manifests/, the config that
# Antithesis launches and local k3s deploys. The manifests reference our
# images as ${REG}/kms/<name>:@KMS_TAG@. This fills in the tag of the last
# build (see ../images/settings.sh).
#
#   antithesis/config/render.sh
#
# Override TAG to render a different build.
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../images/settings.sh"
need_tag

OUT="$(cd "${HERE}/.." && pwd)/build/config"

rm -rf "${OUT}"
mkdir -p "${OUT}/manifests"
for f in "${HERE}"/manifests/*.yaml; do
    sed "s/@KMS_TAG@/${TAG}/g" "${f}" >"${OUT}/manifests/${f##*/}"
done

echo "Rendered ${OUT} with tag ${TAG}"
