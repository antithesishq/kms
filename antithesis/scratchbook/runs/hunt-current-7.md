# hunt-current-7 · b4fb2ef150cdb9e48bb03559d094b203-64-4 · current@3095d82a · completed · 125 m
Report: [triage report](https://zama.antithesis.com/report/_r-7C_mLdeGjzdbEVsK15PuH/42JWZeknAsGm-Z_Vb0O9CfhoehGQ8EEfn0gC54lbVw4.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA5OjM3OjMxLjc3MzcwMzg0MloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiNDJKV1pla25Bc0dtLVpfVmIwTzlDZmhvZWhHUThFRWZuMGdDNTRsYlZ3NC5odG1sIiwicmVwb3J0X2lkIjoiX3ItN0NfbUxkZUdqemRiRVZzSzE1UHVIIn19fd7jJl7N6kidkKYdWS4iGgq7nHJea7bzEdw3s4okVCcvr3q6xrnYfPnZxMlXsbyGPWGtO3JfQ-rKPdebKXwKgQk)

Session `b6ac3d60947c7e134a526ed9b8edfbcd-64-4`. Turbo tier, fault level 4: `network,pod_stop,pod_kill,clock_jitter` with strobing (60 s of chaos, quiet windows of 60–120 s), plus timing fuzzing (`custom.timing_fuzzing=true`), on the default 9.71 GiB VM. Purpose: timing fuzzing with more quiet windows, so recovery is checked more often. No "No Antithesis errors", coredns or journald failure this time ([timing-fuzzing-guest-stalls](../false-positives.md#timing-fuzzing-guest-stalls)). Completed 2026-10-18T10:37:32Z. Property list: [props-b4fb2ef1.ndjson](../logs/props-b4fb2ef1.ndjson). Written by the orchestrator from the property list: every failure is a known one, so no log was needed. A run-wide search for "ENTERING RECOVERY MODE" ([storage-error-enters-recovery-mode](../violations/storage-error-enters-recovery-mode.md)) on the finished run, at 10:58 UTC, returned no event and no error ([output](../logs/recovery-mode-b4fb2ef1.json)); the same search returns the one entry in hunt-current-3. There are no "## Failing" sections: every failure is a known one, listed in the table with its entry.

63 properties: 60 pass, 3 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, and every Reachable and Sometimes marker was hit.**

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 45136 | 0 |
| public decryption response from a KMS party fails authentication (unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1511 | 0 |
| public decryption succeeded through the sync endpoint (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 8923 | 0 |
| batched public decryption succeeded (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 16641 | 0 |
| public decryption succeeded with SnS left to the cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 11372 | 0 |
| public decryption attempt ended without a verdict (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 40320 | 0 |
| public decryption succeeded under a reshared epoch (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 13970 | 0 |
| workload generated an FHE key (reachable) | — (setup) | hit | 4872 | 0 |
| key reshare result from every KMS party matches the reshared key (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 19396 | 0 |
| key reshare succeeded from an epoch that a reshare created (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 4539 | 0 |
| key reshare attempt ended without a verdict (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 13285 | 0 |
| public decryption succeeded through three of the four cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 6680 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 26870 | 27466 |
| public decryption succeeded after the client left out a core it could not connect to (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 522 | 358 |
| every core accepts client connections within 600 s after faults stop (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 6092 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 6092 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 252 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 252 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 13970 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 33470 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 14282 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 49387 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 30109 | 5342 |
| user decryption reconstructs the encrypted plaintext (always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 10909 | 0 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 2416 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 629 | 917 |
| user decryption succeeded under a reshared epoch (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2416 | 1246 |
| batched user decryption succeeded (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4234 | 673 |
| user decryption succeeded through the sync endpoint (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 5724 | 0 |
| user decryption succeeded with every party's response collected (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4095 | 0 |
| user decryption succeeded with SnS left to the cores (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2664 | 0 |
| user decryption attempt ended without a verdict (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1987 | 0 |
| Peak memory usage (Antithesis default) | — | **failing** ([VM size](../false-positives.md#peak-memory-command-backlog)) | 121556 | 331 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 911 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 58 |
