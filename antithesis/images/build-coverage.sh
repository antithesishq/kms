#!/usr/bin/env bash
#=============================================================================
# Builds the local-only coverage variant of the core-service image, for
# antithesis/local/run-local.sh:
#
#   <REG>/kms/core-service:<TAG>-coverage            kms-server built with coverage
#   localhost/kms-antithesis/kms-coverage-tools:intermediate
#                                                    llvm-profdata, llvm-cov,
#                                                    rustfilt, /out/kms-server
#
#   antithesis/images/build-coverage.sh
#
# Run after build.sh: it starts from that build's core-service image and the
# rust-golden image. The -coverage tag is not in settings.sh's IMAGES, so
# push.sh never pushes it and the Antithesis manifests never name it.
#
# Override any of: ENGINE (podman or docker), REG, TAG (see settings.sh).
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KMS_SRC="$(cd "${HERE}/../.." && pwd)"
. "${HERE}/settings.sh"
need_tag
unset SOURCE_DATE_EPOCH

GOLDEN_IMAGE="localhost/kms-antithesis/rust-golden:intermediate"
TOOLS_IMAGE="localhost/kms-antithesis/kms-coverage-tools:intermediate"
CORE_IMAGE="${REG}/kms/core-service:${TAG}"
COVERAGE_IMAGE="${REG}/kms/core-service:${TAG}-coverage"

for img in "${GOLDEN_IMAGE}" "${CORE_IMAGE}"; do
    "${ENGINE}" image inspect "${img}" >/dev/null 2>&1 ||
        { echo "ERROR: ${img} not found in ${ENGINE}; run make build first." >&2; exit 1; }
done

build() {
    "${ENGINE}" build -f "${HERE}/coverage.Dockerfile" \
        --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
        --build-arg CORE_IMAGE="${CORE_IMAGE}" \
        "$@" "${KMS_SRC}"
}

echo "=== coverage tools and kms-server ==="
build --target tools -t "${TOOLS_IMAGE}"
echo "=== ${COVERAGE_IMAGE} ==="
build -t "${COVERAGE_IMAGE}"

echo "Built ${COVERAGE_IMAGE} and ${TOOLS_IMAGE}"
