#!/usr/bin/env bash
#=============================================================================
# Builds the four images the Antithesis manifests use, from the repo's own
# Dockerfiles, unmodified:
#
#   core-service        kms-server, kms-gen-keys, kms-init (insecure flavour)
#   core-service-probe  core-service plus grpc_health_probe, for the init Job
#   core-client         kms-core-client, which hosts the test commands
#   init-envsubst       the cores' config-rendering init container
#
#   antithesis/images/build.sh
#
# Zama's Dockerfiles start FROM images in Zama's private Chainguard org.
# --build-context redirects each of those to the public image of the same name,
# so the Dockerfiles need no edits. The AWS-LC jitter-entropy fix comes in
# through the golden image (golden.Dockerfile).
#
# Images are tagged with the registry names the manifests reference, so
# pushing them needs no retagging.
#
# Override any of: ENGINE (podman or docker), REG, TAG (see settings.sh).
#=============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KMS_SRC="$(cd "${HERE}/../.." && pwd)"
. "${HERE}/settings.sh"

# Intermediate images, never pushed. Fully qualified, so podman does not run
# short-name resolution on them.
ZAMA_GOLDEN_IMAGE="localhost/kms-antithesis/zama-golden:${TAG}"
GOLDEN_IMAGE="localhost/kms-antithesis/rust-golden:${TAG}"
BINARIES_IMAGE="localhost/kms-antithesis/kms-binaries:${TAG}"

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
step "kms-binaries (KMS_FLAVOR=insecure)"
"${ENGINE}" build -t "${BINARIES_IMAGE}" \
    -f "${KMS_SRC}/docker/kms-binaries/Dockerfile" \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    --build-arg KMS_FLAVOR=insecure \
    "${KMS_SRC}"

step "core-service (prod, EXPECTED_KMS_FLAVOR=insecure)"
"${ENGINE}" build -t "${CORE_IMAGE}" \
    -f "${KMS_SRC}/docker/core/service/Dockerfile" --target prod \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    --build-arg EXPECTED_KMS_FLAVOR=insecure \
    "${KMS_SRC}"

# The dev target is core-service plus grpc_health_probe, which the
# threshold-init Job uses to wait for all four cores.
step "core-service-probe (dev, with grpc_health_probe)"
"${ENGINE}" build -t "${PROBE_IMAGE}" \
    -f "${KMS_SRC}/docker/core/service/Dockerfile" --target dev \
    "${ZAMA_BASES[@]}" \
    --build-arg RUST_GOLDEN_IMAGE="${GOLDEN_IMAGE}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    "${KMS_SRC}"

step "core-client (prod, EXPECTED_KMS_FLAVOR=insecure)"
"${ENGINE}" build -t "${CLIENT_IMAGE}" \
    -f "${KMS_SRC}/docker/core-client/Dockerfile" --target prod \
    "${ZAMA_BASES[@]}" \
    --build-arg KMS_BINARIES_IMAGE="${BINARIES_IMAGE}" \
    --build-arg EXPECTED_KMS_FLAVOR=insecure \
    "${KMS_SRC}"

step "init-envsubst"
"${ENGINE}" build -t "${ENVSUBST_IMAGE}" \
    -f "${HERE}/init-envsubst/Dockerfile" \
    "${HERE}/init-envsubst"

#--- Jitter-entropy check ----------------------------------------------------
# kms-gen-keys and kms-server link AWS-LC. If its jitter entropy source was
# compiled in, they abort() under Antithesis' deterministic clock.
step "Checking core-service for AWS-LC jitter entropy"
tmp="$(mktemp -d)"
cid="$("${ENGINE}" create "${CORE_IMAGE}")"
trap '"${ENGINE}" rm -f "${cid}" >/dev/null 2>&1 || true; rm -rf "${tmp}"' EXIT
for bin in kms-gen-keys kms-server; do
    "${ENGINE}" cp "${cid}:/app/kms/core/service/bin/${bin}" "${tmp}/${bin}"
    n="$(grep -c -a 'jent_' "${tmp}/${bin}" || true)"
    if [[ "${n}" != "0" ]]; then
        echo "ERROR: ${bin} still contains jitter entropy code (${n} matches)." >&2
        echo "       AWS_LC_SYS_NO_JITTER_ENTROPY=1 did not reach the cargo build." >&2
        exit 1
    fi
    echo "  ok: ${bin}"
done

echo
echo "Built:"
for img in "${IMAGES[@]}"; do
    echo "  ${REG}/kms/${img}:${TAG}"
done
