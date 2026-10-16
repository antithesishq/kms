---
sut_path: /home/avpai/src/customer/customer-zama/sut/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229  # plus the uncommitted Antithesis kit changes (sut/kms-changes.patch)
updated: 2026-10-14
external_references: []
---

# Existing Antithesis Assertions

## Result

**None found.** The codebase has no Antithesis SDK instrumentation.

## How the scan was done

- Searched all files except `target/` and `.git/` for `antithesis_sdk`, `assert_always!`,
  `assert_sometimes!`, `assert_reachable!`, `assert_unreachable!`, and
  `assert_always_or_unreachable!`. There were no matches.
- Searched all `*.rs` files for the string `antithesis`. There were no matches.
- Checked `Cargo.lock` for an `antithesis` crate. There were no occurrences, so the SDK is not a
  dependency of any workspace member.

The only Antithesis-related files are deployment and packaging files: `Antithesis_RUN/` (K8s
manifests and image push scripts) and the AWS-LC no-jitter build flag in `rebuild-and-redeploy.sh`.

## Implication

Every assertion proposed in this scratchbook is **missing** and must be added. For the one cataloged
property, all assertions belong in the workload, not the SUT.
