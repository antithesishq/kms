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
| `build` | Builds the four images into podman, tagged with the git commit |
| `push` | Pushes the last build to the Antithesis registry |
| `config` | Renders `config/` into `build/config/` with the tag of the last build |
| `driver` | Regenerates `config/manifests/41-kms-workload-tests.yaml` and the client pod's test mounts from `test/v1/main/` |
| `k3s` | Starts local k3s |
| `load` | Imports the images the manifests use into k3s (runs `config` first) |
| `up` / `down` | Deploys / deletes the manifests on k3s (`up` runs `config` first) |
| `test` | Runs the test commands in the client pod (first keygen, every driver, recovery check) and writes `local/out/check/` |
| `build-coverage` | Builds the local-only coverage variant of core-service (`<tag>-coverage`, never pushed) for `local/run-local.sh` |

## Image tags

`make build` tags the images with the short git commit, for example `0688205e`.
If the tree has uncommitted changes, the tag gets a `-dirty-<yyyymmdd-hhmm>` suffix, so two such builds of one commit do not share a tag.
The build records the tag in `build/tag`, and `push`, `config` and `load` use that tag.
Set `TAG=...` to override it for any target.

The manifests in `config/manifests/` reference our images as `.../kms/<name>:@KMS_TAG@`.
`make config` fills in the tag and writes the result to `build/config/`, which is not committed.
Launch and deploy from `build/config/`, never from `config/`.

Each build adds a new tag, so old images stay in podman and in k3s until you remove them.

## Flow

Antithesis:

```
make build push config
```

then launch.

Local:

```
make k3s                      # once
make build load up test
make down
```

Local coverage run (no faults; see `scratchbook/coverage-setup.md`):

```
make build build-coverage     # after a SUT change
local/run-local.sh <label> [seed]
```

It redeploys from scratch with the coverage build, runs the drivers for 8 minutes the way
Test Composer would, and writes `local/out/<label>/coverage.lcov`. Run it with the `ENGINE`
the images were built with (e.g. `ENGINE=docker`): it converts the profiles in the coverage
tools image, which only that engine has.

## Launch

From this folder, after `make push config` (and `make driver` before `config` if test scripts changed):

snouty does not push the KMS images; `make push` does. Without it the run fails at setup
with "could not resolve to a reachable image".

```
snouty validate build/config
snouty launch --webhook advanced_k8s_test --config build/config \
  --source kms --test-name kms/antithesis-poc-coverage \
  --description "<what changed>" --duration 60 \
  --param 'custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-' \
  --param 'custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-' \
  --param custom.vm_memory_mb=16384 \
  --param antithesis.performance_tier=turbo
```

The exclusions keep pod stop and kill faults off the test driver and MinIO. 16 GiB of test
VM memory avoids the "Peak memory usage" alert that the default VM size gave.
Runs use the `turbo` performance tier; edge counts are comparable only between runs of the same tier.

## After editing

| You edited | Local | Antithesis |
|---|---|---|
| SUT code or `images/` | `make build load down up test` | `make build push config`, launch |
| `test/v1/main/` scripts | `make driver down up test` (or the fast path below) | `make driver config`, launch |
| `config/manifests/` | `make down up test` | `make config`, launch |

Fast path for test scripts, without redeploying the cores:

```
make driver
kubectl apply -f config/manifests/41-kms-workload-tests.yaml
kubectl delete pod -n kms-threshold-staging kms-core-client-0
make test
```
