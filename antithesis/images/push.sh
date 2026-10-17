#!/usr/bin/env bash
#=============================================================================
# Pushes the images of the last build.sh run to the Antithesis registry, under
# the tag that build.sh recorded in ../build/tag.
#
#   antithesis/images/push.sh            # show what it would do
#   antithesis/images/push.sh --push     # actually push
#
# Override any of: ENGINE, REG, TAG (see settings.sh).
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/settings.sh"
need_tag

DO_PUSH="false"
[[ "${1:-}" == "--push" ]] && DO_PUSH="true"

command -v "${ENGINE}" >/dev/null || { echo "ERROR: ${ENGINE} not found" >&2; exit 1; }

run() { echo "  \$ $*"; [[ "${DO_PUSH}" == "true" ]] && "$@"; return 0; }

for img in "${IMAGES[@]}"; do
    "${ENGINE}" image inspect "${REG}/kms/${img}:${TAG}" >/dev/null 2>&1 || {
        echo "ERROR: ${REG}/kms/${img}:${TAG} not found in ${ENGINE}; run build.sh first." >&2
        exit 1
    }
done

for img in "${IMAGES[@]}"; do
    run "${ENGINE}" push "${REG}/kms/${img}:${TAG}"
done

if [[ "${DO_PUSH}" != "true" ]]; then
    echo
    echo "Dry run. Re-run with --push to execute."
    echo "Log in first, for example:"
    echo "  ${ENGINE} login -u _json_key --password-stdin https://us-central1-docker.pkg.dev < <your-antithesis-key>.json"
fi
