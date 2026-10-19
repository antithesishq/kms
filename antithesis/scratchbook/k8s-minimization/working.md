# K8s Minimization Working File

> **Provenance.** The manifests in `config/manifests/` were rendered and minimized by hand before
> this file existed. Their header comments point here, but the original working file and the Helm
> render inputs they cite (`values/overrides.yaml`, `values/peers.yaml`) are not in this tree. This
> file was reconstructed on 2026-10-15 by the `antithesis-setup-k8s` skill from:
> - the manifests themselves;
> - `Antithesis_RUN/README.md` and `charts/kms-core/`;
> - the research scratchbook;
> - Antithesis run `95ddada30b89e65eb8212a702642ce0c-63-12`.
>
> Because the render inputs are missing, **edit the manifests directly**. A fresh `helm template`
> cannot reproduce them from this tree.

## Application Overview

Zama KMS stores FHE key material and runs key generation, CRS generation, decryption, and
resharing. This deployment is a **4-party threshold cluster (n = 4, t = 1)**, built with the
**insecure** feature and the **mock enclave**, using `Test` FHE parameters and `NoiseFloodSmall`
decryption.

- Each party is one `kms-server` pod. It exposes the service gRPC API on `:50100` (no auth) and
  the core-to-core MPC mesh on `:50001` (mTLS; each node issues its own certificates from an
  onboard CA via `[threshold.tls.auto]`).
- Public and private key material lives in S3. MinIO stands in for AWS S3 here.

See `../sut-analysis.md` for the full analysis.

## Horizontal classification

### Component classification

- **kms-core-1..4** (`31..34-kms-core-N.yaml`): SUT
  - Status: Confirmed
  - Reasoning: these are the threshold MPC parties under test. Four is the smallest n with
    t = 1 (n > 3t).
- **minio** (`10-minio.yaml`): Dependency-real
  - Status: Confirmed
  - Reasoning: it replaces AWS S3 for the public and private vaults. The cores cannot boot
    without it, and the client reads public keys from it. The decryption-correctness property
    depends on the cores reading key material from it. The cloud service is replaced by a local
    equivalent rather than stubbed.
- **minio-provision** Job (`11-minio-provision-job.yaml`): Dependency-real (bootstrap)
  - Status: Confirmed
  - Reasoning: creates the buckets and the access key. It makes `kms-public` anonymously readable,
    which the cores' init container needs to fetch peer CA certificates.
- **kms-prepopulate-keys** Job (`20-kms-prepopulate-keys-job.yaml`): Dependency-real (bootstrap)
  - Status: Confirmed
  - Reasoning: runs `kms-gen-keys` for all 4 parties before any core starts. This breaks the
    chart's cold-start cycle, in which every core waits for peer CA certs that no core has
    written yet. See `Antithesis_RUN/README.md`, "Why the keys are pre-populated".
- **kms-core-init-threshold-init** Job (`40-kms-core-init.yaml`): Dependency-real (bootstrap)
  - Status: Confirmed
  - Reasoning: runs `kms-init` once all 4 cores pass the gRPC health check. This creates the
    default MPC context and epoch, and nothing can decrypt until it has run.
- **kms-core-client** StatefulSet (`40-kms-core-init.yaml`): client (workload host)
  - Status: Confirmed
  - Reasoning: an idle pod with the `kms-core-client` CLI and a rendered `config.toml`
    (`num_majority = 2`, `num_reconstruct = 3`). `antithesis-workload` will add the test
    template here.
- **FHEVM KMS connector, gateway, host chain**: Out-of-scope
  - Status: Confirmed (user, 2026-10-15)
  - Reasoning: these are production callers of the service API. The workload's client plays the
    connector's role.
- **AWS KMS keychain, custodian backup, Nitro Enclaves (real)**: Out-of-scope
  - Status: Confirmed
  - Reasoning: there is no backup vault or AWS KMS configured, and the enclave is mocked
    (`mock_enclave = true`, `trusted_releases = []`).
- **Chart's `kmsGenCertAndKeys` pre-install hook and `kms-gen-tls-certs`**: Out-of-scope
  - Status: Confirmed
  - Reasoning: replaced by `kms-prepopulate-keys`. The hook's non-AWS branch needs
    `amazon/aws-cli` and is obsolete under automatic TLS.
- **OTLP collector / Prometheus / Grafana** (`docker-compose-telemetry.yml`, `observability/`): Out-of-scope
  - Status: Defaulted
  - Reasoning: observability. With no OTLP endpoint, the cores fall back to a stdout exporter,
    which is visible in Antithesis logs.

### Call graph (from manifests)

High confidence (direct evidence):

- `kms-core-N` → `minio:9000`: `aws.toml` `s3_endpoint`, `AWS_ENDPOINT_URL_S3`, and init-container
  `curl` calls for peer CA certs.
- `kms-core-N` ↔ `kms-core-M-core-M:50001`: `[[threshold.peers]]` in each core's `kms-server.toml`.
- `kms-core-init-threshold-init` → `kms-core-N-core-N:50100`: the `grpc_health_probe` gate,
  then `kms-init --addresses`.
- `kms-core-client` → `kms-core-N-core-N:50100` and `minio:9000/kms-public`: its `config.toml`.
- `minio-provision`, `kms-prepopulate-keys` → `minio:9000`.

Not inferable from manifests: asked the user. There are no other interactions; see below.

### Reverse dependencies (descriptive)

- **FHEVM KMS connector** (production only)
  - Triggers the SUT via gRPC to `:50100`. It runs `PublicDecrypt`/`UserDecrypt` (plus the
    `*Sync` variants), `KeyGen`/`KeyGenPreproc`, `CrsGen`, and `NewMpcEpoch` in response to
    gateway contract events.
  - Payload shape: request ID (assigned by the gateway contract), key ID, context and epoch IDs,
    EIP-712 domain, and ciphertexts with external handles. On retry the connector resends an
    identical payload under the same request ID (`ai-docs/ARCHITECTURE.md:50-52`).
  - Status: Confirmed (from ARCHITECTURE.md; the connector is not in this repo).
- **kms-init** (post-deploy, once)
  - Triggers the SUT by creating the default MPC context and epoch on every party.
  - Status: Confirmed (from the `kms-core-init-threshold-init` Job spec).

### Open questions & answers

- Q: Start from scratch or continue from a past iteration?
  A: Continue. The user said the manual setup in `antithesis/` already exists
  and should not be repeated (2026-10-15).
- Q: Are there interactions not visible in the manifests, such as async messaging, scheduled
  jobs, shared databases or caches, or services behind a shared gateway?
  A: No, the manifests are complete (user, 2026-10-15).

## Component inventory

### kms-core-N, N = 1..4 (StatefulSet, one per party)

**Scope**: SUT
**Status**: Confirmed

**Image**: `us-central1-docker.pkg.dev/molten-verve-216720/zama-repository/kms/core-service:local`
(private, Antithesis registry). The init container uses `.../kms/init-envsubst:local`. Pull
policy is `Never`.

**Replicas**: 1 per party in production (one StatefulSet per party) → 1. StatefulSet
`ordinals.start: N` pins party N to pod `kms-core-N-core-N`. That name doubles as the MPC
identity, the TLS subject, and the per-pod Service name.

**Env vars**:
- `KMS_CORE__THRESHOLD__MY_ID`: `N`
- `RUN_MODE`: `dev`; `RUST_LOG`: `info`; `NO_COLOR`: `true`
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`: the MinIO access key that `minio-provision`
  creates
- `AWS_ENDPOINT_URL_S3`: `http://minio:9000`
- `KMS_CORE__{PUBLIC,PRIVATE}_VAULT__STORAGE__S3__{BUCKET,PREFIX}`: `kms-public`/`PUB-pN`,
  `kms-private`/`PRIV-pN`
- `KMS_CA_PEM_1..4`: fetched from MinIO by the init container and substituted into
  `kms-server.toml`

**Volume mounts**:
- `/var/lib/kms-core/config` ← ConfigMap `kms-core-N-core-config` (`kms-server.toml`,
  `aws.toml`, `vaults.toml`, `kms-gen-keys.toml`)
- `/root` ← emptyDir `workdir` (the rendered config, shared between the init containers and the
  core)

**Init containers**: `kms-core-init-load-env` (curls peer CAs from MinIO and runs `envsubst`
on the configs), `kms-core-init-gen-keys` (`kms-gen-keys`; a no-op when the keys already exist)

**Probes**: gRPC `readiness` (period 5s, failureThreshold 30), `startup` (period 10s,
failureThreshold 60), and `liveness` (failureThreshold 10, timeout 5s, so about 100s before a
restart). The liveness thresholds are conservative, as the Antithesis best practices advise.

**Resources**: requests 100m CPU / 2Gi; limits 8Gi memory and 1Gi ephemeral storage.
`[internal_config] num_rayon_threads = 8`, `num_tokio_threads = 2`.

**Sidecars (kept)**: none
**Sidecars (dropped)**: none present

**Dependencies in**: kms-core-client, kms-core-init-threshold-init, and the other 3 cores
(`:50001`)
**Dependencies out**: minio, and the other 3 cores (`:50001`)

**Decisions applied** (all before this skill ran, per the manifest header comments):
- Kept: one StatefulSet, two Services (headless and per-pod), and one ConfigMap per party.
- Simplified: images repointed at the Antithesis registry; `imagePullPolicy: Never`.
- Dropped: the dangling `registry-credentials` imagePullSecret and the null
  `serviceAccountName`.
- Replaced: Helm hook annotations replaced by kapp `change-group`/`change-rule` ordering
  (`upsert after upserting keys-ready`). The chart patch selects `[threshold.tls.auto]` under
  `mockEnclave` and emits `trusted_releases = []`.

### minio (Deployment + Service + PVC)

**Scope**: Dependency-real
**Status**: Confirmed

**Image**: `docker.io/scnd/minio-mirror:RELEASE.2025-09-07T16-13-09Z`. This is a public,
**third-party mirror** of the MinIO community image. Pull policy is `Never`.

**Replicas**: none in production (AWS S3 is used there) → 1

**Env vars**: `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`, both the placeholder `minioadmin`.

**Volume mounts**: `/data` ← PVC `minio-data` (5Gi, RWO, default storage class, i.e.
`local-path`)

**Resources**: requests 50m CPU / 256Mi; memory limit 1Gi. **Added by this skill.**

**Dependencies in**: cores, kms-core-client, minio-provision, kms-prepopulate-keys
**Dependencies out**: none

**Decisions applied**:
- Replaced: AWS S3 → MinIO (earlier work).
- Simplified: `hostPath /var/lib/kms-minio-data` → PVC. The PVC is torn down with the namespace
  and survives pod restarts, so a MinIO restart behaves like a recoverable S3 outage (earlier
  work).
- Dropped: console port 9001 (earlier work).
- Added: resource requests and a memory limit (this skill, 2026-10-15). MinIO was the only
  long-running container with none, and the K8s best practices ask for requests on all of them.

### minio-provision (Job)

**Scope**: Dependency-real (bootstrap). **Status**: Confirmed.
**Image**: `docker.io/scnd/mc-mirror:RELEASE.2025-02-04T04-57-50Z`. This is a public,
third-party mirror. Pull policy is `Never`.
**What it does**: waits for MinIO to accept writes, creates `kms-public` and `kms-private`,
adds the `kms-access-key-id` user with the `readwrite` policy, and makes `kms-public`
anonymously readable. It sets `HOME=/tmp` because `mc` must write its config.
**Ordering**: kapp `upsert after upserting minio`.

### kms-prepopulate-keys (Job)

**Scope**: Dependency-real (bootstrap). **Status**: Confirmed.
**Image**: `.../kms/core-service:local`. Pull policy is `Never`.
**What it does**: runs `kms-gen-keys` for parties 1–4 against MinIO and prints
`PREPOPULATE_DONE`.
**Ordering**: kapp `upsert after upserting minio-ready`. The cores are `after keys-ready`.

### kms-core-init-threshold-init (Job) and kms-core-client (StatefulSet + ConfigMap)

**Scope**: Dependency-real (bootstrap), and the client. **Status**: Confirmed.
**Images**: `.../kms/core-service-probe:local` (the health-gate init container),
`.../kms/core-service:local` (`kms-init`), and `.../kms/core-client:local`. Pull policy is
`Never` throughout.
**Client resources**: requests 100m CPU / 1Gi; limits 2 CPU / 4Gi.
**Decisions applied** (earlier work): the duplicate `imagePullPolicy` key that the chart emits
was collapsed. The init Job gates itself on `grpc_health_probe` against all 4 cores, and kapp
orders it `after kms-core`.

## Resource budget (steady state, after the Jobs complete)

| Pods | CPU request | Memory request |
|---|---|---|
| kms-core-1..4 | 4 × 100m = 400m | 4 × 2Gi = 8Gi |
| kms-core-client | 100m | 1Gi |
| minio | 50m | 256Mi |
| **Total** | **550m** (< 1000m) | **9.25Gi** (< 10Gi) |

The three Jobs and every init container set no requests. They finish before testing starts.
Memory limits are not summed by the policy, but the cores' 8Gi limits allow 32Gi in total, so
memory pressure would show up as OOM kills rather than scheduling failures. Headroom against
the 10Gi cap is 0.75Gi. Adding any long-running pod (for example a separate workload pod) needs
a budget check.

## Apply-findings log

| Date | Change | Files |
|---|---|---|
| 2026-10-15 | MinIO: added `resources.requests` (50m / 256Mi) and `limits.memory` (1Gi) | `10-minio.yaml` |
| 2026-10-16 | Workload: the `kms-workload-tests` ConfigMap holds the `public_decrypt` test template. The client StatefulSet mounts each script with `subPath` at `/opt/antithesis/test/v1/public_decrypt/`. The core-client image is unchanged. No new pods, so the resource budget is unchanged. | `41-kms-workload-tests.yaml` (generated by `antithesis/test/render-configmap.sh`), `40-kms-core-init.yaml` |
| 2026-10-16 | Workload: added `anytime_reshare_key.sh` (key reshare into new epochs) with its own `subPath` mount. `render-configmap.sh` takes every `*.sh` in the template, so a new script needs only its mount. No new pods. | `41-kms-workload-tests.yaml`, `40-kms-core-init.yaml` |
| 2026-10-17 | Workload: the test commands are Python scripts that use the Antithesis Python SDK. `render-configmap.sh` takes every `*.py`, and the `subPath` mounts name the `.py` files. The core-client image gets Python and the SDK from `antithesis/images/client.Dockerfile`. No new pods. | `41-kms-workload-tests.yaml`, `40-kms-core-init.yaml` |

Nothing else changed. Every other decision above predates this skill and was left as is.

## Validation log

### `snouty validate` (static, k8s-validator): **blocked in this environment**

`snouty validate config` exits 125 because the k8s-validator runs as a container, and this
sandbox has no working container engine. There is no Docker. The Podman in the Nix store fails
with `no such file or directory`: it has no `/etc/containers`, no subuid/subgid mapping, and the
user has no name. The validator could not run.

**Run it on a machine with Docker or Podman** before the next launch:
`snouty validate sut/kms/antithesis/config`. Then fix any DENY results here.

Manual static checks done instead (2026-10-15):
- 25 objects: 1 Namespace, 1 PVC, 1 Deployment, 5 StatefulSets, 3 Jobs, 9 Services,
  5 ConfigMaps.
- Every namespaced object is in `kms-threshold-staging`, and the Namespace object is included.
- 18 out of 18 `imagePullPolicy: Never`. All images are fully qualified with explicit tags; none
  are `:latest`.
- No `hostPath` (only in a comment), no `LoadBalancer`/`NodePort` Services, no `privileged`,
  no RWX PVCs, no hardcoded IPs, no anti-affinity or topology spread.
- Readiness probes on every long-running pod except `kms-core-client`, which is an idle shell.
  kapp treats a running pod as ready.
- Requests total 550m / 9.25Gi (see the budget above).

### Local deploy (k3s): **skipped**

This sandbox has no `kubectl`, `k3s`, `kapp`, or container engine, so local validation could not
run. That is recorded here, not glossed over.

Substitute evidence: Antithesis run `95ddada30b89e65eb8212a702642ce0c-63-12` (2026-10-14,
"Basic k8s Test", status completed).
- kapp applied 25 resources whose names match these manifests, and all four core StatefulSets
  reconciled to ready.
- `kms-prepopulate-keys` printed `PREPOPULATE_DONE`, and `kms-init` started against 4 peers.
- The fault injector started, which only happens after kapp reports success (no custom
  `setup_complete` is emitted), so every Job, `kms-init` included, completed.
- No unexpected container exits or crashes.
- The failing properties were instrumentation-only: no coverage instrumentation or symbols, and
  thread pausing was off. That is expected with no SDK or instrumentation yet.

The MinIO request change postdates that run.

## Open items

- **Restart orphans the epoch?** `Antithesis_RUN/README.md:113-115` says a restarted party ends
  up with an empty epoch list, and only the out-of-band deploy script repairs it. Antithesis node
  faults restart core pods, so if this is true, every killed core stays unable to decrypt for
  the rest of the timeline. The claim has not been verified. It belongs to `antithesis-workload`
  and the research scratchbook, which already track it.
- **Mutable `:local` tags.** All 4 private images use `:local`, and the push script re-pushes the
  same tag (plus a dated one). The best practices prefer digests. Pin them once the images stop
  changing, so that runs are reproducible.
- **MinIO update check.** In the run, MinIO tried to resolve `dl.min.io`. This was harmless (DNS
  timeouts in the CoreDNS logs) but shows an internet lookup.
- **Third-party images.** `scnd/minio-mirror` and `scnd/mc-mirror` are community mirrors, not
  official MinIO images. The customer may want official or vendored copies.
- **Cosmetic.** `20-kms-prepopulate-keys-job.yaml` begins with five empty `---` documents. kapp
  accepted them.
- ~~**Test template.**~~ Resolved (2026-10-16). The `public_decrypt` template reaches the client
  pod from a ConfigMap (see the apply-findings log), not from the image. Run
  `44e6ae0423fb98e579484310cf731b28-64-4` ran the drivers from that path, so Antithesis finds
  commands that a ConfigMap mounts. The local k3s cluster from `deploy-threshold-k3s.sh` is
  different: it deploys the Helm chart, not `config/manifests/`, so its client pod has no test
  template until `40` and `41` are applied over it.
