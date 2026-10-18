# iterate-4 · 63908ef2 · current@3095d82a · completed · 30 m
Report: [triage report](https://zama.antithesis.com/report/DgQ4uIHChAmsytQJtPrXPQDb/yPjTJtmZAM_112M-SSCbQk4uO9AN3vqOJ1_evjj1u1A.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoieVBqVEp0bVpBTV8xMTJNLVNTQ2JRazR1TzlBTjN2cU9KMV9ldmpqMXUxQS5odG1sIiwicmVwb3J0X2lkIjoiRGdRNHVJSENoQW1zeXRRSnRQclhQUURiIn19LCJuYmYiOiIyMDI2LTEwLTE3VDIzOjIwOjU1LjY0MTU1ODE4MFoifR1-46AAkqn4ZQ-dZa71vHM-dAwh9nGO_Tygp74fX6RNriNTp1uIFeFv9z8vEpT_ka5h0N_NjbSgVVNwI4KCSgc)

Fault level 3, the launcher's default set: network faults, pod stops and kills (median 300 s apart), clock jumps. Workload `configmap@3cce831073f5` (Guarantees 1–4).

| Property | Guarantee | Status |
|---|---|---|
| every guarantee Always and AlwaysOrUnreachable in [assertion-map.json](../assertion-map.json) | Guarantees 1–4 | passing |
| No unexpected container exits: kms-core exit 1; kms-core-init-gen-keys exit 1 | — | failing: the known fail-fast restarts ([false positive](../false-positives.md#core-exits-when-storage-unreachable-at-boot), [false positive](../false-positives.md#gen-keys-init-exits-when-storage-unreachable)) |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | Guarantee 2 | not hit |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | Guarantee 2 | not hit (hit in iterate-1 and iterate-2) |
| everything else (59 properties) | — | passing |

No new kind of failure, so no logs were downloaded. Property list: [props-iterate-4.ndjson](../logs/props-iterate-4.ndjson).
