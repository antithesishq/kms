# Shared by build.sh, push.sh, ../config/render.sh and ../local/load.sh.
# Override any of these from the environment.

ENGINE="${ENGINE:-podman}"
REG="${REG:-us-central1-docker.pkg.dev/molten-verve-216720/zama-repository}"

# build.sh tags the images with the git commit it builds, plus -dirty-<time> if
# the tree has uncommitted changes, and records the tag in TAG_FILE. Everything
# after it reads the tag from there, so it always uses the last build.
TAG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/build/tag"
if [[ -z "${TAG:-}" && -f "${TAG_FILE}" ]]; then
    TAG="$(<"${TAG_FILE}")"
fi

need_tag() {
    [[ -n "${TAG:-}" ]] || { echo "ERROR: no image tag in ${TAG_FILE}; run make build first, or set TAG." >&2; exit 1; }
}

# The images the manifests reference, as ${REG}/kms/<name>:${TAG}.
IMAGES=(core-service core-service-probe core-client init-envsubst)
