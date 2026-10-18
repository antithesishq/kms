---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# Existing Antithesis Assertions

## Result

**No SDK assertions in the KMS code.** At the harness commit the only Antithesis code in the
Rust workspace is the coverage-instrumentation shim (`antithesis-instrumentation`, pulled into
`observability` only under `cfg(antithesis)`; see [antithesis/README.md](../README.md)). It adds
coverage, not assertions.

All assertions are in the workload, written with the fallback SDK (JSON lines in
`$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`) by
[helper_lib.sh](../test/v1/public_decrypt/helper_lib.sh): the public-decryption plaintext
`Always`, the authentication `Unreachable`, the two recovery `Always`s (Guarantee 2), the
reshare `Always`s (result, public key unchanged, source epoch still decrypts; Guarantee 3), the
user-decryption plaintext `Always` (Guarantee 4), the `AlwaysOrUnreachable`s that attribute a
wrong result under a reshared epoch to Guarantee 3, and their `Sometimes` and `Reachable`
markers. Every message, with its
guarantee, property, type and file, is in [assertion-map.json](assertion-map.json); their status
per property is in each evidence file under [properties/](properties/).

## How the scan was done

- Searched all `*.rs` and `Cargo.toml` files outside `target/` for `antithesis`,
  `antithesis_sdk`, `assert_always`, `assert_sometimes`, `assert_reachable`,
  `assert_unreachable`. The only matches are the shim in `Cargo.toml`, `observability/Cargo.toml`
  and `observability/src/lib.rs`.

## Implication

Every assertion proposed in [property-catalog.md](property-catalog.md) belongs in the workload. No
SUT-side assertion is proposed: each condition is visible to the client.
