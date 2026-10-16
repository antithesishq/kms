---
sut_path: /home/avpai/src/customer/customer-zama/sut/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229  # plus the uncommitted Antithesis kit changes (sut/kms-changes.patch)
updated: 2026-10-16
external_references: []
---

# Deployment Topology

## Summary

A Kubernetes topology already exists in `antithesis/config/manifests/`. The
customer kit's `/home/avpai/src/customer/customer-zama/sut/README.txt` (step 3) says to launch it
with `snouty launch -w basic_k8s_test --config antithesis/config`. It is
already close to minimal for the cataloged property, so this file documents it and lists only
what the workload needs added. It does not redesign the topology.

```text
                      +-----------------------------+
                      | kms-core-client (workload)  |
                      | kms-core-client CLI + tests |
                      +--------------+--------------+
                        service gRPC | :50100 (all 4)       S3 reads (public key, verf keys)
          +----------------+---------+------+----------------+         |
          v                v                v                v         |
   +-------------+  +-------------+  +-------------+  +-------------+  |
   | kms-core-1  |<>| kms-core-2  |<>| kms-core-3  |<>| kms-core-4  |  |
   +------+------+  +------+------+  +------+------+  +------+------+  |
          |   core-to-core mTLS :50001 (full mesh)           |         |
          +----------------+----------------+----------------+         |
                           v                                           v
                    +---------------------------------------------------+
                    | MinIO  (kms-public / kms-private, PUB-pX/PRIV-pX) |
                    +---------------------------------------------------+
   one-shot Jobs: minio-provision, kms-prepopulate-keys, kms-core-init-threshold-init
```

Setup status, minimization decisions, and validation results live in
`k8s-minimization/working.md`.

## Components

| Manifest | Name | Role | Image | Runs | Justification |
|---|---|---|---|---|---|
| `10-minio.yaml` | `minio` | dependency | `docker.io/scnd/minio-mirror` | S3 server for public and private vaults | The cores need S3 storage, and the client reads the public key from it |
| `11-minio-provision-job.yaml` | `minio-provision` Job | setup | `docker.io/scnd/mc-mirror` | Creates the buckets | One-shot |
| `20-kms-prepopulate-keys-job.yaml` | `kms-prepopulate-keys` Job | setup | `kms/core-service:local` | `kms-gen-keys` for parties 1–4 | Each core needs every peer's CA cert at boot (see `Antithesis_RUN/README.md`) |
| `31..34-kms-core-N.yaml` | `kms-core-N-core-N` | service (SUT) | `kms/core-service:local` (insecure, mock enclave) | `kms-server`, party N | n = 4 is the smallest cluster with t = 1 (n > 3t), so it is the smallest setup where losing one party is survivable in principle |
| `40-kms-core-init.yaml` | `kms-core-init-threshold-init` Job | setup | `core-service-probe`, `core-service` | `kms-init` creates the context and epoch | One-shot, gated on the health of all 4 cores |
| `40-kms-core-init.yaml` | `kms-core-client` | client | `kms/core-client:local` | Idle (`tail -f /dev/null`) with `config.toml` | Workload driver host |

## What the workload needs added (not yet present)

- ~~**Test template**~~ **Added** (2026-10-16): `/opt/antithesis/test/v1/public_decrypt/` in the
  `kms-core-client` pod, mounted from the `kms-workload-tests` ConfigMap. The scripts use the
  fallback SDK. See `k8s-minimization/working.md`. It holds a keygen `first_` command, the
  decryption `parallel_driver_`, and an `anytime_` command that reshares the key into new
  epochs. The commands share state in the client container's `/tmp/kms-workload-state/`.
- ~~`setup_complete`~~ **Not needed** (corrected 2026-10-15). With no custom signal, Antithesis
  begins testing once `kapp deploy` succeeds, which requires the init Job to complete and every
  core to be ready. Run `95ddada30b89e65eb8212a702642ce0c-63-12` confirms this. See
  `k8s-minimization/working.md`.
- **Antithesis SDK in the workload.** The checks are client-side. A Rust driver that links
  `kms-core-client` / the `kms` client crate can use the Rust SDK. A shell driver would use the
  fallback `$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`.
- **A key to decrypt under.** `kms-init` creates only the context and epoch. A `first_` command
  must run keygen (`preproc-key-gen` + `key-gen`, or `insecure-key-gen`) and record the key ID for
  the drivers.

## Faults relevant to the cataloged property

- Pod kill or restart of **one** core at a time: within `t = 1`.
- Network partitions and latency between cores on `:50001`, and between the client and the cores.
- Faults on MinIO affect key reads on the cores and the public-key fetch on the client.

## Assumptions

- The cluster runs on Antithesis's K8s support, and pod kills can target individual core pods.

## Open Questions

- ~~Is setup reliable under fault injection?~~ Resolved (2026-10-15): faults start only after
  `kapp deploy` succeeds, so the bootstrap Jobs run fault-free. Run
  `95ddada30b89e65eb8212a702642ce0c-63-12` reached that point.
- Two kills overlapping in time (more than `t` parties down) can legitimately stop decryption.
  That does not affect the safety property here, but it matters for any future liveness property.
- Does a restarted core orphan its epoch (`Antithesis_RUN/README.md:113-115`)? `(partial: a
  code trace on 2026-10-16 found no code that rewrites a context with an empty epoch list.
  `ContextInfo` has no epoch list, and at boot a core loads every epoch's EpochData and key
  shares. `ensure_default_threshold_context_in_storage` re-stores the default context on every
  boot. The README symptom was not reproduced.)` If it does, the deploy script's repair does not
  run under Antithesis. Every node fault would then permanently
  disable a core, and two such faults would leave the cluster below quorum for the rest of the
  timeline. The answer decides whether node faults need limiting or a repair step, and whether
  the property can be reached at all late in a run (see the property's evidence file).
