#!/usr/bin/env bash
#=============================================================================
# Builds the four images the Antithesis manifests use:
#
#   core-service        kms-server, kms-gen-keys, kms-init (insecure flavour)
#   core-service-probe  core-service plus grpc_health_probe, for the init Job
#   core-client         kms-core-client and Python, which host the test commands
#   init-envsubst       the cores' config-rendering init container
#
#   antithesis/images/build.sh
#
# The KMS binaries are built with Antithesis coverage instrumentation by
# kms-binaries.Dockerfile, a variant of docker/kms-binaries/Dockerfile. Zama's
# core-service and core-client Dockerfiles package them, unmodified, and
# symbols.Dockerfile adds a /symbols layer on top of each image.
#
# Zama's Dockerfiles start FROM images in Zama's private Chainguard org.
# --build-context redirects each of those to the public image of the same name,
# so the Dockerfiles need no edits. The AWS-LC jitter-entropy fix comes in
# through the golden image (golden.Dockerfile).
#
# Images are tagged with the registry names the manifests reference, so
# pushing them needs no retagging. The tag is the short git commit, with
# -dirty-<yyyymmdd-hhmm> if the tree has uncommitted changes. After the binary
# checks pass, build.sh records the tag in ../build/tag for the other scripts.
#
# Override any of: ENGINE (podman or docker), REG, TAG (see settings.sh).
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KMS_SRC="$(cd "${HERE}/../.." && pwd)"

# Set before settings.sh, which otherwise loads the tag of the last build.
if [[ -z "${TAG:-}" ]]; then
    TAG="$(git -C "${KMS_SRC}" rev-parse --short HEAD)" || {
        echo "ERROR: ${KMS_SRC} is not a git checkout; set TAG." >&2
        exit 1
    }
    # Two builds of one commit with different uncommitted changes must not
    # share a tag in the registry.
    if [[ -n "$(git -C "${KMS_SRC}" status --porcelain)" ]]; then
        TAG="${TAG}-dirty-$(date +%Y%m%d-%H%M)"
    fi
fi
. "${HERE}/settings.sh"

# Nix shells export SOURCE_DATE_EPOCH=315532800 (1980-01-01), and podman uses
# it as the creation date of every image it builds. Antithesis checks that the
# run has an image built in the last 72 hours, so build with the real time.
unset SOURCE_DATE_EPOCH

# Intermediate images, never pushed. Fully qualified, so podman does not run
# short-name resolution on them. Their tag is fixed, so each build replaces the
# last one's and `podman image prune` can reclaim the old ones.
ZAMA_GOLDEN_IMAGE="localhost/kms-antithesis/zama-golden:intermediate"
GOLDEN_IMAGE="localhost/kms-antithesis/rust-golden:intermediate"
BINARIES_IMAGE="localhost/kms-antithesis/kms-binaries:intermediate"
ZAMA_CORE_IMAGE="localhost/kms-antithesis/zama-core-service:intermediate"
ZAMA_PROBE_IMAGE="localhost/kms-antithesis/zama-core-service-probe:intermediate"
ZAMA_CLIENT_IMAGE="localhost/kms-antithesis/zama-core-client:intermediate"
CLIENT_PYTHON_IMAGE="localhost/kms-antithesis/core-client-python:intermediate"

CORE_IMAGE="${REG}/kms/core-service:${TAG}"
PROBE_IMAGE="${REG}/kms/core-service-probe:${TAG}"
CLIENT_IMAGE="${REG}/kms/core-client:${TAG}"
ENVSUBST_IMAGE="${REG}/kms/init-envsubst:${TAG}"

# Zama's CI passes the rust-toolchain.toml channel to docker/base/Dockerfile.
RUST_TOOLCHAIN="$(sed -n 's/^channel *= *"\(.*\)"/\1/p' "${KMS_SRC}/rust-toolchain.toml")"
[[ -n "${RUST_TOOLCHAIN}" ]] || { echo "ERROR: no channel in ${KMS_SRC}/rust-toolchain.toml" >&2; exit 1; }

# Private Zama base -> public stand-in, passed to every build of a Zama Dockerfile.
ZAMA_BASES=(
    --build-context cgr.dev/zama.ai/glibc-dynamic:16-dev=docker-image://cgr.dev/chainguard/glibc-dynamic:latest-dev
    --build-context cgr.dev/zama.ai/golang:1.25=docker-image://cgr.dev/chainguard/go:latest
)

step() { echo; echo "=== $* ==="; }

#--- Preflight ---------------------------------------------------------------
command -v "${ENGINE}" >/dev/null || { echo "ERROR: ${ENGINE} not found" >&2; exit 1; }
# Later builds start FROM images that earlier builds only tagged locally.
# podman always resolves those from its local store. With docker, only the
# docker driver does; any other (e.g. docker-container) would try to pull them
# from a registry.
if [[ "${ENGINE}" == "docker" ]]; then
    # No early `exit` in awk: closing the pipe would SIGPIPE docker and, with
    # pipefail + set -e, silently abort the script.
    driver="$(docker buildx inspect 2>/dev/null | awk '$1 == "Driver:" && !d { d = $2 } END { print d }')" || true
    if [[ "${driver}" != "docker" ]]; then
        echo "ERROR: the active docker builder uses the '${driver:-unknown}' driver; ENGINE=docker needs 'docker'." >&2
        echo "       Use ENGINE=podman, or select a builder with the docker driver (docker buildx ls)." >&2
        exit 1
    fi
fi
echo "engine: ${ENGINE}"
echo "tag: ${TAG}"
echo "kms source: ${KMS_SRC}"
echo "rust toolchain: ${RUST_TOOLCHAIN} (from rust-toolchain.toml)"

#--- Golden image ------------------------------------------------------------
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

#--- KMS images --------------------------------------------------------------
# The prod and dev targets below each assert that the binaries they package
# are the insecure flavour, so a secure build cannot slip through.
step "kms-binaries (insecure, instrumented)"
"${ENGINE}" build -t "${BINARIES_IMAGE}" \
    -f "${HERE}/kms-binaries.Dockerfile" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    "${KMS_SRC}"

step "core-service (prod, EXPECTED_KMS_FLAVOR=insecure)"
"${ENGINE}" build -t "${ZAMA_CORE_IMAGE}" \
    -f "${KMS_SRC}/docker/core/service/Dockerfile" --target prod \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    --build-arg EXPECTED_KMS_FLAVOR=insecure \
    "${KMS_SRC}"

# The dev target is core-service plus grpc_health_probe, which the
# threshold-init Job uses to wait for all four cores.
step "core-service-probe (dev, with grpc_health_probe)"
"${ENGINE}" build -t "${ZAMA_PROBE_IMAGE}" \
    -f "${KMS_SRC}/docker/core/service/Dockerfile" --target dev \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    "${KMS_SRC}"

step "core-client (prod, EXPECTED_KMS_FLAVOR=insecure)"
"${ENGINE}" build -t "${ZAMA_CLIENT_IMAGE}" \
    -f "${KMS_SRC}/docker/core-client/Dockerfile" --target prod \
    "${ZAMA_BASES[@]}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    --build-arg EXPECTED_KMS_FLAVOR=insecure \
    "${KMS_SRC}"

# Python and the Antithesis Python SDK, for the test commands in test/v1/main/.
step "core-client + python"
"${ENGINE}" build -t "${CLIENT_PYTHON_IMAGE}" \
    -f "${HERE}/python.Dockerfile" \
    --build-arg BASE_IMAGE="${ZAMA_CLIENT_IMAGE}" \
    "${HERE}"

# symbols.Dockerfile on top of each, so Antithesis can symbolize coverage.
symbols() {  # <zama image> <final image> <bin dir>
    step "symbols: $(basename "${2%:*}")"
    "${ENGINE}" build -t "$2" \
        -f "${HERE}/symbols.Dockerfile" \
        --build-arg BASE_IMAGE="$1" \
        --build-arg BIN_DIR="$3" \
        "${HERE}"
}
symbols "${ZAMA_CORE_IMAGE}" "${CORE_IMAGE}" /app/kms/core/service/bin
symbols "${ZAMA_PROBE_IMAGE}" "${PROBE_IMAGE}" /app/kms/core/service/bin
symbols "${CLIENT_PYTHON_IMAGE}" "${CLIENT_IMAGE}" /app/kms-core-client/bin

step "init-envsubst"
"${ENGINE}" build -t "${ENVSUBST_IMAGE}" \
    -f "${HERE}/init-envsubst/Dockerfile" \
    "${HERE}/init-envsubst"

#--- Binary checks -----------------------------------------------------------
# Byte greps, so the host needs no binutils. In each binary:
#   jent_                         must be absent: AWS-LC's jitter entropy source
#                                 abort()s under Antithesis' deterministic clock
#   antithesis_load_libvoidstar   the coverage shim is linked in
#   __sancov_guards               the code is instrumented
#   .debug_line                   line tables for symbolization survived
step "Checking binaries"
tmp="$(mktemp -d)"
cids=()
cleanup() {
    for c in "${cids[@]}"; do "${ENGINE}" rm -f "${c}" >/dev/null 2>&1 || true; done
    rm -rf "${tmp}"
}
trap cleanup EXIT
check() {  # <image> <bin dir> <binary>...
    local image="$1" dir="$2" cid bin s
    shift 2
    # docker refuses to create a container from an image with no CMD (core-client has none);
    # the command is never run, the container only exists so its files can be copied out.
    cid="$("${ENGINE}" create "${image}" true)"
    cids+=("${cid}")
    for bin in "$@"; do
        "${ENGINE}" cp "${cid}:${dir}/${bin}" "${tmp}/${bin}"
        if grep -q -a -F 'jent_' "${tmp}/${bin}"; then
            echo "ERROR: ${bin} still contains jitter entropy code." >&2
            echo "       AWS_LC_SYS_NO_JITTER_ENTROPY=1 did not reach the cargo build." >&2
            exit 1
        fi
        for s in antithesis_load_libvoidstar __sancov_guards .debug_line; do
            if ! grep -q -a -F "${s}" "${tmp}/${bin}"; then
                echo "ERROR: ${bin} has no ${s}; see 'Binary checks' in build.sh." >&2
                exit 1
            fi
        done
        echo "  ok: ${bin}"
    done
}
check "${CORE_IMAGE}" /app/kms/core/service/bin kms-server kms-gen-keys kms-init
check "${CLIENT_IMAGE}" /app/kms-core-client/bin kms-core-client

mkdir -p "$(dirname "${TAG_FILE}")"
echo "${TAG}" >"${TAG_FILE}"

echo
echo "Built:"
for img in "${IMAGES[@]}"; do
    echo "  ${REG}/kms/${img}:${TAG}"
done
echo "Tag recorded in ${TAG_FILE}"
