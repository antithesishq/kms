# hunt-current-4 · 6111d172031d2759747024bdb638b01a-64-4 · current@3095d82a · completed · 105 m
Report: [triage report](https://zama.antithesis.com/report/P1OrdTOwOQhvk1Bda_x3yATq/6G9cywvyWShFE6lQzOi0RmoaJzzoiArwrA7fpzOnKiU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiNkc5Y3l3dnlXU2hGRTZsUXpPaTBSbW9hSnp6b2lBcndyQTdmcHpPbktpVS5odG1sIiwicmVwb3J0X2lkIjoiUDFPcmRUT3dPUWh2azFCZGFfeDN5QVRxIn19LCJuYmYiOiIyMDI2LTEwLTE4VDA3OjA4OjUyLjM1MjQ2MTQ4Mloifcvim4mQHGuO4yuywJaNWaRVq1skn9a4_E1eXUtmVC_gVSCCpxteSZeLsyy0z01YAT6E2l37bGY50_RmzPPTgwM)

Session `aebc59a94f795d0b3948c17f521156f2-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, one pod fault about every 300 s, MinIO and the client pod excluded from pod faults), no strobing quiet windows (`strobe_quiet_max_seconds` 0). These are the settings of [hunt-current-1](hunt-current-1.md), with two changes: the test VM has 16 GiB (`custom.vm_memory_mb=16384`; the earlier runs used the default, 9.71 GiB), and the run lasts 105 minutes instead of 240. The question was whether "Peak memory usage", which failed in all four 4-hour hunts, passes with more memory. Completed 08:08:52Z. Property list: [props-6111d172.ndjson](../logs/props-6111d172.ndjson); run details: [show-6111d172.json](../logs/show-6111d172.json).

63 properties: 61 pass, 2 fail. **Every guarantee property in [assertion-map.json](../assertion-map.json) passes, every Reachable and Sometimes marker was hit, and "Peak memory usage" passes (0 counterexamples).** The only failures are the two known fail-fast container exits. The kms-core exit 101 property (boot panic on a port in use) isn't in this run's property list at all.

Setup and instrumentation are fine. There is no explicit setup-complete property in the list. "All commands were started at least once", "All commands were run to completion at least once" and "workload generated an FHE key" pass. "Software was instrumented" lists kms-server (970,574 locations), kms-gen-keys (394,465), kms-core-client (348,094) and kms-init (143,553). "Every instrumented module has symbols" passes, and thread pausing ran in all 9 kms containers. No logs were downloaded for this triage.

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 12530 | 0 |
| public decryption response from a KMS party fails authentication (Unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1394 | 0 |
| public decryption succeeded through the sync endpoint (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3071 | 0 |
| batched public decryption succeeded (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2884 | 0 |
| public decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1775 | 0 |
| public decryption attempt ended without a verdict (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2848 | 0 |
| public decryption succeeded through three of the four cores (Reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 2668 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 1130 | 1260 |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 581 | 473 |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 5625 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 5625 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 43 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 200 | 0 |
| public decryption succeeded under a reshared epoch (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 1166 | 0 |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 11843 | 0 |
| key reshare succeeded from an epoch that a reshare created (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 2445 | 0 |
| key reshare attempt ended without a verdict (Reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 21046 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 1166 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 33722 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 22080 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 38182 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (Sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 25947 | 5819 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (AlwaysOrUnreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 1172 | 0 |
| user decryption reconstructs the encrypted plaintext (Always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 6856 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 950 | 959 |
| user decryption succeeded under a reshared epoch (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1172 | 1121 |
| batched user decryption succeeded (Sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2581 | 679 |
| user decryption succeeded through the sync endpoint (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4446 | 0 |
| user decryption succeeded with every party's response collected (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3560 | 0 |
| user decryption succeeded with SnS left to the cores (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1848 | 0 |
| user decryption attempt ended without a verdict (Reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2156 | 0 |
| workload generated an FHE key (Reachable; setup / bootstrap) | — | hit | 4704 | 0 |
| All commands were started at least once (setup / bootstrap) | — | passing | 1 | 0 |
| All commands were run to completion at least once (setup / bootstrap) | — | passing | 1 | 0 |
| Commands finish with zero exit code (all 5 commands) | — | passing | 4704–39708 each | 0 |
| Peak memory usage (Antithesis default) | — | passing | 126556 | 0 |
| **No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1** (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 1451 |
| **No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1** (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 121 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 101 (Antithesis default) | — | not in the property list (no exit 101 in this run) | — | — |
| Other Antithesis defaults (instrumentation, symbols, thread pausing, crashes, build, fault injector, parallelism, software versions) | — | passing | — | — |

The Sometimes markers with counterexamples pass: a Sometimes property only needs one true evaluation, and the false ones are the cases where the condition didn't apply.

## Failing properties
Both are known false positives. No log downloaded.
- kms-core exit 1: a restarted core exits when it can't read its keys from MinIO at boot ([false-positives.md](../false-positives.md#core-exits-when-storage-unreachable-at-boot)). 1451 counterexamples (1335 in hunt-current-2); first moment input_hash=5274908163408575179 vtime=274.74683463480324.
- kms-core-init-gen-keys exit 1: the key-generation init container exits when MinIO is unreachable ([false-positives.md](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)). 121 counterexamples (205 in hunt-current-2); first moment input_hash=-6477681185838797895 vtime=326.99683447019197.

The kms-core exit 101 property ([false-positives.md](../false-positives.md#boot-panic-port-in-use)) doesn't appear in this run, so no exit with code 101 was reported. It had 150 counterexamples in [hunt-current-2](hunt-current-2.md) and 3 in [iterate-3](iterate-3.md), and it didn't appear in [hunt-current-1](hunt-current-1.md) either.

## Peak memory usage
**Passing: 126556 examples, 0 counterexamples.** The Antithesis default checks that memory never goes above 95 % of the total available. With 16 GiB, that threshold is about 15.2 GiB.
- Detail exposed: none. The property record has only one example moment (input_hash=-4766553260371646552 vtime=713.1425959689077), with no details field and no memory value. `snouty runs --json events` returns 0 events for "Peak memory usage". The peak value isn't readable through the API.
- Comparison:

| Run | Test VM | Faults | Duration | Examples | Counterexamples |
|---|---|---|---|---|---|
| hunt-current-4 (this run) | 16 GiB | level 3 | 105 m | 126556 | 0 |
| [hunt-current-1](hunt-current-1.md) | default (9.71 GiB) | level 3 | 240 m | 122387 | 1235 |
| [hunt-current-2](hunt-current-2.md) | default (9.71 GiB) | level 4, strobing | 240 m | 238850 | 615 |

- In the two earlier hunts, the first counterexamples came at vtime 733.60 and 801.69 in their histories, long after setup. They followed the backlog of concurrent test commands and reshares ([false-positives.md](../false-positives.md#peak-memory-command-backlog)). With 16 GiB, no history in this run crossed 95 %. That fits the earlier reading that the 9.71 GiB VM lacked headroom for the backlog. It argues against memory that keeps growing until it crosses whatever limit the VM has.
- Limits of the comparison: this run is 105 minutes, not 240, so it explored fewer histories. It still evaluated the property more often than hunt-current-1 did (126556 vs 122387 examples). Without the peak value, the data can't say how close the run came to 15.2 GiB, and a leak too slow to reach that within a history can't be ruled out.
