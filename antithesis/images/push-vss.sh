#!/usr/bin/env bash
#=============================================================================
# Pushes the image of the last build-vss.sh run to the Antithesis registry.
#
#   antithesis/images/push-vss.sh
#
# Override any of: ENGINE, REG, VSS_TAG.
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TAG=unused
. "${HERE}/settings.sh"
TAG_FILE="${HERE}/../build/vss-tag"
if [[ -z "${VSS_TAG:-}" && -f "${TAG_FILE}" ]]; then
    VSS_TAG="$(<"${TAG_FILE}")"
fi
[[ -n "${VSS_TAG:-}" ]] || { echo "ERROR: no tag in ${TAG_FILE}; run build-vss.sh first, or set VSS_TAG." >&2; exit 1; }

"${ENGINE}" push "${REG}/kms/vss-harness:${VSS_TAG}"
