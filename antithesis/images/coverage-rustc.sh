#!/bin/sh
# RUSTC_WRAPPER for coverage.Dockerfile: add the coverage flags only when rustc compiles one
# of the repo's crates (its manifest is under /app/kms-binaries) for the target (--target is
# on the command line; build scripts and proc macros are compiled for the host without it).
# Cargo calls it as: coverage-rustc <rustc> <args...>
case "${CARGO_MANIFEST_DIR:-}" in
/app/kms-binaries/*)
    case " $* " in
    *" --target "*) exec "$@" -C instrument-coverage -Cllvm-args=-runtime-counter-relocation ;;
    esac
    ;;
esac
exec "$@"
