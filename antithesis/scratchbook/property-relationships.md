---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references:
  - path: https://docs.zama.org/protocol/protocol/overview/kms
    why: guaranteed output delivery and robustness claims behind Guarantees 1, 2 and 4
  - path: https://docs.zama.org/protocol/zama-protocol-litepaper
    why: robustness claim behind Guarantee 1
---

# Property Relationships

## Decryption correctness under faults
Properties: public-decrypt-returns-encrypted-plaintext, user-decrypt-returns-encrypted-plaintext
Notes: Same fan-out, meta-store handling (`add_or_redo_failed_in_meta_store`), deterministic
session IDs and Async MPC sessions; they differ in the output (signed plaintext vs signcrypted
shares reconstructed by the client) and in slack (2 vs 3 responses needed). A defect in shared
session or meta-store code would likely show in both.

## Safety and liveness of decryption
Properties: public-decrypt-returns-encrypted-plaintext, recovers-after-faults
Notes: The liveness probe for recovers-after-faults is a public decryption, so every successful
probe is also checked by the plaintext `Always`. Together they are the safety and liveness sides
of the decryption protocol.

## Request-ID reuse
Properties: decrypt-request-id-retries, public-decrypt-returns-encrypted-plaintext,
user-decrypt-returns-encrypted-plaintext
Notes: Angles (3)–(5) of the public-decryption property are the same scenarios as
decrypt-request-id-retries. The retry property checks the reply set; the decryption properties
check that any result for a reused ID carries the original plaintexts. Suspected dominance: a
wrong result after a resend fails both.

## Epochs and resharing
Properties: reshare-preserves-key, public-decrypt-returns-encrypted-plaintext,
user-decrypt-returns-encrypted-plaintext, recovers-after-faults
Notes: Decryptions under reshared epochs are how reshare-preserves-key checks the reshared shares.
Every reshare adds key material a core loads at boot, so frequent reshares lengthen recovery
(recovers-after-faults). The recovery probe uses the kms-init epoch so a failed reshare can't fail
it.
