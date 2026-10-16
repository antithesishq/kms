# Antithesis harness for Zama KMS

Everything Antithesis needs lives in this folder; the rest of the repo is unmodified.
Run everything from this folder (or `make -C antithesis <target>` from the repo root).

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
