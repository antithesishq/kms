---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: /home/exedev/kms/advanced_k8s_test.md
    why: launcher fault types, exclusion-pattern syntax, quiet windows
---

# Deployment Topology

## Summary

The Kubernetes topology in [antithesis/config/manifests/](../config/manifests/) already exists and
is adopted unchanged: four SUT pods, MinIO, and one client pod, plus three one-shot Jobs. It's
launched with the `advanced_k8s_test` webhook. `make config` renders the manifests into
`antithesis/build/config/` with the image tag of the last build (`speedrun-<sha>` in this
speedrun); launches use that rendered copy ([README](../README.md)). Setup decisions and
validation notes are in [k8s-minimization/working.md](k8s-minimization/working.md).

```text
                      +-----------------------------+
                      | kms-core-client-0 (workload)|
                      | kms-core-client CLI + tests |
                      +--------------+--------------+
                        service gRPC | :50100 (all 4)       HTTP reads of kms-public
          +----------------+---------+------+----------------+         |
          v                v                v                v         |
   +-------------+  +-------------+  +-------------+  +-------------+  |
   |kms-core-1-  |<>|kms-core-2-  |<>|kms-core-3-  |<>|kms-core-4-  |  |
   |  core-1     |  |  core-2     |  |  core-3     |  |  core-4     |  |
   +------+------+  +------+------+  +------+------+  +------+------+  |
          |   core-to-core mTLS :50001 (full mesh)           |         |
          +----------------+----------------+----------------+         |
                           v                                           v
                    +---------------------------------------------------+
                    | minio  (kms-public / kms-private, PUB-pX/PRIV-pX) |
                    +---------------------------------------------------+
   one-shot Jobs: minio-provision, kms-prepopulate-keys, kms-core-init-threshold-init
```

## Components

| Manifest | Pod name | Role | Image | Runs | Replicas |
|---|---|---|---|---|---|
| `10-minio.yaml` | `minio-<hash>-<hash>` (Deployment) | dependency | `docker.io/scnd/minio-mirror` | S3 server for public and private vaults; data on PVC `minio-data` (5 Gi, RWO, `local-path`) | 1 |
| `11-minio-provision-job.yaml` | `minio-provision-<hash>` | one-shot Job | `docker.io/scnd/mc-mirror` | creates the buckets and the access key, makes `kms-public` anonymously readable | — |
| `20-kms-prepopulate-keys-job.yaml` | `kms-prepopulate-keys-<hash>` | one-shot Job | `kms/core-service:speedrun-<sha>` | `kms-gen-keys` for parties 1–4 (signing keys, CA certs) | — |
| `31..34-kms-core-N.yaml` | `kms-core-N-core-N` (StatefulSet, `ordinals.start: N`) | SUT | `kms/core-service:speedrun-<sha>` (insecure, mock enclave, coverage-instrumented) | `kms-server`, party N; init containers fetch peer CA certs and run `kms-gen-keys` | 1 per party, 4 parties |
| `40-kms-core-init.yaml` | `kms-core-init-threshold-init-<hash>` | one-shot Job | `core-service-probe`, `core-service` | waits for all four cores' health, then `kms-init` creates the default context and epoch | — |
| `40-kms-core-init.yaml` | `kms-core-client-0` (StatefulSet) | workload | `kms/core-client:speedrun-<sha>` | idle (`tail -f /dev/null`) with `config.toml`; test template mounted from `41-kms-workload-tests.yaml` at `/opt/antithesis/test/v1/public_decrypt/` | 1 |

Pod `kms-core-N-core-N` is also the per-pod Service name, the MPC identity and the TLS subject.
Resource requests total 550m CPU / 9.25 Gi (under the 1 CPU / 10 Gi cap). No `setup_complete` is
emitted: testing starts once `kapp deploy` succeeds, which needs every Job complete and every core
ready.

## Why n = 4, t = 1 can stay available after one failure

- **Quorum.** The protocols tolerate t = 1 of n = 4 parties missing or faulty (n > 3t). With one
  core down, the remaining three are enough: the async robust open reconstructs once more than
  `degree + t` parties are accounted for (`core/threshold-execution/src/sharing/open.rs:474-482`),
  and user decryption needs `2t + 1` = 3 responses. Public decryption needs `num_majority` = 2 in the
  client.
- **No spare capacity, by design.** Parties are fixed identities holding distinct key shares; there
  are no roles to move. A failed party comes back as itself: its StatefulSet recreates the pod with
  the same name, and it reloads its shares and epochs from MinIO at boot. That's how the KMS stays
  available in production too (one pod per operator).
- **Nothing pins or starves roles.** One StatefulSet per party, no affinity, one node. A rescheduled
  pod has everything it needs, provided MinIO answers while its init containers run (see the
  hazard below).
- **Limit of the stock client.** The CLI connects to all four cores before sending, so while a core
  pod is down the stock CLI fails before reaching the SUT. The system stays available; the
  workload needs a three-core config to see it (see [sut-analysis.md](sut-analysis.md#the-client-cli)).

## Roles for fault injection

Exclusion lists in `advanced_k8s_test` are regexes matched unanchored against pod names. These are
part of the harness and stay the same for every run, including the setup smoke run.

| Role | Pods | Pod-name regex | network | pod_stop | pod_kill | Why |
|---|---|---|---|---|---|---|
| SUT | `kms-core-1-core-1` … `kms-core-4-core-4` | `^kms-core-[1-4]-core-[1-4]$` | yes | yes | yes | the system under test; every fault applies (clock jitter and thread pausing are not per-pod choices) |
| dependency | `minio-<hash>-<hash>` | `^minio-` | **yes** | no | no | see below |
| workload | `kms-core-client-0` | `^kms-core-client` | yes | no | no | the test driver; network trouble is realistic for a client, but deleting it kills running test commands and loses its `/tmp` state |
| one-shot Jobs | `minio-provision-…`, `kms-prepopulate-keys-…`, `kms-core-init-threshold-init-…` | (none needed) | — | — | — | completed before faults start (kapp waits for them, then `post_setup_settle_seconds`); pod faults pick only running pods |

Launch parameters (the same on every run):

```text
--param custom.container_faults_stop_exclusion_patterns=^kms-core-client,^minio-
--param custom.container_faults_kill_exclusion_patterns=^kms-core-client,^minio-
```

No network exclusion. Check the report's Fault Configuration section on the first run to confirm
that the comma-separated list was read as two patterns, and that its Cluster Status lists these pod
names. None of the patterns matches a core pod (`^kms-core-client` doesn't match
`kms-core-1-core-1`; `^minio-` also matches the completed `minio-provision` Job pod, which is
harmless).

**The workload pod is under a controller** (the `kms-core-client` StatefulSet), so a deleted pod
would be recreated. It's still excluded from pod faults: its state (`/tmp/kms-workload-state`: the
key's preprocessing ID and the reshared epochs) and every running command would be lost, which
produces findings about the harness rather than the KMS. Thread pausing stays on for it.

**MinIO: network faults yes, pod faults no.**

- **Network faults are needed.** MinIO stands in for AWS S3, whose latency and unavailability are
  realistic. They are also the only way to reach the documented reshare rollback, which happens on
  a storage failure ([Guarantee 3](guarantees.md#guarantee-3)), and boot-time storage errors on a
  restarted core. Excluding MinIO from network faults would also exempt all core↔MinIO traffic
  from partitions.
- **Pod faults are not.** AWS S3 is a regional, replicated service that doesn't restart; a single
  MinIO pod restart has no production analogue beyond "S3 unavailable", which network faults already
  model. Durability isn't the concern: the PVC is a `local-path` directory on the same node, so a
  pod stop or kill keeps all acknowledged data (the node's page cache survives a process kill); a
  restart would be a brief outage, not data loss. The concern is the init-container hazard below:
  while MinIO has no ready pod, its Service refuses connections at once, so any core pod starting in
  that window gets a broken config. Network faults mostly delay the init container instead (a dropped
  SYN makes `curl` wait ~2 min, outlasting most partitions).

## Known deployment hazards

- **Peer CA fetch in the core's init container (fixed in the harness).** The chart's
  `kms-core-init-load-env` lists each peer's CA certificate in MinIO with `curl -s` (no retry, no
  timeout) and substitutes it into `kms-server.toml` with `envsubst` (the chart's mock-enclave
  branch, `charts/kms-core/templates/_helpers.tpl:321-324`). If a listing returns nothing, it only
  prints a warning, `tls_cert.pem = ` is written empty, `kms-server` can't parse its config, and the
  container crash-loops; init containers don't re-run on a container restart, so the core stays
  down until its pod is deleted again. **Change in `31..34-kms-core-*.yaml`:** the four
  list-and-download blocks are replaced by one loop. `fetch_ca N` lists `PUB-pN/CACert/` and
  downloads the first key with `curl -sf --connect-timeout 5 --max-time 20`, and accepts it only if
  it contains `-----BEGIN CERTIFICATE-----`. Missing certificates are retried every 5 s; after
  600 s (measured with `/proc/uptime`) the container prints which parties are missing and exits 1,
  so the pod shows an init failure and kubelet runs the init container again. `KMS_CA_PEM_1..4`
  are exported only once all four are present. Nothing else in the manifests changed. Checked on
  local k3s: all four cores came up, and a core scaled to 0 and back rejoined.
- **SIGTERM.** `kms-server` handles SIGTERM with a graceful shutdown that waits for in-flight tasks
  (`threshold_kms.rs:117-150`). It's started from a multi-command `/bin/sh -c` script, so whether the
  signal reaches it depends on the image's shell; not verified. Either way `pod_stop` ends in SIGKILL
  after the default 30 s grace period.
- **Overlapping pod faults.** `pod_fault_interval_seconds` defaults to a 300 s median, separately for
  stop and for kill, so about one pod fault every 150 s across the four eligible cores. A core takes
  tens of seconds to a few minutes to come back, so a second core is often hit while the first is
  still down (rough estimate: a quarter to a third of pod faults at the default). The `600` s interval
  in the "network+kill" fault level roughly halves that.

## Two overlapping pod faults (more than t) per guarantee

| Guarantee | Effect of two cores down at once |
|---|---|
| [Guarantee 1](guarantees.md#guarantee-1) | Decryptions stall or fail (only 2 shares). Must still never return a wrong signed plaintext: crash faults aren't malicious, so the check stays on. |
| [Guarantee 2](guarantees.md#guarantee-2) | Judged only after faults stop; both cores must rejoin within the window. Two cores restarting in parallel take no longer than one (separate StatefulSets). |
| [Guarantee 3](guarantees.md#guarantee-3) | Reshares fail (the CLI needs all four); the source epoch must keep serving once enough cores are back. |
| [Guarantee 4](guarantees.md#guarantee-4) | Fewer than 3 responses: the client reports an error, which the guarantee allows. |
| [Guarantee 5](guarantees.md#guarantee-5) | Results unavailable; replies must still be from the documented set. |

## Open Questions

- Boot time of a core under Antithesis, and so the real downtime per pod fault, is unmeasured.
- Does the image's `/bin/sh` forward SIGTERM to `kms-server` (affects how long each `pod_stop`
  takes)?
- Do the exclusion parameters accept a comma-separated list of patterns? Check the first run's
  Fault Configuration section.
