# Inputs

| Field | Content |
|---|---|
| Customer | Zama ([zama.ai](https://www.zama.ai)) |
| Product | Zama KMS: the threshold key management system behind the Zama Protocol's FHE decryption (`kms-server` cores, `kms-core-client`) |
| Repo | This checkout, `/home/exedev/kms` (branch `antithesis-poc-speedrun`, commit `3095d82a`; upstream [zama-ai/kms](https://github.com/zama-ai/kms), base commit `4a644c85`) |
| Notes | No CRM or Glean notes: Glean and Salesforce are not authenticated in this session, and speedrun never starts a login |
| Pre-existing artifacts | An Antithesis Kubernetes harness in [antithesis/](../): manifests in [config/manifests/](../config/manifests/), image build in [images/](../images/), a `public_decrypt` workload in [test/v1/public_decrypt/](../test/v1/public_decrypt/), driven by the [Makefile](../Makefile) and described in the [README](../README.md). Research files already in this scratchbook: [sut-analysis.md](sut-analysis.md), [deployment-topology.md](deployment-topology.md), [property-catalog.md](property-catalog.md), [one property file](properties/public-decrypt-returns-encrypted-plaintext.md), [existing-assertions.md](existing-assertions.md), [property-relationships.md](property-relationships.md), [evaluation/synthesis.md](evaluation/synthesis.md), [k8s-minimization/working.md](k8s-minimization/working.md). Coverage instrumentation is already wired in (`observability` crate under `cfg(antithesis)`, [kms-binaries.Dockerfile](../images/kms-binaries.Dockerfile)) |

## Environment notes

- snouty's environment variables (`ANTITHESIS_TENANT=orbitinghail`, `ANTITHESIS_BASE_URL` on an exe.dev team proxy) are rejected with HTTP 403 ("team integration not found or not attached to this VM"). The snouty settings file (`~/.config/snouty/settings.toml`) names tenant `zama` and registry `us-central1-docker.pkg.dev/molten-verve-216720/zama-repository`, the same registry the harness pushes to, and passes `snouty doctor` ([log](logs/doctor-p0.json)). speedrun runs every snouty command with those four `ANTITHESIS_*` variables unset.
- The registry holds earlier, uninstrumented KMS images (`nojitter-20261014-1056`, `nojitter-20261016-1730`, `local`); no image built from the instrumented harness has been pushed, and none is in the local image store.
