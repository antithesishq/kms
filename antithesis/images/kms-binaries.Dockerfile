# syntax=docker/dockerfile:1
#=============================================================================
# Builds the KMS binaries with Antithesis coverage instrumentation:
# https://antithesis.com/docs/reference/sdk/rust/instrumentation/
#
# It writes the same /out layout as docker/kms-binaries/Dockerfile, so Zama's
# core-service and core-client Dockerfiles package these binaries unchanged.
# Differences from that file (diff against it when it changes):
#
#   - RUSTFLAGS add the coverage flags and --cfg antithesis. The cfg pulls the
#     antithesis-instrumentation shim into the observability crate
#     (observability/Cargo.toml). Every binary here uses that crate, directly
#     or through threshold-networking or kms_lib, so every binary links the
#     shim. A binary that does not fails to link with an undefined
#     __sanitizer_cov_trace_pc_guard.
#   - --target is explicit, so RUSTFLAGS reach only the target code and not
#     build scripts or proc macros. That puts the binaries under
#     target/x86_64-unknown-linux-gnu/.
#   - Profile release-lto-off: compile-time instrumentation does not survive
#     LTO.
#   - Line tables are kept and the binaries are not stripped, so Antithesis
#     can symbolize coverage (see symbols.Dockerfile).
#   - Insecure flavour only, and no sccache.
#=============================================================================
ARG RUST_GOLDEN_IMAGE
FROM ${RUST_GOLDEN_IMAGE} AS builder

WORKDIR /app/kms-binaries

COPY Cargo.toml Cargo.lock rust-toolchain.toml ./
COPY backward-compatibility ./backward-compatibility
COPY bc2wrap ./bc2wrap
COPY core ./core
COPY core-client ./core-client
COPY observability ./observability
COPY tools ./tools

RUN mkdir -p /out/core-service/bin /out/core-client/bin

RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    cargo fetch --locked

# Replaces the golden image's RUSTFLAGS, so its -crt-static is repeated here.
# -Cstrip=none overrides the strip=debuginfo that cargo defaults to for
# release profiles without debug info.
# The docs also list -Cllvm-args=-sanitizer-coverage-pc-table. It makes every
# object call __sanitizer_cov_pcs_init, which antithesis-instrumentation 0.1.0
# does not define, so the link fails. It is left out.
ENV RUSTFLAGS="-C target-feature=-crt-static \
    -Ccodegen-units=1 \
    -Cpasses=sancov-module \
    -Cllvm-args=-sanitizer-coverage-level=3 \
    -Cllvm-args=-sanitizer-coverage-trace-pc-guard \
    -Clink-args=-Wl,--build-id \
    -Cdebuginfo=line-tables-only \
    -Cstrip=none \
    --cfg antithesis"

# The antithesis-instrumentation build script fetches a header from GitHub, so
# this step needs network access.
RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    --mount=type=cache,id=kms-antithesis-target,target=/app/kms-binaries/target,sharing=locked \
    set -eu && \
    cargo build --locked --profile=release-lto-off --target x86_64-unknown-linux-gnu \
        -p kms --bin kms-server --bin kms-gen-tls-certs --bin kms-init --bin kms-custodian --bin kms-gen-keys \
        -p kms-core-client --bin kms-core-client \
        -p kms-health-check --bin kms-health-check \
        --features insecure && \
    cd target/x86_64-unknown-linux-gnu/release-lto-off && \
    cp kms-server kms-gen-tls-certs kms-init kms-gen-keys kms-custodian /out/core-service/bin/ && \
    cp kms-core-client kms-health-check kms-custodian /out/core-client/bin/ && \
    echo insecure > /out/kms-build-flavor

FROM scratch AS binaries

COPY --from=builder /out /out
