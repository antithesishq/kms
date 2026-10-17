# Antithesis harness for Zama KMS

Everything Antithesis needs lives in this folder, apart from the coverage instrumentation hook.
Run everything from this folder (or `make -C antithesis <target>` from the repo root).

## Coverage instrumentation

The KMS binaries use the [Rust instrumentation method](https://antithesis.com/docs/reference/sdk/rust/instrumentation/).
It needs these edits outside this folder, which are all inactive unless `--cfg antithesis` is set:

| File | Edit |
|---|---|
| `Cargo.toml`, `Cargo.lock` | `antithesis-instrumentation` dependency |
| `observability/Cargo.toml` | Pull it in only under `cfg(antithesis)`, and declare that cfg |
| `observability/src/lib.rs` | `use antithesis_instrumentation as _;` under `#[cfg(antithesis)]` |

The shim sits in `observability` because every KMS binary uses that crate, so every binary links the shim.

`images/kms-binaries.Dockerfile` builds the binaries with the coverage flags, `--cfg antithesis` and no LTO.
It leaves out the docs' `-sanitizer-coverage-pc-table` flag, because the shim (0.1.0) does not define `__sanitizer_cov_pcs_init`, which that flag needs at link time.
It replaces `docker/kms-binaries/Dockerfile`; diff against that file when it changes.
`images/symbols.Dockerfile` adds a `/symbols` layer to the core-service, core-service-probe and core-client images.
`make build` checks that the binaries contain the shim, the coverage sections and line tables.
The build needs network access, because the shim's build script downloads a header from GitHub.

In a run, the triage report's Setup group shows whether this worked:
"Software was instrumented" and "Every instrumented module has symbols" should both pass.

| Target | Does |
|---|---|
| `build` | Builds the four images into podman |
| `push` | Pushes them to the Antithesis registry as `:local` |
| `driver` | Regenerates `config/manifests/41-kms-workload-tests.yaml` from `test/v1/` |
| `k3s` | Starts local k3s |
| `load` | Imports the images the manifests use into k3s |
| `up` / `down` | Deploys / deletes the manifests on k3s |
| `test` | Runs the test commands in the client pod: keygen, driver, reshare, driver |

## Flow

Antithesis:

```
make build push
```

then launch.

Local:

```
make k3s                      # once
make build load up test
make down
```

## Launch

From this folder, after `make push` (and `make driver` if test scripts changed):

```
snouty validate config
snouty launch -w basic_k8s_test --config config \
  --test-name kms-threshold \
  --description "public_decrypt workload" \
  --duration 30
```

## After editing

| You edited | Local | Antithesis |
|---|---|---|
| SUT code or `images/` | `make build load down up test` | `make build push`, launch |
| `test/v1/` scripts | `make driver down up test` (or the fast path below) | `make driver`, launch |
| `config/manifests/` | `make down up test` | launch |

Fast path for test scripts, without redeploying the cores:

```
make driver
kubectl apply -f config/manifests/41-kms-workload-tests.yaml
kubectl delete pod -n kms-threshold-staging kms-core-client-0
make test
```
