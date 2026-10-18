# iterate-1 · d886f1ac · current@3095d82a · completed · 30 m
Report: [triage report](https://zama.antithesis.com/report/i9QvVQsNUV3lWeROzE30qG3G/YGlP1gzJvu1YGvvnc5gFTZMAddJga9xKGZuRd7-K0hw.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE3VDIxOjE3OjE4LjI3MzMxNjI2MloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiWUdsUDFnekp2dTFZR3Z2bmM1Z0ZUWk1BZGRKZ2E5eEtHWnVSZDctSzBody5odG1sIiwicmVwb3J0X2lkIjoiaTlRdlZRc05VVjNsV2VST3pFMzBxRzNHIn19fepgRllfmZncOVYFOd51epaITiFiUjGu3PlmgPn9wWx1mLwq-qLcGnKECPOyVSDkASL6IBKxeaNgUpgFDAdSLA0)

Network faults only (fault level 1). Workload `configmap@e3587b5624f9`: the Guarantee 1 driver with 3/4-core configs and retries, the Guarantee 2 recovery check, and the init-container certificate retry.

| Property | Guarantee | Status |
|---|---|---|
| public decryption response carries the encrypted plaintext (Always) | [Guarantee 1](../guarantees.md#guarantee-1) | passing, reached |
| every core accepts client connections within 600 s after faults stop (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached |
| public decryption answered by all four cores succeeds within 300 s of every core accepting connections (Always) | [Guarantee 2](../guarantees.md#guarantee-2) | passing, reached |
| key reshare result from every KMS party matches the reshared key (Always) | [Guarantee 3](../guarantees.md#guarantee-3) | passing, reached |
| public decryption answered by all four cores succeeded after a failed first attempt once faults stopped (Sometimes) | Guarantee 2 | hit |
| public decryption succeeded on a retry after an attempt without a verdict (Sometimes) | Guarantee 1 | hit |
| a core the client could not connect to after faults stopped accepted connections again (Sometimes) | Guarantee 2 | **not hit** |
| public decryption succeeded after the client left out a core it could not connect to (Sometimes) | Guarantee 1 | **not hit** |
| Antithesis defaults (instrumentation, symbols, exits, crashes, memory) | — | passing (46 of 48 properties pass) |

Both unhit markers need a core the client can't connect to, i.e. a core pod that is down. This run had network faults only, which slow or drop traffic but never stop a pod. See [false-positives.md](../false-positives.md#sometimes-need-pod-faults).
