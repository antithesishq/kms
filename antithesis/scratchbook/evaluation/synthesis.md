---
sut_path: /home/exedev/kms
commit: 4a644c8546abc8b002b7e45c19bf195996e7d229
harness_commit: 3095d82afc277661a2d1629f8d31cc91bf4761f0
updated: 2026-10-17
external_references: []
---

# Property Evaluation — Synthesis

## Scope and mode

This was a single-agent evaluation of a **one-property catalog**, sized to the user's request ("find
1 black box property … do not generate a comprehensive property catalog"). All four lenses ran,
but their findings are recorded here instead of in separate `evaluation/{lens}.md` files, because
the per-lens evidence is a few lines each. Coverage Balance is judged against the user's scope,
not the usual ~15-property portfolio.

## Lens findings

### 1. Antithesis Fit — strong

- The property fails only under specific interleavings: restart mid-session, resubmit an ID whose
  derived session IDs collide with peer state, redo while a peer is `Completed`, and sync
  attaching to an in-flight async request. Random testing would rarely hit these, and Antithesis
  explores exactly this kind of interleaving.
- The oracle is exact (ground-truth plaintext) and cheap. False positives are unlikely: the
  deployed `Test` params have zero encryption noise (see the evidence file's investigation log).

### 2. Coverage Balance — limited by scope

- One safety property. There is no liveness counterpart, no user-decryption property, and no
  keygen or reshare property. That is the expected result of the user's scope, not an oversight.

### 3. Implementability — feasible, with two caveats

- The stock CLI collects only `num_majority` responses by default, or fails as a whole with `-a`
  when one core is down. It also repeats one value across `-b` batches. A small Rust driver on
  the `kms` client helpers is needed to evaluate every party's response individually and to use
  distinct values. This is recorded in the evidence file.
- A key must exist before the first decryption, so a `first_` command must run keygen. The time
  for `preproc-key-gen` + `key-gen` under Antithesis is unknown (sut-analysis Open Questions).

### 4. Wildcard

- **Result mix-ups.** A meta-store or session-ID bug could return request A's result for request B,
  or one batch slot's result for another. The plaintext check catches this only if values differ
  across requests and slots. The original draft did not require that.

## Categorized findings and actions

| # | Category | Finding | Action taken |
|---|---|---|---|
| 1 | Refinement | Values must be distinct per request and per batch slot, or the oracle misses result mix-ups (wildcard) | **Applied:** added to the catalog's Antithesis Angle and to the evidence file's workload sketch |
| 2 | Refinement | The CLI is unsuitable as the driver (majority-only collection, `-a` fails as a whole, `-b` repeats a value) | **Applied:** the evidence file specifies a Rust driver and cites the helper functions |
| 3 | Refinement | False-positive risk from FHE noise under `Test` params | **Resolved:** investigated; no noise (`t_uniform(0)`), so no tolerance is needed (evidence file investigation log) |
| 4 | Gap | No liveness counterpart. Without one, a run where every decryption fails under faults gets no "availability" signal, though the `Always` reachability requirement still catches a run with zero successes | **Deferred per user scope.** Listed under the catalog's file-level Open Questions |
| 5 | Gap | User decryption (share reconstruction with `num_reconstruct = 3`) is also black-box checkable and has more client-side logic | **Deferred per user scope** |
| 6 | Bias | Property selection leaned toward public decryption because the CLI already has an encrypt-then-check path, which makes the property cheap to implement. Keygen agreement and restart/recovery may hold more bugs but cost more to build | **Presented to the user** in the run summary |

## Fresh-context review (applied)

A separate reviewer with fresh context checked about 20 citations against the code and found
these issues. All of them have been applied.

| # | Category | Finding | Action taken |
|---|---|---|---|
| 7 | Refinement (high) | Reusing a request ID with new ciphertexts gives a false positive. The core assumes a known ID carries the same ciphertexts, and `PublicDecryptSync` attaches to the old entry and returns the old plaintexts (`ARCHITECTURE.md:50`) | **Applied:** the Invariant, the Angle and the sketch now require a byte-identical resend with the original expected plaintexts |
| 8 | Refinement | Gating on full request-bound validation hides mix-ups between requests | **Applied:** the gate is now the payload signature only, and `payload.request_id` is checked explicitly (`kms.v1.proto:407-421`) |
| 9 | Gap (open question) | Epoch orphaning after a restart (claimed by an earlier deployment kit's README, not in this repo) could make node faults disable cores permanently and leave the `Always` unreached | **Added** as an open question; a later code trace found no such path (`partial`, see the evidence file) |
| 10 | Refinement | Doc claims stated as fact, citation drift, `ebool` cannot give distinct values, and the "no false positive" result depends on `Test` params | **Applied** across sut-analysis, deployment-topology and the evidence file |

## Extension to five guarantees (2026-10-17)

The speedrun extended the catalog from one property to one per guarantee in
[guarantees.md](../guarantees.md): [recovers-after-faults](../properties/recovers-after-faults.md),
[reshare-preserves-key](../properties/reshare-preserves-key.md),
[user-decrypt-returns-encrypted-plaintext](../properties/user-decrypt-returns-encrypted-plaintext.md)
and [decrypt-request-id-retries](../properties/decrypt-request-id-retries.md). That closes gaps 4 and
5 above. No lens pass was rerun for them; the main implementability findings are in their evidence
files: the CLI connects to every core before sending, can't choose a request ID, and reports every
reshare failure as a panic; and Guarantee 2's 300 s window needs to be measured from the cores
accepting connections, with a separate 600 s bound.

## Open Questions

- None beyond those in the catalog, the SUT analysis, and the deployment topology.
