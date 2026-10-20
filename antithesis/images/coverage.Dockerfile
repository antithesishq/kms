#=============================================================================
# Local-only coverage build of kms-server, for measuring the workload without
# an Antithesis run (antithesis/local/run-local.sh). Antithesis runs never use
# it: they use the sancov-instrumented build of kms-binaries.Dockerfile.
#
#   tools   the Rust builder plus llvm-tools and rustfilt, with the coverage
#           build of kms-server at /out/kms-server. run-local.sh converts the
#           cores' profiles to LCOV in it, against that exact binary.
#   (last)  CORE_IMAGE with its kms-server replaced by the coverage build.
#
# The build uses LLVM source-based coverage (-C instrument-coverage). Runtime
# counter relocation lets LLVM_PROFILE_FILE use continuous mode (%c), so the
# counters reach the profile file while the server runs, not only at a clean
# exit. No --cfg antithesis: that only links the Antithesis coverage shim.
#=============================================================================
ARG RUST_GOLDEN_IMAGE
ARG CORE_IMAGE

FROM ${RUST_GOLDEN_IMAGE} AS tools

WORKDIR /app/kms-binaries

# The component goes to the toolchain that rust-toolchain.toml pins.
COPY rust-toolchain.toml ./
RUN rustup component add llvm-tools && cargo install --locked rustfilt

COPY Cargo.toml Cargo.lock ./
COPY backward-compatibility ./backward-compatibility
COPY bc2wrap ./bc2wrap
COPY core ./core
COPY core-client ./core-client
COPY observability ./observability
COPY tools ./tools

RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    cargo fetch --locked

ENV RUSTFLAGS="-C target-feature=-crt-static \
    -Cdebuginfo=line-tables-only \
    -Cstrip=none"

# Coverage counters only in the repo's own crates, compiled for the target (not their build
# scripts or proc macros). With every crate instrumented, the dependencies' multithreaded
# crypto loops (tfhe, tfhe-zk-pok) ran ~100x slower: an insecure CRS took minutes instead of
# 4 s and starved every other driver. Their coverage is dropped by normalize --repo anyway.
COPY antithesis/images/coverage-rustc.sh /usr/local/bin/coverage-rustc
ENV RUSTC_WRAPPER=/usr/local/bin/coverage-rustc

# Its own target cache, so it doesn't evict the Antithesis build's.
RUN --mount=type=cache,target=/root/.cargo/registry,sharing=locked \
    --mount=type=cache,id=kms-coverage-target-ws,target=/app/kms-binaries/target,sharing=locked \
    set -eu && \
    cargo build --locked --profile=release-lto-off --target x86_64-unknown-linux-gnu \
        -p kms --bin kms-server --features insecure && \
    mkdir -p /out && \
    cp target/x86_64-unknown-linux-gnu/release-lto-off/kms-server /out/kms-server && \
    ln -s "$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-profdata" /usr/local/bin/ && \
    ln -s "$(rustc --print sysroot)/lib/rustlib/x86_64-unknown-linux-gnu/bin/llvm-cov" /usr/local/bin/

FROM ${CORE_IMAGE}
COPY --from=tools /out/kms-server /app/kms/core/service/bin/kms-server
