---
sut_path: /home/avpai/src/customer/customer-zama/sut/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229  # plus the uncommitted Antithesis kit changes (sut/kms-changes.patch)
updated: 2026-10-14
external_references: []
---

# Property Relationships

## Decryption correctness under faults
Properties: public-decrypt-returns-encrypted-plaintext
Notes: This is the only cataloged property, because the user asked for exactly one. It has no
clusters or dominance relationships yet. When the catalog grows, expect it to pair with:
(a) a liveness counterpart (public decryption eventually succeeds with at most t parties faulted,
after a quiet period). That property would share the same workload and fault scenarios. Together
they form the safety and liveness sides of the decryption protocol. (b) A user-decryption
reconstruction-correctness property, which would share the meta-store redo path and the derived
session IDs.
