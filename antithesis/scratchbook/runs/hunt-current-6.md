# hunt-current-6 · 9f7fa3b1be496d51e9f1282f511a729c-64-4 · current@3095d82a · completed · 125 m
Report: [triage report](https://zama.antithesis.com/report/o8xNfnvPNgTUfOskOctLnlkS/-F82X7-TJYyvoHCWd5I-9QkUhYMCmCi2ouiS5N_b-eM.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiLUY4Mlg3LVRKWXl2b0hDV2Q1SS05UWtVaFlNQ21DaTJvdWlTNU5fYi1lTS5odG1sIiwicmVwb3J0X2lkIjoibzh4TmZudlBOZ1RVZk9za09jdExubGtTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDA5OjM5OjE0LjExNTgwODU2M1oifZQTX0mC0s_eteptEa4dnjKUBSq7S1eeAtwcWmKF67SGnjmZE3uBvhjqT5bzEYFf9J4j7rxMcCA2c-dR621ggQE)

Session `dc90cec2d0f68894eadd62db01801063-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, MinIO and the client pod excluded from pod faults) with timing fuzzing (`custom.timing_fuzzing=true`) on a 16 GiB VM (`custom.vm_memory_mb=16384`). Purpose: does the Guarantee 2 failure under timing fuzzing in [hunt-current-3](hunt-current-3.md) reproduce with memory pressure removed. No "No Antithesis errors", coredns or journald failure this time ([timing-fuzzing-guest-stalls](../false-positives.md#timing-fuzzing-guest-stalls)). Completed 2026-10-18T10:39:15Z. Property list: [props-9f7fa3b1.ndjson](../logs/props-9f7fa3b1.ndjson). Written by the orchestrator from the property list: every failure is a known one, so no log was needed. A run-wide search for "ENTERING RECOVERY MODE" ([storage-error-enters-recovery-mode](../violations/storage-error-enters-recovery-mode.md)) on the finished run, at 10:58 UTC, returned no event and no error ([output](../logs/recovery-mode-9f7fa3b1.json)); the same search returns the one entry in hunt-current-3. There are no "## Failing" sections: every failure is a known one, listed in the table with its entry.

64 properties: 61 pass, 3 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, and every Reachable and Sometimes marker was hit.**

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 12840 | 0 |
| public decryption response from a KMS party fails authentication (unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1061 | 0 |
| public decryption succeeded through the sync endpoint (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5081 | 0 |
| batched public decryption succeeded (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3397 | 0 |
| public decryption succeeded with SnS left to the cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1935 | 0 |
| public decryption attempt ended without a verdict (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3516 | 0 |
| public decryption succeeded under a reshared epoch (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 694 | 0 |
| workload generated an FHE key (reachable) | — (setup) | hit | 3934 | 0 |
| key reshare result from every KMS party matches the reshared key (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 8273 | 0 |
| key reshare succeeded from an epoch that a reshare created (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2576 | 0 |
| key reshare attempt ended without a verdict (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 23683 | 0 |
| public decryption succeeded through three of the four cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5100 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1341 | 910 |
| public decryption succeeded after the client left out a core it could not connect to (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 166 | 211 |
| every core accepts client connections within 600 s after faults stop (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 4843 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 4843 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 137 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 215 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 694 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 32538 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 24343 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 37618 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 29426 | 8652 |
| user decryption reconstructs the encrypted plaintext (always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 6542 | 0 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 1290 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 435 | 671 |
| user decryption succeeded under a reshared epoch (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1290 | 1034 |
| batched user decryption succeeded (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2511 | 678 |
| user decryption succeeded through the sync endpoint (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4375 | 0 |
| user decryption succeeded with every party's response collected (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1286 | 0 |
| user decryption succeeded with SnS left to the cores (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1506 | 0 |
| user decryption attempt ended without a verdict (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1861 | 0 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 1478 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101 (Antithesis default) | — | **failing** ([suspect](../false-positives.md#boot-panic-port-in-use)) | 0 | 8 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 77 |
