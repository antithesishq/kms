# fix-verify-1 · a7167532671d016c1683aa3df1145e45-64-4 · fixverify-decryption-stalls-after-core-restart@3095d82a · completed · 120 m
Report: [triage report](https://zama.antithesis.com/report/E3aRgfAZx0FG9ubZyK2gLIoR/WOfMjnEReqZRagmPUuWwUHPDAjmwjhtZw3u5U5iRSuU.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA4OjA5OjE5LjE3MjY0NjYxM1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV09mTWpuRVJlcVpSYWdtUFV1V3dVSFBEQWptd2podFp3M3U1VTVpUlN1VS5odG1sIiwicmVwb3J0X2lkIjoiRTNhUmdmQVp4MEZHOXViWnlLMmdMSW9SIn19feJnQdPR6ASOY1JTnB5-6WNI3-5xqJfWurzelFpKrcEWWRqdnjJ2gCtotLkMWQ5e1aqAmMFoC5nDcB466sYCTwU)

Session `e102516a058c0d93a088a11f12a8de2d-64-4`. Turbo tier, fault level 3 (`network,pod_stop,pod_kill,clock_jitter`, one pod fault about every 300 s, MinIO and the client pod excluded from pod faults), the same settings as the pre-fix run that reproduced the known bug ([hunt-prefix-1](hunt-prefix-1.md)). Build: the pre-fix build plus the proposed patch [decryption-stalls-after-core-restart.patch](../../fixes/decryption-stalls-after-core-restart.patch); same-workload check [same-workload-fixverify.txt](../logs/same-workload-fixverify.txt). Completed 2026-10-18T09:09:19Z. Property list: [props-a7167532.ndjson](../logs/props-a7167532.ndjson). Written from the property list by the orchestrator (no failure needed a log, so there are no "## Failing" sections).

63 properties: 60 pass, 3 fail. **Every guarantee property passes, and every Reachable and Sometimes marker was hit, including both [Guarantee 2](../guarantees.md#guarantee-2) Sometimes markers: a core the client couldn't reach after faults stopped came back (87 times), and a decryption that failed its first attempt after faults stopped then succeeded (116 times).** Before the fix, 118 of 8,424 checks (1.4 %) failed in [hunt-prefix-1](hunt-prefix-1.md), so about 97 failures would be expected here; none occurred. The failures are Antithesis defaults seen in earlier runs: the two known fail-fast container exits and "Peak memory usage" (12 failing examples, default 9.71 GiB VM; see [peak-memory-command-backlog](../false-positives.md#peak-memory-command-backlog)).

| Property | Guarantee | Status | Examples | Counterexamples |
|---|---|---|---|---|
| public decryption response carries the encrypted plaintext (always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 19612 | 0 |
| public decryption response from a KMS party fails authentication (unreachable) | [Guarantee 1](../guarantees.md#guarantee-1) | passing | 0 | 0 |
| public decryption succeeded with every party's response checked (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3760 | 0 |
| public decryption succeeded through the sync endpoint (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 7704 | 0 |
| batched public decryption succeeded (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5330 | 0 |
| public decryption succeeded with SnS left to the cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3164 | 0 |
| public decryption attempt ended without a verdict (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 11319 | 0 |
| public decryption succeeded under a reshared epoch (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 3391 | 0 |
| workload generated an FHE key (reachable) | — (setup) | hit | 5858 | 0 |
| key reshare result from every KMS party matches the reshared key (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 14331 | 0 |
| key reshare succeeded from an epoch that a reshare created (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 3621 | 0 |
| key reshare attempt ended without a verdict (reachable) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 14082 | 0 |
| public decryption succeeded through three of the four cores (reachable) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 5046 | 0 |
| public decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 3944 | 2672 |
| public decryption succeeded after the client left out a core it could not connect to (sometimes) | [Guarantee 1](../guarantees.md#guarantee-1) | hit | 371 | 301 |
| every core accepts client connections within 600 s after faults stop (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 6934 | 0 |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing | 6934 | 0 |
| a core the client could not connect to after faults stopped accepted connections again (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 87 | 0 |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (sometimes) | [Guarantee 2](../guarantees.md#guarantee-2) | hit | 116 | 0 |
| public decryption under a reshared epoch carries the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 3391 | 0 |
| public key that every party publishes for a key is unchanged by a reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 29337 | 0 |
| public key read back unchanged after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 15059 | 0 |
| public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare (always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 35927 | 0 |
| public decryption under the source epoch succeeded after a reshare that ended without a verdict (sometimes) | [Guarantee 3](../guarantees.md#guarantee-3) | hit | 21160 | 8905 |
| user decryption reconstructs the encrypted plaintext (always) | [Guarantee 4](../guarantees.md#guarantee-4) | passing | 11141 | 0 |
| user decryption under a reshared epoch reconstructs the encrypted plaintext (always or unreachable) | [Guarantee 3](../guarantees.md#guarantee-3) | passing | 1492 | 0 |
| user decryption succeeded on a retry after an attempt without a verdict (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3824 | 1528 |
| user decryption succeeded under a reshared epoch (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 1492 | 844 |
| batched user decryption succeeded (sometimes) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4327 | 1768 |
| user decryption succeeded through the sync endpoint (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 3462 | 0 |
| user decryption succeeded with every party's response collected (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 5800 | 0 |
| user decryption succeeded with SnS left to the cores (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 2319 | 0 |
| user decryption attempt ended without a verdict (reachable) | [Guarantee 4](../guarantees.md#guarantee-4) | hit | 4851 | 0 |
| Peak memory usage (Antithesis default) | — | **failing** ([VM size](../false-positives.md#peak-memory-command-backlog)) | 148404 | 12 |
| No unexpected container exits: container: kms-core, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot)) | 0 | 1584 |
| No unexpected container exits: container: kms-core-init-gen-keys, namespace: kms-threshold-staging , exit code: 1 (Antithesis default) | — | **failing** ([known false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) | 0 | 116 |

## Verdict
The proposed fix is **verified** by the rule in use: the [Guarantee 2](../guarantees.md#guarantee-2) Always properties pass (6,934 checks each, 0 failing) and both of its Sometimes markers were hit. On the pre-fix build, the same check failed in both 4-hour runs (118 and 41 failing examples; [hunt-prefix-1](hunt-prefix-1.md), [hunt-prefix-2](hunt-prefix-2.md)). Caveat: 120 minutes here against 240 there; at the pre-fix failure rate (118 of 8,424 checks, 1.4 %) about 97 failures would have been expected in this run's 6,934 checks.
