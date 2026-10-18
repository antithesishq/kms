# hunt-current-5 · f138c07c6969e0a9691b2a7192e8749c-64-4 · current@3095d82a · completed · 180 m
Report: [triage report](https://zama.antithesis.com/report/fGBWatltHprLF20S9ngnf_Xx/axTAE2jgHdQBkKrbRNM9KwkMvW5_QmpoTc8LDOpxSOY.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA5OjIwOjExLjc0ODYwNzIxOFoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiYXhUQUUyamdIZFFCa0tyYlJOTTlLd2tNdlc1X1FtcG9UYzhMRE9weFNPWS5odG1sIiwicmVwb3J0X2lkIjoiZkdCV2F0bHRIcHJMRjIwUzluZ25mX1h4In19fW3zT4lKIsk7YZnr70bN1tmOm4j8MTfQ6Vdl27XtDiq70F1RB_57_1SoZ7QUNY07jsf_7-ZuPmZontnlKcNVKQ4)

Session `80a943125b1b760f9bfc7039d4d82a69-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, MinIO and the client pod excluded from pod faults) with strobing (60 s of chaos, quiet windows of 60–120 s) and a pod fault about every 150 s instead of 300 s, on the default 9.71 GiB VM. Completed 2026-10-18T10:20:12Z. Property list: [props-f138c07c.ndjson](../logs/props-f138c07c.ndjson). Written by the orchestrator from the property list: every failure is a known one, so no log was needed. A run-wide search for "ENTERING RECOVERY MODE" ([storage-error-enters-recovery-mode](../violations/storage-error-enters-recovery-mode.md)) on the finished run, at 10:58 UTC, returned no event and no error ([output](../logs/recovery-mode-f138c07c.json)); the same search returns the one entry in hunt-current-3. There are no "## Failing" sections: every failure is a known one, listed in the table with its entry.

64 properties: 60 pass, 4 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, and every Reachable and Sometimes marker was hit.**

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 18972 | 0 |
| public decryption response from a KMS party fails authentication (unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5368 | 0 |
| public decryption succeeded through the sync endpoint (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 6677 | 0 |
| batched public decryption succeeded (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 4863 | 0 |
| public decryption succeeded with SnS left to the cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3038 | 0 |
| public decryption attempt ended without a verdict (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3835 | 0 |
| public decryption succeeded under a reshared epoch (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 3290 | 0 |
| workload generated an FHE key (reachable) | — (setup) | hit | 5693 | 0 |
| key reshare result from every KMS party matches the reshared key (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 27034 | 0 |
| key reshare succeeded from an epoch that a reshare created (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 10022 | 0 |
| key reshare attempt ended without a verdict (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 12044 | 0 |
| public decryption succeeded through three of the four cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3936 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1610 | 1649 |
| public decryption succeeded after the client left out a core it could not connect to (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 151 | 164 |
| every core accepts client connections within 600 s after faults stop (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 7121 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 7121 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 64 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 165 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3290 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 39336 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 12349 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 51252 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 21825 | 2038 |
| user decryption reconstructs the encrypted plaintext (always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 16476 | 0 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3745 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 703 | 3823 |
| user decryption succeeded under a reshared epoch (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3745 | 5956 |
| batched user decryption succeeded (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 6521 | 2480 |
| user decryption succeeded through the sync endpoint (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 9259 | 0 |
| user decryption succeeded with every party's response collected (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4680 | 0 |
| user decryption succeeded with SnS left to the cores (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4294 | 0 |
| user decryption attempt ended without a verdict (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 6514 | 0 |
| Peak memory usage (Antithesis default) | — | **failing** ([VM size](../false-positives.md#peak-memory-command-backlog)) | 151370 | 1 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 757 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101 (Antithesis default) | — | **failing** ([suspect](../false-positives.md#boot-panic-port-in-use)) | 0 | 115 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 65 |
