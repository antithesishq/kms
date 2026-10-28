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
| `driver` | Regenerates `config/manifests/41-kms-workload-tests.yaml` from `test/v1/` |
| `k3s` | Starts local k3s |
| `load` | Imports the images the manifests use into k3s (runs `config` first) |
| `up` / `down` | Deploys / deletes the manifests on k3s (`up` runs `config` first) |
| `test` | Runs the test commands in the client pod: keygen, driver, reshare, driver |

## Image tags

`make build` tags the images with the short git commit, for example `0688205e`.
If the tree has uncommitted changes, the tag gets a `-dirty-<yyyymmdd-hhmm>` suffix, so two such builds of one commit do not share a tag.
The build records the tag in `build/tag`, and `push`, `config` and `load` use that tag.
Set `TAG=...` to override it for any target.

The manifests in `config/manifests/` reference our images as `.../kms/<name>:@KMS_TAG@`.
`make config` fills in the tag and writes the result to `build/config/`, which is not committed.
Launch and deploy from `build/config/`, never from `config/`.

Each build adds a new tag, so old images stay in podman and in k3s until you remove them.

## Test commands

The test template `test/v1/public_decrypt/` holds Python scripts that use the [Antithesis Python SDK](https://antithesis.com/docs/reference/sdk/python/).
`images/client.Dockerfile` installs Python and the SDK in the core-client image.
The scripts reach the client pod from the ConfigMap in `config/manifests/41-kms-workload-tests.yaml`, not from the image, so a script edit needs no image build.
Antithesis catalogs assertions only in Python files that are part of an image.
So each command declares the catalog itself at startup (`declare_catalog` in `helper_lib.py`).
That scan finds only SDK assertion calls with a string literal as the message, so do not put messages in variables.

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

## Launch

From this folder, after `make push config` (and `make driver` before `config` if test scripts changed):

```
snouty validate build/config
snouty launch -w basic_k8s_test --config build/config \
  --test-name kms-threshold \
  --description "public_decrypt workload" \
  --duration 30
```

## After editing

| You edited | Local | Antithesis |
|---|---|---|
| SUT code or `images/` | `make build load down up test` | `make build push config`, launch |
| `test/v1/` scripts | `make driver down up test` (or the fast path below) | `make driver config`, launch |
| `config/manifests/` | `make down up test` | `make config`, launch |

Fast path for test scripts, without redeploying the cores:

```
make driver
kubectl apply -f config/manifests/41-kms-workload-tests.yaml
kubectl delete pod -n kms-threshold-staging kms-core-client-0
make test
```

## VSS harness

`vss-harness/` is a second, separate workload. It runs the VSS protocol with all parties in one process and up to t fuzzed liars.
`feature-workloads/vss/analysis.md` lists its decision points, properties and findings.
It needs two edits outside this folder: the `vss_observer` feature of `threshold-execution`, and the liar in `malicious_execution/large_execution/fuzzed_vss.rs`.

| Target | Does |
|---|---|
| `vss-build` | Builds the instrumented `vss-harness` image, tagged like `build`, and records the tag in `build/vss-tag` |
| `vss-push` | Pushes that image to the Antithesis registry |
| `vss-config` | Renders `config-vss/` into `build/config-vss/` with that tag |

Run it locally without Antithesis:

```
VSS_ITERATIONS=40 VSS_SEED=7 cargo run -p kms-antithesis-vss
```

The run prints the reach claims that were not reached and the property violations, and exits non-zero on a violation.

Launch it from this folder, after `make vss-build vss-push vss-config`.
`snouty launch` pushes only the config image, so the harness image must be in the registry first:

```
snouty launch -w basic_k8s_test --config build/config-vss \
  --test-name kms-vss --description "VSS harness" --duration 30 \
  --param custom.pause_fault_injector=true
```
