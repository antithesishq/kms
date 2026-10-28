# syntax=docker/dockerfile:1
#=============================================================================
# Builds the VSS harness (antithesis/vss-harness) with Antithesis coverage
# instrumentation, on the same golden image and RUSTFLAGS as
# kms-binaries.Dockerfile, which explains each flag.
#
# The harness reaches the coverage shim through threshold-networking, which
# depends on the observability crate. build-vss.sh checks that the binary
# contains the shim.
#
# The image runs the harness as its entrypoint and has /symbols, so Antithesis
# can symbolize coverage.
#=============================================================================
ARG RUST_GOLDEN_IMAGE
FROM ${RUST_GOLDEN_IMAGE} AS builder

WORKDIR /app/kms

COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY backward-compatibility ./backward-compatibility
COPY bc2wrap ./bc2wrap
COPY core ./core
COPY core-client ./core-client
COPY observability ./observability
COPY tools ./tools
COPY antithesis/vss-harness ./antithesis/vss-harness

RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    cargo fetch --locked

ENV RUSTFLAGS="-C target-feature=-crt-static \
    -Ccodegen-units=1 \
    -Cpasses=sancov-module \
    -Cllvm-args=-sanitizer-coverage-level=3 \
    -Cllvm-args=-sanitizer-coverage-trace-pc-guard \
    -Clink-args=-Wl,--build-id \
    -Cdebuginfo=line-tables-only \
    -Cstrip=none \
    --cfg antithesis"

RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    --mount=type=cache,id=kms-antithesis-vss-target,target=/app/kms/target,sharing=locked \
    set -eu && \
    cargo build --locked --profile=release-lto-off --target x86_64-unknown-linux-gnu \
        -p kms-antithesis-vss --bin vss-harness && \
    mkdir -p /out && \
    cp target/x86_64-unknown-linux-gnu/release-lto-off/vss-harness /out/

# The -dev variant has a shell, for the /symbols link and for debugging in a run.
FROM cgr.dev/chainguard/glibc-dynamic:latest-dev

COPY --from=builder /out/vss-harness /usr/local/bin/vss-harness
USER root
RUN mkdir /symbols && ln -s /usr/local/bin/vss-harness /symbols/vss-harness
USER nonroot
ENTRYPOINT ["/usr/local/bin/vss-harness"]
