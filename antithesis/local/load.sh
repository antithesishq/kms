#!/usr/bin/env bash
#=============================================================================
# Imports every image the manifests reference into the local k3s node.
# k3s runs its own containerd and cannot see the podman (or docker) image
# store, and every manifest uses imagePullPolicy: Never, as in Antithesis.
#
#   antithesis/local/load.sh
#
# Our images must already be built (make build). Anything else the manifests
# reference (the MinIO images) is pulled first if it is not local yet.
#
# Override any of: ENGINE, REG, TAG (see ../images/settings.sh), IMPORT_CMD,
# LIST_CMD.
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "${HERE}/../images/settings.sh"
MANIFESTS="${HERE}/../config/manifests"

IMPORT_CMD="${IMPORT_CMD:-sudo k3s ctr images import}"
LIST_CMD="${LIST_CMD:-sudo k3s ctr images ls -q}"

command -v "${ENGINE}" >/dev/null || { echo "ERROR: ${ENGINE} not found" >&2; exit 1; }

images=()
while read -r img; do images+=("${img}"); done < <(
    grep -hE '^[[:space:]-]*image:' "${MANIFESTS}"/*.yaml | awk '{ print $NF }' | tr -d "\"'" | sort -u
)

for img in "${images[@]}"; do
    "${ENGINE}" image inspect "${img}" >/dev/null 2>&1 && continue
    if [[ "${img}" == "${REG}/"* ]]; then
        echo "ERROR: ${img} not found in ${ENGINE}; run make build first." >&2
        exit 1
    fi
    echo "Pulling ${img}"
    "${ENGINE}" pull "${img}"
done

echo "Importing into k3s:"
printf '  %s\n' "${images[@]}"
save=("${ENGINE}" save)
[[ "${ENGINE}" == "podman" ]] && save+=(--multi-image-archive)
"${save[@]}" "${images[@]}" | ${IMPORT_CMD} -

present="$(${LIST_CMD})"
for img in "${images[@]}"; do
    grep -qxF "${img}" <<<"${present}" || { echo "ERROR: ${img} is not in k3s after the import." >&2; exit 1; }
done
echo "All ${#images[@]} images are in k3s."
