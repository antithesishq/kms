#!/usr/bin/env bash
#=============================================================================
# Builds the VSS harness image that the config-vss manifests use:
#
#   vss-harness   the instrumented vss-harness binary (vss-harness.Dockerfile)
#
#   antithesis/images/build-vss.sh
#
# It builds the golden image the same way as build.sh, so both scripts share
# it. The tag scheme is the one of build.sh: the short git commit, with
# -dirty-<yyyymmdd-hhmm> if the tree has uncommitted changes. After the binary
# check passes, the script records the tag in ../build/vss-tag.
#
# Override any of: ENGINE (podman or docker), REG, VSS_TAG.
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KMS_SRC="$(cd "${HERE}/../.." && pwd)"
# settings.sh would load the KMS tag of the last build.sh run; this script has its own.
TAG=unused
. "${HERE}/settings.sh"

if [[ -z "${VSS_TAG:-}" ]]; then
    VSS_TAG="$(git -C "${KMS_SRC}" rev-parse --short HEAD)"
    if [[ -n "$(git -C "${KMS_SRC}" status --porcelain)" ]]; then
        VSS_TAG="${VSS_TAG}-dirty-$(date +%Y%m%d-%H%M)"
    fi
fi
VSS_TAG_FILE="${HERE}/../build/vss-tag"
IMAGE="${REG}/kms/vss-harness:${VSS_TAG}"

# See build.sh: Antithesis needs an image built in the last 72 hours.
unset SOURCE_DATE_EPOCH

ZAMA_GOLDEN_IMAGE="localhost/kms-antithesis/zama-golden:intermediate"
GOLDEN_IMAGE="localhost/kms-antithesis/rust-golden:intermediate"
RUST_TOOLCHAIN="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "${KMS_SRC}/rust-toolchain.toml")"
[[ -n "${RUST_TOOLCHAIN}" ]] || { echo "ERROR: no channel in ${KMS_SRC}/rust-toolchain.toml" >&2; exit 1; }
ZAMA_BASES=(
    --build-context cgr.dev/zama.ai/glibc-dynamic:16-dev=docker-image://cgr.dev/chainguard/glibc-dynamic:latest-dev
    --build-context cgr.dev/zama.ai/golang:1.25=docker-image://cgr.dev/chainguard/go:latest
)

step() { echo; echo "=== $* ==="; }

echo "engine: ${ENGINE}"
echo "tag: ${VSS_TAG}"

step "zama-golden: Zama's rust-golden-image (docker/base/Dockerfile)"
"${ENGINE}" build -t "${ZAMA_GOLDEN_IMAGE}" \
    -f "${KMS_SRC}/docker/base/Dockerfile" --target prod \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_IMAGE_VERSION="${RUST_TOOLCHAIN}" \
    "${KMS_SRC}"

step "golden: zama-golden + AWS_LC_SYS_NO_JITTER_ENTROPY=1"
"${ENGINE}" build -t "${GOLDEN_IMAGE}" \
    -f "${HERE}/golden.Dockerfile" \
    --build-arg ZAMA_GOLDEN_IMAGE="${ZAMA_GOLDEN_IMAGE}" \
    "${HERE}"

step "vss-harness (instrumented)"
"${ENGINE}" build -t "${IMAGE}" \
    -f "${HERE}/vss-harness.Dockerfile" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    "${KMS_SRC}"

# The same byte greps as the binary checks of build.sh.
step "Checking the binary"
tmp="$(mktemp -d)"
cid="$("${ENGINE}" create "${IMAGE}")"
trap '"${ENGINE}" rm -f "${cid}" >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT
"${ENGINE}" cp "${cid}:/usr/local/bin/vss-harness" "${tmp}/vss-harness"
for s in antithesis_load_libvoidstar __sancov_guards .debug_line; do
    if ! grep -q -a -F "${s}" "${tmp}/vss-harness"; then
        echo "ERROR: vss-harness has no ${s}; see 'Binary checks' in build.sh." >&2
        exit 1
    fi
done
echo "  ok: vss-harness"

mkdir -p "$(dirname "${VSS_TAG_FILE}")"
echo "${VSS_TAG}" >"${VSS_TAG_FILE}"
echo
echo "Built ${IMAGE}"
echo "Tag recorded in ${VSS_TAG_FILE}"
