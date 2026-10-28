#!/usr/bin/env bash
#=============================================================================
# Renders manifests/ into ../build/config-vss/manifests/, the config of the
# VSS harness that Antithesis launches. It fills in the tag of the last
# build-vss.sh run (../build/vss-tag), or VSS_TAG if set.
#
#   antithesis/config-vss/render.sh
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TAG_FILE="$(cd "${HERE}/.." && pwd)/build/vss-tag"
if [[ -z "${VSS_TAG:-}" && -f "${TAG_FILE}" ]]; then
    VSS_TAG="$(<"${TAG_FILE}")"
fi
[[ -n "${VSS_TAG:-}" ]] || { echo "ERROR: no tag in ${TAG_FILE}; run build-vss.sh first, or set VSS_TAG." >&2; exit 1; }

OUT="$(cd "${HERE}/.." && pwd)/build/config-vss"
rm -rf "${OUT}"
mkdir -p "${OUT}/manifests"
for f in "${HERE}"/manifests/*.yaml; do
    sed "s/@VSS_TAG@/${VSS_TAG}/g" "${f}" >"${OUT}/manifests/${f##*/}"
done

echo "Rendered ${OUT} with tag ${VSS_TAG}"
