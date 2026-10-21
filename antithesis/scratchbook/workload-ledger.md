# Workload Ledger

Coverage-driven workload in [`antithesis/test/v1/main/`](../test/v1/main/), built tier by tier
from [api-surface.md](api-surface.md). One row per local iteration and one per Antithesis run
(format: `antithesis-coverage-workload`, measuring-progress.md).

| # | Date | Change | Active tiers / groups | Local: new lines / functions | Antithesis run | Antithesis: edges (Δ) | Notes |
|---|---|---|---|---|---|---|---|
| 1 | 2026-10-19 | Initial Tier 0 drivers (8) plus first_ keygen; Guarantee 1/2/4 assertions | 0 | baseline: 11,961 lines / 2,125 functions in 248 files (3 seeds × 480 s, merged; seeds 11,714–11,961 lines) | — | — | every Tier 0 op mostly `ok`; no false Always/Unreachable; 4 non-zero exits per run are drivers the composer stops at the end; seed-to-seed noise up to ~250 lines / ~30 functions |
| 2 | 2026-10-19 | — | 0 | — | `26624b2b5f2d8a978be1469b0141857c-64-4` (60 min, advanced_k8s_test, default faults, client and MinIO spared from pod stop/kill, 16 GiB VM) | none: the tenant's `advanced_k8s_test` didn't export coverage yet (`.results.coverage` absent); enabled 2026-10-20 for later runs | all catalog properties pass (4 Always, 1 Unreachable, 9 Reachable, 6 Sometimes); every command exits 0; only failures are the known fail-fast exits of kms-core and kms-core-init-gen-keys when MinIO is unreachable (false-positives.md), checked in one log each. A first launch, `d2986be4…-64-4`, failed at setup because the images had not been pushed (`make push`) |
| 3 | 2026-10-20 | — (rerun of row 2) | 0 | — | `c7dcf08a77927e5d6a1a6eaf7610b240-64-4` (same length, parameters, images and workload as row 2) | baseline: 5,801 edges; 1,283 functions, 2,554 lines in 127 repo files (kms-server, kms-core-client, kms-init, kms-gen-keys) | the Antithesis baseline, first run with the coverage export. 52 properties pass. Failing: Guarantee 2's "public decryption answered by all four cores succeeds within 300 s…" (35 of ~2,670) and its command's exit code, a SUT finding (Status, 2026-10-20); kms-core exit 1 and kms-core-init-gen-keys exit 1 (known fail-fast); kms-core exit 101, a panic binding port 50100 ("Address already in use") while a core restarted after a pod fault |
| 4 | 2026-10-20 | iter01: all of Tier 1: `pubdec.sync`, `userdec.sync` (async and sync drivers share `helper_decrypt.py`), `keygen.abort` (gRPC, by preprocessing ID); the two sync-endpoint markers declared again; `pick_key` prefers keys every core holds | 0, 1 | +19 lines / +9 functions (11,980 / 2,134 merged; seeds 11,733–11,946): `PublicDecryptSync`, `UserDecryptSync`, `AbortKeyGen` (not-found path) | — | — | no abort met a running keygen in these 3 seeds, so the cancel path is unreached. A first version without the `pick_key` change (iter01a, +181 / +36) did meet some: its aborts reached the cancel path, and the keys they left on only some cores reached the key-missing and failed-decryption redo paths, but decryptions under those keys timed out at 300 s and halved one seed's driver runs. No false Always/Unreachable in either; every sync driver run `ok` except no-verdict ones under a just-created key |
| 5 | 2026-10-20 | iter02: short sequence `parallel_driver_keygen_abort_running.py` (insecure keygen in the background, AbortKeyGen to all cores or one 0.5–2.5 s later), for the keygen cancel path that a standalone abort reaches only by chance (`inner_abort_key_gen` finding the keygen, `key_gen_background`'s "Key generation was aborted"); it may go 2 keys past `MAX_KEYS`. `start_cli` writes the CLI's output to a file | 0, 1 | +164 lines / +31 functions over iter01 (12,144 / 2,164 merged; seeds 11,833–12,132): the cancel path, and through the keys aborts leave on some cores, the key-missing reads in the vault and decryptors and the meta-store redo of a failed decryption ID | — | — | kept. Aborts that cancelled a keygen: 23, 10, 17 per seed. No timeouts, no false Always/Unreachable. A first version gated at `MAX_KEYS` + 1 keys (iter02a) skipped 65 of 66 runs and cancelled one keygen |
| 6 | 2026-10-20 | — (Antithesis run of rows 4–5) | 0, 1 | — | `7ad203f37b3bfe439364933a26f8bb44-64-4` (60 min, same parameters and images as row 3) | 5,930 (+129 over row 3); 1,303 functions (+20), 2,587 lines | first run with Tier 1. 57 properties pass, both sync-endpoint markers among them. Failing: the same Guarantee 2 finding (40 counterexamples, core 3 in degraded mode after a context read failed at boot), with its command's exit code; the known fail-fast exits; and the Sometimes "a core the client could not connect to after faults stopped accepted connections again", never evaluated in this run (no recovery check met a core refusing connections; it passed in rows 2 and 3), so it depends on fault timing |
| 7 | 2026-10-20 | iter03: Tier 2 `reshare` group: `parallel_driver_epoch_reshare.py` (new-epoch from the kms-init epoch or a confirmed reshared one, at most `MAX_EPOCHS` = 6 epochs), `parallel_driver_epoch_get_result.py` (gRPC); decryptions pick an epoch per call (`pick_epoch`: default 2/5, confirmed 2/5, unconfirmed 1/5); Guarantee 3 and the reshared-epoch markers of Guarantees 1 and 4 declared again (all 33 catalog assertions now) | 0, 1, 2 (`reshare`) | +2,329 lines / +585 functions over iter02 (14,471 / 2,745 merged; seeds 14,188–14,471): the epoch manager, the reshare protocol (`online/reshare.rs`, `endpoints/reshare_sk.rs`), PRSS and offline phases, `reshare_utils.rs` | — | — | kept. 6–8 reshares per seed, all done; every Guarantee 3 check true; chained reshares in 2 of 3 seeds; decryptions under reshared epochs 30–74 per seed, all correct. The cap is reached within minutes, after which the driver skips. 3 decryption timeouts in one seed, all under the kms-init epoch with keys an abort left on some cores (the 10 % any-key branch) |
| 8 | 2026-10-20 | iter04: `parallel_driver_epoch_reshare_rejected.py`: reshare requests that must fail (wrong key digest, wrong preprocessing ID, unknown source epoch, the kms-init epoch as the new epoch), no Guarantee 3 checks; the first three leave a PRSS-only epoch, so at most 3 of them (`epochs-rejected/`); `epoch.get_result` also asks for those | 0, 1, 2 (`reshare`) | +149 lines / +9 functions over iter03 (14,611 / 2,752 merged; seeds 14,175–14,585): digest and preprocessing-ID verification in `reshare_utils.rs` and `material_integrity.rs`, the rejection paths of `new_mpc_epoch` | — | — | kept. Every such request failed (`INVALID_ARGUMENT`, a few `INTERNAL` from the background check); none was accepted. No false Always/Unreachable |
| 9 | 2026-10-20 | iter05: `helper_common.lifecycle`: keygens and keygen aborts never overlap a reshare (the proto's caller rule); a reshare that didn't finish holds the lock until no core reports the epoch in progress | 0, 1, 2 (`reshare`) | −48 lines / −10 functions against iter04 (14,563 / 2,743 merged; seeds 14,174–14,554), none gained: the lost code is the redo of a failed public decryption ID, which needs a decryption under a partial key and a sync re-send, so it comes and goes with chance | — | — | kept: required so that no failure comes from breaking the API's caller rules. No driver ever waited out the lock (no `skipped=…running`); reshares 6–8 and cancelled keygens 9–13 per seed as before. No false Always/Unreachable |
| 10 | 2026-10-20 | — (Antithesis run of rows 7–9) | 0, 1, 2 (`reshare`) | — | `2675775a5a08f47c69dfa815080f0252-64-4` (60 min, same parameters and images as row 3) | 7,075 (+1,145 over row 6); 1,518 functions (+215), 3,019 lines in 142 files | first run with the `reshare` group. 71 properties pass, all of Guarantee 3 among them, its fault-only markers too (1,904 reshares without a verdict; 138 chained reshares; 380 public and 194 user decryptions under reshared epochs, all correct). Failing: the same Guarantee 2 finding (15 counterexamples, "Only got 3/4 … responses") with its command's exit code, the known fail-fast exits, and kms-core exit 101 (6, the port-bind panic of row 3). The `rejoined` Sometimes that row 6 missed passed |
| 11a | 2026-10-20 | iter05b: no change to the workload; the coverage build now instruments only the repo's crates (`images/coverage-rustc.sh`), re-measuring iter05's drivers on it | 0, 1, 2 (`reshare`) | 14,142 / 2,699 merged (seeds 14,057–14,139), the new reference: against iter05 −421 lines / −44 functions, none gained. ~2,800 driver runs per seed instead of ~800, but keygens got ~6x faster (DKG 321 ms, it was 2.1 s), so aborts stopped meeting running keygens (0–1 per seed, 9–13 before) and none of the few keygens under the cap drew `-u`: the lost code is the keygen cancel path and the uncompressed-keygen path | — | — | the earlier rows' local numbers come from the slower, fully instrumented build |
| 11 | 2026-10-20 | iter06: Tier 2 `crs` group: `crs.start` (ceremony; one at a time, at most 2 per run, else a `max_num_bits` the cores reject), `crs.start_insecure` (at most `MAX_CRS` = 6), `crs.get_result`, `crs.get_insecure_result`, `crs.abort` (gRPC); generation and abort hold the lifecycle group "generate" | 0, 1, 2 (`reshare`, `crs`) | +1,000 lines / +221 functions over iter05b (15,142 / 2,920 merged; seeds 15,118–15,133): `zk/ceremony.rs`, `crs_generator.rs`, the CRS parts of `base.rs`, `central_kms.rs` and `crypto_material/base.rs`. On the old, fully instrumented build CRS generation ran 65–70x slower (an insecure CRS 269–468 s against 4–7 s) and starved every driver (20–106 runs per seed), which led to the build change in row 11a | `3af8ebda5530e028068fb363365282f5-64-4` (60 min, same parameters and images as row 3) | 7,667 (+592 over row 10); 1,644 functions (+126), 3,223 lines in 148 files: `crs_generator.rs`, `zk/ceremony.rs`, `crsgen.rs` new | on the normal build the same workload ran 254 commands in 4 minutes with no false Always/Unreachable. A secure ceremony keeps every core's CPUs busy ~70 s whatever `max_num_bits` is; two at once take ~110 s and both succeed ; on Antithesis 76 properties pass, every crs driver exits 0, and Guarantee 2's Always passed: all 1,557 recovery checks decrypted on their first attempt. So its two Sometimes ("…accepted connections again", "…succeeded after a failed first attempt…") were never evaluated and fail; also the known container exits (exit 1, and the exit-101 port-bind panic, 7) |
| 12 | 2026-10-20 | iter07: `parallel_driver_keygen_abort_running.py` retimed for the 0.3 s keygens of the faster builds (abort 0.2–1.5 s after the CLI starts), `-u` 1 time in 4, and its own budget (at most 12 keygens per container, none past `MAX_KEYS` + 6 keys) instead of the shared cap, which the keygen driver fills within a minute | 0, 1, 2 (`reshare`, `crs`) | +434 lines / +51 functions over iter06 (15,576 / 2,971 merged; seeds 15,426–15,569), none lost: the keygen cancel path and its meta-store error update, the uncompressed keygen (`compute_info_uncompressed_keygen`, `gen_uncompressed_key_set`) and resharing an uncompressed key (`VerifiedPublicMaterial::new_uncompressed`, server-key digest checks) | — | — | kept. 9–12 aborts per seed met a running keygen. Driver runs fell to 1,298–1,830 per seed (2,600 in iter06): the keys aborts leave on some cores cost 1–2 decryption timeouts per seed. No false Always/Unreachable. A first version that only changed the delays (iter07a) still gated on the shared cap: 126 of its 129 runs skipped |
| 13 | 2026-10-20 | — (Antithesis run of row 12) | 0, 1, 2 (`reshare`, `crs`) | — | `5b02a1fef023c96697ddc3fd67fba501-64-4` (60 min, **turbo** tier, otherwise as row 3) | no coverage export (`.results` holds only `environment`) | 76 properties pass. Failing: Guarantee 2's "every core accepts client connections within 600 s after faults stop" (65 counterexamples) and its command's exit code, a false positive the workload caused (Status, 2026-10-20 turbo); the known fail-fast exits (exit 1: 2,041). Not usable as the turbo reference: the next turbo run is |
| 14 | 2026-10-20 | iter08: Tier 3 `material.list` and the `request-status` group (`metastore.get_statuses`, `metastore.list`, `metastore.info`), read-only gRPC with hand-encoded requests: pooled, unknown and malformed IDs, every store type and one that doesn't exist, status filters, page sizes around the 1000 cap, valid and unparsable page tokens | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`) | +269 lines / +148 functions over iter07 (15,845 / 3,118 merged; seeds 15,668–15,726): `metastore_status_service.rs` (150 lines), the meta-store listing accessors, key-material availability | — | — | kept. ~2,900 driver runs per seed; ~45 % of `metastore.list` calls are `INVALID_ARGUMENT` by design. No false Always/Unreachable |
| 15 | 2026-10-20 | iter09: `epoch.reshare` inputs not used yet: two keys in one request (1 time in 3), re-signing 1–2 CRSes when resharing from the kms-init epoch (half the time; digest over `PDAT_CRS`), a chained source's own keys; `MAX_EPOCHS` 6 → 12, since the faster build reached 6 within a minute; epoch records list all their keys | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`) | +91 lines / +18 functions over iter08 (15,936 / 3,136 merged; seeds 15,816–15,936), none lost: CRS verification and re-signing in a reshare (`reshare_utils.rs`, `epoch_manager.rs`), threshold crypto-material storage | — | — | kept. 12–13 reshares per seed, 2–3 of them with two keys, 1–4 re-signing CRSes; every Guarantee 3 check true |
| 16 | 2026-10-20 | iter10: fix for the turbo false positive of row 13: one CRS generation of either kind in flight (`exclusive("crs-generation")`), at most `MAX_CRS_REQUESTS` = 10 valid CRS requests per container, one reshare in flight, lifecycle waits 600/300 s → 120 s for keygen, abort and CRS drivers | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`) | +6 lines / +1 function over iter09 (15,942 / 3,136 merged): no loss from the limits | — | — | kept. 6 valid CRS requests per seed (2 ceremonies, 4 insecure), 12 reshares, 1–9 reshares skipped while another ran. No false Always/Unreachable |
| 17 | 2026-10-20 | — (Antithesis run of rows 14–16) | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`) | — | `97ed35045ae50ed898fdb0b28edc5889-64-4` (60 min, turbo, otherwise as row 3) | no coverage export, as in row 13 (turbo runs carry only `environment` in `.results`) | 82 properties pass: every catalog assertion, Guarantee 2's two fault-timing `Sometimes` too; the turbo connect false positive of row 13 is gone. Failing: only the known fail-fast exits (kms-core exit 1: 1,245; kms-core-init-gen-keys exit 1: 72). The degraded-mode finding didn't recur in this run |
| 18 | 2026-10-20 | iter11: Tier 3 `mpc-admin` epochs: `epoch.create` (PRSS-only, at most 3 alive and 8 made, 1 in 10 an existing ID), `epoch.destroy` (an epoch the workload made, a reshared one only while more than 2 are left, never the kms-init epoch; sometimes destroyed or unknown IDs). The proto asks callers not to destroy an epoch while requests on it run, so commands hold a shared lock on the reshared epoch they decrypt or reshare under (`epoch_in_use`) and the destroy driver takes it exclusively after moving the epoch out of the pools; new epochs (reshare, create) one at a time | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`, `mpc-admin` epochs) | +178 lines / +34 functions over iter10 (16,120 / 3,169 merged; seeds 15,992–16,112), none lost: epoch destruction in `epoch_manager.rs` and `session.rs`, the storage deletes | — | — | kept. 25–31 epochs destroyed and 7–8 created per seed; reshares went from 12 to 29–33 per seed, since destroyed epochs free the cap. Driver runs ~1,400 per seed (reshares take every core's CPU). No false Always/Unreachable |
| 19 | 2026-10-21 | iter12: epoch IDs in increasing order (`new_epoch_id` counter, taken inside `exclusive("new-epoch")`, which the rejected-reshare driver now holds too), as `NewMpcEpochRequest` requires | 0, 1, 2 (`reshare`, `crs`), 3 (`material.list`, `request-status`, `mpc-admin` epochs) | −7 lines / −1 function against iter11 (16,113 / 3,168 merged): noise | — | — | kept: required by the API. Every epoch ID sent came from the counter; 30–34 reshares, 26–32 destroys and 6–8 creates per seed. No false Always/Unreachable |
| 20 | 2026-10-21 | iter13 (input review, candidate 1): per-timeline variation. Drivers that undo each other run only in some timelines (`exit_unless_active`: destroy 50 %, aborts, rejected reshares, epoch create and CRS 60 %, keygen and reshare 80 %); per-timeline mixes for decryption epochs, request-ID noise (10/35/70 %), the largest batch (1, 3 or 6; was always ≤ 3) and uncompressed keygens (0/25/75 %) | 0, 1, 2, 3 | merged over 3 seeds: +27 / −172 lines against iter12 (15,968 / 3,142); per seed 13,088 (reshare and both CRS drivers off), 15,906, 15,903. Batches of 4–6 reached a little more of the networking code; insecure CRS generation was off in all three seeds (a 6 % draw), which lost the CRS paths | (turbo, row 21) | — | kept, on the review's reasoning: Antithesis starts many timelines from the setup snapshot, each drawing its own mix, which 3 local timelines can't show. Its Antithesis effect isn't measured, since turbo runs export no coverage. No false Always/Unreachable |
| 21 | 2026-10-21 | — (Antithesis run of rows 18–20) | 0, 1, 2, 3 | — | `43b322977f3b2643964277fc89f81dc9-64-4` (60 min, turbo, otherwise as row 3) | no coverage export (turbo) | 82 properties pass. Failing: Guarantee 2's "every core accepts client connections within 600 s after faults stop" (64) and its command's exit code: a SUT finding, a core bricked by a kill during a CRS write (Status, 2026-10-21); and the known fail-fast exits |
| 22 | 2026-10-21 | iter14 (input review, candidate 4): `parallel_driver_crs_abort_running.py`, start a CRS generation (insecure 7 in 10), find its ID with `ListRequests` (PROCESSING) and abort it: every core, or one core for an insecure one; own budget of 3 per container. Ceremony client timeout 900 → 300 s | 0, 1, 2, 3 | measured on seeds 4–6 (seeds 1–3 drew it off or out of budget), so against iter13 the numbers mix two changes and two seed sets: +151 / −385 lines (15,734 / 3,129 merged; seeds 13,754–15,402). Reached: the CRS cancel path (`crs_generator.rs` +33, `zk/ceremony.rs` +41); lost: keygen paths, from seeds whose switches drew keygen off | — | — | kept. 5–12 aborts met a running generation and 3 ceremonies ended `ABORTED` in the seeds where it ran. A first version also aborted ceremonies on a single core: the others then waited for the ceremony's network timeout while holding the lifecycle lock, and one seed fell to 625 driver runs. With per-timeline switches, one local seed is one timeline, so 3 seeds are a small sample |
| 23 | 2026-10-21 | — (Antithesis run of row 22) | 0, 1, 2, 3 | — | `b7a1b803dbad5907bb76f702d020f8e8-64-4` (60 min, turbo, otherwise as row 3) | no coverage export (turbo) | 85 properties pass, every catalog assertion among them, the CRS abort sequence's commands too. Failing: only the known container exits (kms-core exit 1: 1,118; exit 101, the port-bind panic: 21; kms-core-init-gen-keys exit 1: 101) |
| 24 | 2026-10-21 | — (row 22's workload, commit `cbf829e4`, under aggressive faults) | 0, 1, 2, 3 | — | `d5c566152d1bb8181af3254cd895fb3c-64-4` (60 min, turbo; pod stop and kill every ~120 s each, strobing 60 s chaos / 30–90 s quiet, timing fuzzing) | no coverage export (turbo) | asked by the user, to look for wrong decryptions: with n = 4 and t = 1, one faulty core is masked by design, so a wrong result needs two cores inconsistent at once. None found: 85 properties pass, every plaintext and reshare check among them (19,659 public and 11,759 user decryption plaintext checks, 1,065 / 645 under reshared epochs, 1,810 reshare results, 2,085 public-key checks, authentication failure unreached), and Guarantee 2 too. The faults bit harder than row 23's: reshares without a verdict 276 (131), recovery hard cases 118 rejoined and 153 retried (47, 61); fewer decryptions without a verdict (2,668 against 6,878), the strobe's quiet windows letting the cluster settle. Failing: only the known container exits (exit 1: 972; exit 101: 29; init exit 1: 67) |
| 26 | 2026-10-21 | — (12 h bug hunt, at the user's request: row 22's workload, commit `cbf829e4`, the newest one validated on Antithesis, under row 24's aggressive faults) | 0, 1, 2, 3 | — | `1aa9f98df97398fabc1b8e4ca66a0daa-64-4` (720 min, turbo; pod stop and kill every ~120 s each, strobing, timing fuzzing) | pending | |
| 25 | 2026-10-21 | iter15 (input review, candidate 3): per-container budgets paced per timeline (`paced`: all at once, or one slot every 120 or 300 s) for keys, keygen abort runs, CRS requests, CRS abort runs and PRSS epochs; the PRSS-epoch budget no longer counts live epochs twice | 0, 1, 2, 3 | +389 / −15 lines over iter14 (16,108 / 3,170 merged; seeds 13,305–15,797, a wide spread from the per-timeline switches) | — | — | kept. Generation still happens in every seed (4–9 keygens, 3–6 insecure CRS, 3–12 cancelled keygens, 8–12 cancelled CRS generations). No false Always/Unreachable. The gain locally is small by nature: the change is for Antithesis branches that start late in a run |
| 27 | 2026-10-21 | iter16 (input review, candidate 5): keygen from an existing keyset (`--existing-keyset-id`, half the time `--use-existing-key-tag`, 3 in 10 compressed ones `--copy-compressed-key-to-original`), in a per-timeline share of keygens (0/20/50 %), with its own budget of 3 fresh preprocessing IDs per container. The reshare driver now reads the public keys inside its lifecycle lock: a copy-back replaces an existing key's public material, and outside the lock that could fail Guarantee 3's check on a correct system | 0, 1, 2, 3 | +436 lines over iter15 (16,398 / 3,191 merged; seeds 15,413–15,938): rebuilding a keyset from existing shares (`tfhe_internals/test_feature.rs` +278, `key_generator.rs` +101), `keyset_configuration.rs` | — | — | kept. 3 existing-keyset keygens in one seed: the compressed one succeeded, the two uncompressed ones ended `INTERNAL` as documented ("only supported for compressed keysets"). Checked by hand: all three flag combinations succeed, and after a copy-back, public and user decryptions under the original key still return the encrypted values. No false Always/Unreachable. Two earlier versions reached nothing: one sent the flags on spent preprocessing IDs (they fail first), one only on fresh ones within the key cap (too few) |
| 28 | 2026-10-21 | — (Antithesis run of rows 25 and 27, commit `a34e1371`) | 0, 1, 2, 3 | — | `4d31ac7b71d37b2cf0e6f8e8ac0fb146-64-4` (60 min, turbo, default faults) | no coverage export (turbo) | validation before long runs. 83 properties pass. Failing: Guarantee 2's "public decryption answered by all four cores succeeds within 300 s…" (50) and its command's exit code, a suspected SUT finding, not caused by the workload (Status, 2026-10-21, stall after a core restart); the known container exits (exit 1: 1,836; exit 101: 26; init: 122). So rows 25 and 27 add no false positive |
| 29 | 2026-10-21 | iter17 (input review, candidate 2): keygens and CRS generations in a PRSS-only or confirmed reshared epoch, in a per-timeline share (0/20/40 %; `generation_epoch`), with their own budgets (3 keygens, 2 insecure CRSes per container). Keys and CRSes record their home epoch; decryptions use a key's home as its default epoch, reshares start from it, existing-keyset keygens and CRS re-signing stay within one epoch, and the recovery check only uses keys born in the kms-init epoch (a key born in a destroyed epoch would otherwise fail Guarantee 2 on a correct system) | 0, 1, 2, 3 | +312 lines over iter16 (16,690 / 3,236 merged; seeds 15,001–16,434; seeds 4–6): key material stored under other epochs (`crypto_material/threshold.rs` +120), `key_generator.rs`, `epoch_manager.rs`, signing | — | — | kept. 7–9 completed keygens per seed, 2 valid CRS generations in other epochs in two seeds. No false Always/Unreachable. A first version (iter17a, seeds 1–3) shared the key and CRS budgets, which are spent before other epochs exist: only spent or invalid requests went to other epochs |
| 30 | 2026-10-21 | — (Antithesis run of row 29, commit `2fe3d48a`) | 0, 1, 2, 3 | — | `d33556309d1fea4d9cba0efbf83769a3-64-4` (60 min, turbo, default faults) | no coverage export (turbo) | validation before long runs. 82 properties pass. Failing: both Guarantee 2 Always and the recovery command's exit code, each traced to the SUT, not the workload (Status, 2026-10-21: a key migration that splits a key's shares, and row 21's CRS-write brick, this time on the keygen path); the known container exits (exit 1, exit 101, init exit 1). So row 29 adds no false positive |

## How this workload differs from the skill's defaults

These were the user's instructions when the workload was started (2026-10-19):

- **No log sidecar.** The harness topology stays as it was; `antithesis-coverage-setup` was not
  run as a whole. Only its local coverage build and `local/run-local.sh` were added later
  (see [coverage-setup.md](coverage-setup.md)). `antithesis/local/test.sh` still runs every
  command in the client pod as a quick check, without coverage.
- **The property catalog stays in the workload**, since there is no sidecar to hold reducers.
  [property-catalog.md](property-catalog.md) is unchanged: no property added or removed. Its
  checks are SDK assertions in [`helper_properties.py`](../test/v1/main/helper_properties.py),
  evaluated by the commands whose operation gives a verdict. The drivers themselves stay
  check-free. Message texts are unchanged, so [assertion-map.json](assertion-map.json) and old
  triage reports still match.
- **A check is declared only while a driver can reach it.** A must-hit assertion that no
  driver can reach would fail every run, which is a false positive. So the following came
  back with their operations (assertion-map.json listed them with `status` until then):
  - Guarantee 3 (`reshare-preserves-key`), all of it, and the reshared-epoch markers of
    Guarantees 1 and 4: back with the `reshare` feature group (Tier 2, 2026-10-20), ported
    from the shell harness's `anytime_reshare_key.sh` as a parallel driver (the skill has no
    `anytime_` commands). Its fault-only markers ("key reshare attempt ended without a
    verdict" and the two `Sometimes` judged after one) were reached thousands of times in
    every 120–180 min shell-harness run on Antithesis, so they are safe as must-hit.
  - "public decryption succeeded through the sync endpoint" and "user decryption succeeded
    through the sync endpoint": back with the `pubdec.sync` and `userdec.sync` drivers
    (Tier 1, 2026-10-20). They are judged by the same code as the async drivers
    (`helper_decrypt.py`), so a sync success also passes the plaintext checks.
  - Guarantee 5 stays not implemented, as in the catalog.
- **Commands kept beyond plain drivers:** `first_generate_key.py` (one-time keygen without
  faults, so decryption has a key from the start; it also evaluates the "workload generated
  an FHE key" marker) and `eventually_recovers_after_faults.py` (Guarantee 2, which needs an
  eventually_ command). Its probe uses `--sync` half the time, as the catalog's invariant says,
  so it reaches `PublicDecryptSync` before Tier 1 does.
- **Keys.** `first_generate_key.py` makes one key with no faults; `keygen.start_insecure`
  makes more during the run, up to `MAX_KEYS` = 3 (a soft cap: concurrent drivers can pass it).
  Keys add memory and boot time to every core, and boot time counts against Guarantee 2's
  600 s window. The recovery check uses only a key that all four parties published,
  preferring the first one: the CLI accepts a keygen that two cores finished, so a driver's
  key can be missing from a core for good, and probing it with `-a` would fail Guarantee 2 in
  a correct system. Since `keygen.abort` (Tier 1) that happens often: an abort that reaches
  some cores while the keygen runs leaves a key the others never finish. Decryptions under
  such a key wait out the 300 s MPC timeout, so the decryption drivers pick a key every core
  holds 9 times in 10 (`pick_key`), and any generated key otherwise. `key_count` counts a key
  any party published. Known ways past the cap, all bounded: concurrent keygen drivers
  passing the check together; past the cap, `keygen.start_insecure` re-sends taken
  preprocessing IDs, and one whose earlier CLI failed before sending (connect or MinIO
  error) still starts a keygen; `parallel_driver_keygen_abort_running.py` starts at most 12
  keygens and none once `MAX_KEYS` + 6 keys exist, and those its aborts miss become keys.
  With the test parameters keys are small: the cores used 44–131 MiB with 3–5 keys.
- **The proto's caller rules.** `core/grpc/proto/kms-service.v1.proto` says no `KeyGen`,
  `AbortKeyGen`, `CrsGen` or `AbortCrsGen` may run while `NewMpcEpoch`, `DestroyMpcEpoch` or
  `DestroyMpcContext` does, and the server doesn't enforce it. A failure from such an overlap
  would be a false positive by contract, so since iter05 `helper_common.lifecycle` keeps the
  two groups apart in the client container: the keygen and keygen-abort drivers hold group
  "generate", the reshare drivers group "epoch"; calls within a group may overlap (reshares
  with reshares are allowed). A reshare that didn't finish keeps the lock until no core reports
  the epoch in progress (at most 300 s), since the cores go on after the CLI gives up. Not
  covered: a keygen the CLI gave up on (timeout) that still runs on a core. `InsecureKeyGen`
  isn't named by the insecure proto; it shares the keygen machinery, so it is treated like
  `KeyGen`. iter03 and iter04 were measured before this, with the overlap.
- **Epoch IDs in order.** `NewMpcEpochRequest` (kms.v1.proto) requires every new epoch ID to be
  greater than the previous one (big-endian), and a core picks a key's and a CRS's latest epoch
  by ID at boot. Until iter12 the workload drew epoch IDs at random, so about half broke that
  rule (found by the input review). Since iter12 they come from a counter (`new_epoch_id`) and
  are taken inside `exclusive("new-epoch")`, which every driver that creates an epoch holds, so
  requests reach the cores in ID order. Requests that must fail use `unknown_epoch_id`.
- **Recovery check without a probe key.** If no key is published by all four parties (the
  first key needs only two cores to finish, so a fault during `first_generate_key.py` could
  leave it on fewer), the recovery check exits without evaluating its assertions. Their
  must-hit flags would then fail the run only if that happened in every eventually phase.
  Not seen so far.
- **Secure keygen is out of scope** (the customer doesn't test it in Antithesis), so the shell
  harness's `KMS_WORKLOAD_KEYGEN=secure` option is gone.
- **Retries.** The decryption drivers make 1–3 calls with fresh inputs each, and keep going
  after a success. The shell retried the same value and stopped at the first success. The
  retry and failover `Sometimes` are judged the same way: on a call that follows a call
  without a verdict, or that leaves out a core the previous call couldn't connect to.
- **Assertion counts.** The Python SDK emits only the first pass and the first fail of each
  assertion per process, so triage shows fewer evaluations than the shell harness did for the
  same work. Verdicts are unaffected.
- **Python in the client image.** `antithesis/images/python.Dockerfile` adds Python 3.13,
  `antithesis==0.4.0` and `grpcio==1.84.0` to the core-client image (the only harness change).
  The SDK writes through libvoidstar if the container has it, else to
  `$ANTITHESIS_OUTPUT_DIR/sdk.jsonl`, the fallback file the shell harness used.

## Status

- 2026-10-21, SUT finding in `d3355630…` (Guarantee 2, decryption bound; high confidence): a
  key migration (`copy_compressed_key_to_original`) leaves the parties with shares from
  different re-sharings of the same key, so the key can never be decrypted again. Each
  migration re-shares the existing secret (party 1 reconstructs it) and then, on each core
  separately, replaces the original key's `FheKeyInfo` and `CompressedXofKeySet` with the new
  ones (`key_gen_background`, `key_generator.rs:1713`; shared by `KeyGen` and
  `InsecureKeyGen`). A core whose copy fails only logs "…committed successfully, but the
  follow-up copy to original key id … failed … must be retried", and nothing reconciles the
  cores. In the counterexample (input_hash 720574761797369932, vtime 1138.45) two migrations
  of the probe key `af75…` ran (`5275…` and `b1d9…`, client commands at vtime 242 and 284):
  core 1 copied the first and then failed the second ("Unencrypted load failed: streaming
  error", a network fault); core 4 failed the first ("could not claim meta-store entry …
  locked", the other migration held it) and copied the second; core 2 copied both; core 3
  was stopped at vtime 400, mid-keygen, and copied neither. So the shares of `af75…` came from
  three different sharings (1: first, 2 and 4: second, 3: original). With n=4, t=1, robust
  open needs three consistent shares. After faults stopped, all four cores connected and
  every decryption under `af75…` failed in `RobustOpen` for 300 s ("Gao decoding failure …
  Could not reconstruct the sharing"; 0/4 responses). Either migration alone, with the same
  faults, would have split the cores 2 to 2. No wrong plaintext can come out of this
  (decoding fails rather than mis-decodes), but the key is lost to the protocol, and the
  old shares are overwritten on three cores. The proto allows this: it doesn't forbid
  concurrent migrations or describe partial failure. The same key decrypted fine at vtime
  397, before the copies. This failure will dominate Guarantee 2 in timelines where it
  happens: the probe key is the first key, which the existing-keyset keygen also picks.
- 2026-10-21, the CRS-write brick of `43b32297…` (below) also hits keys. In `d3355630…`
  (input_hash -4703883254626317498, vtime 1148.76) core 1 was killed (node stop, vtime 453.3)
  while it stored key `6bdc…`: its `FheKeyInfo` write had started, its `PublicKey` write
  hadn't logged. From then on every boot (15 starts) failed "storage verification failed:
  missing or unreadable public material PublicKey for id=6bdc… Byte load failed", even
  after faults stopped, and the recovery check never connected to party 1. Repair from
  peers can't work in this deployment: `DEFAULT_MPC_CONTEXT` is rebuilt at every boot with
  an empty `public_storage_url` for every node, by design ("We do not know the storage URLs
  in the default context", `context_manager.rs:700`), so "Cannot access public storage of
  peer N: no public storage URL recorded for this node". A context created with
  `NewMpcContext` and real URLs would try the repair, which needs the harness's
  `context.create` (blocked, see 2026-10-20).
- 2026-10-21, platform note from `d3355630…`: in input_hash 720574761797369932 a node fault
  (`node/stop` of kms-core-4, vtime 857.88) came 21 s after the fault injector paused for the
  eventually phase (vtime 836.03). It didn't cause that failure (the key was already split),
  and a restart that early fits Guarantee 2's bounds, but the quiet window isn't absolute.
- 2026-10-21, SUT finding in turbo run `43b32297…` (Guarantee 2, connect bound): a pod kill
  during a CRS write leaves a core that can never boot again. Core 3 began storing insecure CRS
  `e9ec2c14…` at vtime 309.7 (`PRIV-p3/CrsInfo/08…01/e9ec…` written), was killed at 310.2,
  and from then on every boot (22 starts, past the end of the run) failed: "storage
  verification failed: missing or unreadable public material CRS for id=e9ec… … Byte load
  failed", and the fallback "public material could not be synced from peers … no public
  storage URL recorded for this node". `write_data_pair` (core/service/src/vault/storage/
  crypto_material/base.rs) writes the public and the private object at the same time
  (`tokio::join!`), with no order or rollback, and boot treats a CrsInfo without its public
  CRS as fatal. `write_crs` serves the secure ceremony too. Not a workload false positive:
  no caller rule was broken (no epoch change ran; CRS generation was one at a time).
- 2026-10-21, suspected SUT finding in `4d31ac7b…` (Guarantee 2, decryption bound; medium
  confidence, no root cause yet): decryptions stall on a core that just restarted, although
  the code under test has upstream's fix for that (`a51d30be`, HTTP/2 keepalive, #887). In the
  counterexample (input_hash 4452306308432722739, vtime 861.47) kms-core-4 restarted at vtime
  562, as the eventually phase began, and booted normally (no recovery or degraded mode). The
  recovery check connected to every core at once, then its 3 attempts (561, 661, 761) each
  timed out at 90 s: cores 1–3 completed all 3 sessions, kms-core-4 started all of them and
  completed none. That is the signature of the speedrun's control, `decryption-stalls-after-
  core-restart` (rca/), where peers kept dead connections to the restarted core; with the
  keepalive they should reconnect within seconds. The peers log nothing about connections at
  INFO level, so the logs can't show the mechanism. Not the workload: no existing-keyset
  keygen ran in that timeline, and unlike `recovery-check-attempt-outlives-timeout` the other
  cores kept working. Next: the multiverse debugger at that moment (antithesis-debug), or
  more counterexamples from the 12 h run.
- 2026-10-21, relation to the speedrun's findings: the degraded-mode finding of `c7dcf08a…`
  (MPC contexts unreadable at boot → "degraded mode", `kms_impl.rs:864`) is the same class as
  `storage-error-enters-recovery-mode` (rca/), but a different read: that one is the signing
  key (`backup_operator.rs`), and its proposed patch touches only `backup_operator.rs`, so it
  doesn't cover the context path.
- 2026-10-21: input review (`antithesis-review-inputs`, after iter11). Candidates, in its order:
  (1) per-timeline enable masks and weights, so drivers that undo each other (reshare and
  destroy, abort and decrypt) don't always run together; (2) keygen, CRS and preprocessing
  under epochs other than kms-init's; (3) pace the per-container budgets (keys, abort runs,
  CRS requests, PRSS epochs) over the run instead of spending them in the first minutes, so
  later Antithesis branches still generate; (4) a CRS start-then-abort sequence (aborts now
  only meet finished CRSes); (5) keygen from an existing keyset (`--existing-keyset-id`,
  `--use-existing-key-tag`); (6) a few requests on destroyed, PRSS-only or rejected epochs, and
  some reshares without the source-epoch lock; (7) up to 2 new epochs at once in some
  timelines. It also found the random epoch IDs, fixed in iter12. Done: (1) iter13, (3) iter15,
  (4) iter14, (5) iter16, (2) iter17, (6) the part that sends decryptions to destroyed or
  PRSS-only epochs, iter18. Not done: (7), because the proto also wants epoch IDs in increasing
  order and the CLI sends and polls in one command, so two concurrent new epochs could reach a
  core out of order; and the part of (6) that drops the source-epoch lock, since destroying a
  reshare's source while the source check decrypts under it breaks the destroy caller rule.
- 2026-10-20: every operation of api-surface.md has a driver except those that need a harness
  change, which is the user's decision (not this skill's):
  - `context.create` and `context.destroy` (`mpc-admin`): the request is a safe-serialized
    `ContextInfo`, which only a `kms-core-client` built with the `testing` feature writes
    (`new-testing-mpc-context-file`); `new-mpc-context context-toml` is unimplemented. Destroying
    the default context would end every other check, so `context.destroy` waits for
    `context.create`.
  - the `backup` group (custodian contexts, operator key, recovery, restore): needs a
    `[backup_vault]` section in the core config, which the harness doesn't set.
- 2026-10-20: the Antithesis runs after row 11 use the `turbo` performance tier
  (`antithesis.performance_tier=turbo`), at the user's request, to find more issues. Those up
  to row 11 ran on the standard tier; edge counts compare only within a tier, so the first
  turbo run is the reference for the later ones.

- 2026-10-19: initial Tier 0 workload written and checked locally (`antithesis/local/test.sh
  check`, images `cded1193-dirty-20261019-2006`): every command exited 0; every Tier 0
  operation logged `ok` (keygen, preprocessing, both decryptions and their result RPCs); the
  errors were the intended edge-case IDs (`NOT_FOUND` for unknown or consumed IDs,
  `INVALID_ARGUMENT` for malformed ones). 20 assertions declared, 12 evaluated, none false.
  `snouty validate build/config` passes. The baseline is row 1 (local) and the next row (Antithesis).
- Low `ok` shares locally, all by design, to watch in the baseline:
  `preproc.get_insecure_result` 2 of 19 (consumed preprocessing IDs answer `NOT_FOUND`),
  `keygen.start_insecure` 3 of 6 (past `MAX_KEYS` it sends IDs that can't start a keygen),
  `pubdec.get_result` 6 of 20 (few pooled IDs early on, plus the edge-case IDs).
- 2026-10-20: before adding Tier 1, checked what Tier 0 code the local baseline never reached
  (zero-count lines in the Tier 0 operations' files) for anything a driver could reach by
  calling differently. Nothing the CLI can send:
  - the other FHE types (`euint4`, `euint512` … `euint2048`; the server also has `Uint80`):
    the CLI accepts them as `--data-type` but can't encrypt them (`TestingPlaintext` covers
    `ebool` … `euint256` only);
  - `DecryptionMode::BitDecSmall` in both decryptors: a server setting, not a request field;
  - request validation errors, key-not-found and verification-key errors: the CLI only builds
    valid requests for keys it downloaded;
  - meta-store eviction: needs more than `dec_capacity` = 10000 decryptions per core;
  - the request-ID reuse paths (`AlreadyExists`, redo of a Failed ID): the CLI has no
    request-ID option for decryptions;
  - most of `key_generator.rs` and `preprocessor.rs`: secure keygen, out of scope;
  - error paths after a failed MPC session: faults, so only in Antithesis.
  So the next step is all of Tier 1 (growing-workload.md, step 4).
- 2026-10-20: the decryption drivers' loop moved to `helper_decrypt.py` unchanged, so the
  async and sync drivers of each decryption share it and its checks.
- 2026-10-20, SUT finding in `c7dcf08a…-64-4` (Guarantee 2, not a workload false positive):
  core 4 restarted after a pod fault at vtime ~265 and, while it loaded its MPC contexts at
  boot, a network fault broke the MinIO read ("Unencrypted load failed: streaming error",
  `context_manager.rs:1063`). `kms_impl.rs:864` logs "Server will continue in degraded mode
  (recovery operations only)" and serves on without the context, and never reads it again.
  From then on it answered every `PublicDecrypt`/`PublicDecryptSync` with `NotFound`
  ("Context 07…01 not found") and rejected its peers' TLS ("not a trust anchor"), while the
  pod looked healthy. The recovery check started at vtime 344, connected at once, and failed
  all 29 attempts in 307 s with "Only 3/4 public decrypt requests succeeded". The probe key
  was the first key, published by all four parties. A transient storage error at boot is
  thus treated like a permanent one, with no exit for Kubernetes to restart and no retry.
  Other storage reads at boot fail fast (exit 1) instead.
- 2026-10-20, Guarantee 2's two `Sometimes` depend on fault timing. They are judged only when
  the recovery check meets a hard case: a core refusing connections when faults stop
  ("…accepted connections again"), or a failed first attempt ("…after a failed first attempt
  once faults stopped"). Over the four runs with coverage, the first was never evaluated in 2
  (`7ad203f3…`, `3af8ebda…`) and the second in 1 (`3af8ebda…`, where all 1,557 checks decrypted
  at once), so each must-hit `Sometimes` failed on a run where nothing was wrong. Changing that
  is a property change (e.g. not must-hit), left to the user.
- 2026-10-20, turbo run `5b02a1fe…`, workload false positive (Guarantee 2, connect bound):
  core 1 accepted no client connection for over 600 s after faults stopped, without any fault
  on it and without restarting. In Antithesis each core has one CPU ("total_num_cpus: 1",
  2 tokio workers). Turbo ran many drivers at once (the composer cancelled ~25 each of
  `crs_start_insecure`, `keygen_start_insecure` and `userdec_sync` when the eventually phase
  began), and core 1 received ~30 `InsecureCrsGen` requests within a minute; party 1 samples
  every insecure CRS alone, inside the request's async task, and the generations go on after
  their CLIs are killed. So core 1's CPU went to queued test-only CRS generations and it
  stopped serving. Fixed in the workload (iter10): one CRS generation of either kind in
  flight, at most 10 valid CRS requests per run, lifecycle waits cut to 120 s so drivers don't
  pile up. Worth telling the user: CPU-bound work on the server's async workers can starve its
  connection handling; with production operations that would be a real availability issue.

## Tried and didn't help

- iter18 (2026-10-21): decryptions sent to destroyed or PRSS-only epochs in a per-timeline share (0/3/10 %; input review, candidate 6). In 3 seeds not one such decryption happened (the draws came out 0 % or never fired), so it reached nothing; reverted. The decryption judges keep the stricter test of a reshared epoch (`epoch_status` confirmed or unconfirmed), which behaves the same without it.
