# setup-2 · 89e114d4 · current@3095d82a · completed · 15 m
Report: [triage report](https://zama.antithesis.com/report/ilG2W2eWtahE0MgFCM13ilUk/nBs_rWnrBYj49XFAHGNeCJoa2oeSD6hZxnAfR42DeIE.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE3VDIwOjI4OjA3LjA2MDYyNjI2M1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoibkJzX3JXbnJCWWo0OVhGQUhHTmVDSm9hMm9lU0Q2aFp4bkFmUjQyRGVJRS5odG1sIiwicmVwb3J0X2lkIjoiaWxHMlcyZVd0YWhFME1nRkNNMTNpbFVrIn19fds1Wp-y5Jgw079ePKBsYsHQIOAWfzdmjCCnJzav3zeVdEZvRnq1RrY4e_Ea8-TXpWHSH0RtQmXY0drVL_o5lQg)

Network faults only (fault level 1). The existing public_decrypt workload (keygen, decryption driver, reshare), from git HEAD.

| Property | Guarantee | Status |
|---|---|---|
| All 41 properties in the report, Antithesis defaults included | — | passing |
| Software was instrumented; Every instrumented module has symbols; Thread pausing was enabled | — | passing |
| public decryption response carries the encrypted plaintext (Always) | Guarantee 1 | passing, reached |
| public decryption response from a KMS party fails authentication (Unreachable) | Guarantee 1 | passing |
| key reshare result from every KMS party matches the reshared key (Always) | Guarantee 3 | passing, reached |
| every Reachable marker of the workload (keygen, batched, sync, -a, reshared epoch, no-verdict attempts) | — | hit |

No failing properties, so no logs were downloaded. Property list: [props-setup-2.ndjson](../logs/props-setup-2.ndjson).
