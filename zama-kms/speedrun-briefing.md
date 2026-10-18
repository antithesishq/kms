# Briefing: Zama · Zama KMS

<!-- Internal: for the customer-facing engineer who will turn this into a demo, a blog post or a
presentation. Never share this file with the customer. -->

**Status:** COMPLETE
**Dates:** 2026-10-17 15:53 UTC → 2026-10-18 11:00 UTC · **Skill:** speedrun v0.8 (state started under v0.7), variant baseline
**Budget used:** 16 runs (2 setup, 4 iteration, 9 hunts: 7 on the current version and 2 on the build before the fix, 1 fix check; the first setup run never started its tests) · run-hours 31.2 / 40 (sum of run lengths) · elapsed about 19 h, including a stop for a VM resize
**Customer report:** [speedrun-report.md](speedrun-report.md)

## The short version

Two headlines. First, a **new availability bug on the current version**,
[a storage error while a core boots leaves it in recovery mode](speedrun-report.md#storage-error-enters-recovery-mode):
a core restarted during a brief storage outage reads its signing key, gets a network error,
treats it as a lost key and boots into recovery mode, then refuses every decryption until someone
restarts it, while its health checks keep passing. One failing check (timing fuzzing on), the same
entry into recovery mode in a 4-hour run without timing fuzzing, an adversarial review that let it
stand, a blinded root cause, a small patch with a unit test, and the code is unchanged on the latest
`main`. Second, the [known-bug check](speedrun-report.md#known-bug-check): Zama's own September
2026 fix for restarted cores that can't rejoin (PR #887) was reverted, and Antithesis found the
bug in both 4-hour runs on that build (118 and 41 failing examples). The current version passed
the same check in every run with the same faults; its one failure, under timing fuzzing, is the new finding. The blinded root-cause pass reached the same mechanism and a fix
of the same kind as upstream, and its fix check passed ([digest](../antithesis/scratchbook/runs/fix-verify-1.md)).
Also: a boot crash on a port in use stays
[unconfirmed](speedrun-report.md#boot-panic-port-in-use). The caveats not to forget: the new
finding rests on one failing timeline; the cluster is miniaturised (4 parties, `Test` parameters,
insecure key generation, mock enclave); and only honest-but-faulty cores were tested, never
Byzantine ones.

## Sharing the report

- **Safe to share as is:** [speedrun-report.md](speedrun-report.md). Its relative links point to
  files that must travel with it, or the links break:
  - [antithesis/scratchbook/rca/decryption-stalls-after-core-restart.md](../antithesis/scratchbook/rca/decryption-stalls-after-core-restart.md)
  - [antithesis/fixes/decryption-stalls-after-core-restart.patch](../antithesis/fixes/decryption-stalls-after-core-restart.patch)
  - [antithesis/scratchbook/rca/storage-error-enters-recovery-mode.md](../antithesis/scratchbook/rca/storage-error-enters-recovery-mode.md)
    and [antithesis/fixes/storage-error-enters-recovery-mode.patch](../antithesis/fixes/storage-error-enters-recovery-mode.patch)
  - [antithesis/scratchbook/logs/unit-test-storage-error-enters-recovery-mode.txt](../antithesis/scratchbook/logs/unit-test-storage-error-enters-recovery-mode.txt), the fix's unit-test log, linked from the analysis
  - the new finding's [write-up](../antithesis/scratchbook/violations/storage-error-enters-recovery-mode.md) and
    [adversarial review](../antithesis/scratchbook/adversarial/storage-error-enters-recovery-mode.md), which the analysis links
  - [antithesis/scratchbook/runs/fix-verify-1.md](../antithesis/scratchbook/runs/fix-verify-1.md), linked from the known bug's analysis
  - [antithesis/patches/prefix/0001-revert-887-http2-keepalive.patch](../antithesis/patches/prefix/0001-revert-887-http2-keepalive.patch)
  - [antithesis/scratchbook/probes/boot-panic-port-in-use/tw-bind-check.md](../antithesis/scratchbook/probes/boot-panic-port-in-use/tw-bind-check.md) and the two scripts beside it
  - [speedrun-tests.md](speedrun-tests.md), which the report links for every command, and the
    test commands in [antithesis/test/](../antithesis/test/)
  - the manifests and image build files in [antithesis/config/](../antithesis/config/) and
    [antithesis/images/](../antithesis/images/)
  - [antithesis/scratchbook/false-positives.md](../antithesis/scratchbook/false-positives.md), which the report links once (the test-machine stall); read it before sharing, it's a working file.
  - **Deeper links:** the evidence files above link further into the scratchbook. For those
    links to work, also share exactly these, and nothing else from `antithesis/scratchbook/`:
    [runs/](../antithesis/scratchbook/runs/), the run evidence in [logs/](../antithesis/scratchbook/logs/)
    (`*.ndjson` histories, `props-*.ndjson`, `show-*.json`, `recovery-mode-*.json`, `unit-test-*.txt`,
    `same-workload*.txt`; not `doctor-*`, `local-*`, `build-*`, `launch-*`, `push-*` or `wait-*`, which
    describe the build host), [guarantees.md](../antithesis/scratchbook/guarantees.md),
    [properties/](../antithesis/scratchbook/properties/), the port-crash probe files
    ([probes/](../antithesis/scratchbook/probes/)), [positive-control.md](../antithesis/scratchbook/positive-control.md),
    [violations/](../antithesis/scratchbook/violations/) and [adversarial/](../antithesis/scratchbook/adversarial/).
    Never share `speedrun-state.json`, `speedrun-log.md`, `inputs.md`, `system-brief.md`,
    `sut-choice.md`, `evaluation/` or `antithesis/build/`: they hold budget, internal decisions,
    the build VM's name and another workspace's name. Read
    [false-positives.md](../antithesis/scratchbook/false-positives.md) and the
    [adversarial review](../antithesis/scratchbook/adversarial/storage-error-enters-recovery-mode.md)
    before sharing: they are working notes.
- **The report's run links carry access tokens.** Anyone with one can open that run's report.
  Remove them before publishing anything publicly.
- **Not for the customer:** this briefing and every scratchbook file not named in the sharing list above. The report mentions
  one unconfirmed finding, [the port crash](speedrun-report.md#boot-panic-port-in-use), labelled as
  such. It mentions the peak-memory warning only as a limit, because it's most likely our own
  workload's backlog. The report's log links need a tenant login: fine to leave in, but they won't
  open for the customer.
- **Disclosure:** the new finding is an availability bug in a security product, not public, and
  unchanged on the latest `main`. Send it to Zama privately (their [SECURITY.md](../SECURITY.md)
  process, or directly to the team) before any public mention. We found nothing to suggest it
  exposes keys: a core in recovery mode refuses to sign. The known bug is public and fixed
  ([PR #887](https://github.com/zama-ai/kms/pull/887)). The port crash is unconfirmed and isn't a
  security issue; it's an availability nuisance during restarts.
- **Licence:** Zama KMS is BSD 3-Clause Clear ([LICENSE](../LICENSE)). It puts no limit on
  publishing test results, but clause 3 forbids using Zama's name to endorse derived products
  without permission. Get Zama's agreement before naming them in marketing content.

## How confident we are

| Finding | Guarantee broken | Failing examples / runs | Adversarial verdict | Root cause | Fix check |
|---|---|---|---|---|---|
| [A storage error while a core boots leaves it in recovery mode](speedrun-report.md#storage-error-enters-recovery-mode) (new) | [Guarantee 2](speedrun-report.md#guarantee-2) | 1 / 1 (in [`4e338bff`](https://zama.antithesis.com/report/z0DpS4BEFi0AtQY_3k2xQYil/WNeeUiIs3qYUlUd7UAiS1YdNQh8HKvhl2ofzq82Afa8.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA3OjA0OjQzLjEwMjAyODEzMloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV05lZVVpSXMzcVlVbFVkN1VBaVMxWWROUWg4SEt2aGwyb2Z6cTgyQWZhOC5odG1sIiwicmVwb3J0X2lkIjoiejBEcFM0QkVGaTBBdFFZXzNrMnhRWWlsIn19fZI8ndKJGsf6_PbNOmcRvP7XRP6CnD-8mfcqZYL0UYS8iuH35ePerg9wy7HvBDKR8Y_jV7R5W-saZjsBZoGotAo); the same entry into recovery mode, never exercised, in [`8196fb3c`](https://zama.antithesis.com/report/RQ8Cbp-xGNyv2LzRK7QJhdaS/Q4j24Mga4r9vKq6G1GGKGJhmWP0f7ZtlCtPmgF4J-dU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUTRqMjRNZ2E0cjl2S3E2RzFHR0tHSmhtV1AwZjdadGxDdFBtZ0Y0Si1kVS5odG1sIiwicmVwb3J0X2lkIjoiUlE4Q2JwLXhHTnl2Mkx6Uks3UUpoZGFTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjUyOjUyLjkwNzU2NjUzOVoiffXOyyh90TorAK1eQ08RnDaqV3Hiuf4ZXbyxANa4Qh-8Ku_qk3g7JPpHFH0alZBWKDgpmQ1bzWKzpgv7_81JSwI)) | [stands](../antithesis/scratchbook/adversarial/storage-error-enters-recovery-mode.md) | [blinded analysis](../antithesis/scratchbook/rca/storage-error-enters-recovery-mode.md); no upstream fix ([comparison](../antithesis/scratchbook/rca/storage-error-enters-recovery-mode.md#comparison-with-upstream)); unchanged on the latest `main` | unit test only: fails without the fix, passes with it; 50 of 50 related tests pass ([log](../antithesis/scratchbook/logs/unit-test-storage-error-enters-recovery-mode.txt)); no fix-check run (one long enough wouldn't report before the cutoff) |
| [Decryption stalls after a core restarts](speedrun-report.md#known-bug-check) (the known bug, before-the-fix build only) | [Guarantee 2](speedrun-report.md#guarantee-2) | 118 + 41 / 2 (107 + 41 analysed as the known bug; 118 in [`52a8bf9b`](https://zama.antithesis.com/report/9eEE7zOFd9Dh9U3xoux0L-pj/QKG_cHLnNVVbOYWB0R0HlqKpRTSdfPqStnNZHN3dfPw.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUUtHX2NITG5OVlZiT1lXQjBSMEhscUtwUlRTZGZQcVN0bk5aSE4zZGZQdy5odG1sIiwicmVwb3J0X2lkIjoiOWVFRTd6T0ZkOURoOVUzeG91eDBMLXBqIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjU5OjE0LjIyMjgwNjM3N1oifbWHfRwyY5SragY9QudsFg23eqGDVqsOLpO1QjjEXtewl5lI-gUwUNxI3o5onfIw34kyP6XqcyIcKwhz_FiQ4Qk), 41 in [`336b5b11`](https://zama.antithesis.com/report/Fll8Soc5kCDFTeEZp3ek17Ea/gZZGf9Vks_xaKy0EyS88AGlaJVfemscOEEYb6WG4vAs.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA0OjAxOjQxLjY1NTk3MDU5M1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiZ1paR2Y5VmtzX3hhS3kwRXlTODhBR2xhSlZmZW1zY09FRVliNldHNHZBcy5odG1sIiwicmVwb3J0X2lkIjoiRmxsOFNvYzVrQ0RGVGVFWnAzZWsxN0VhIn19fYJapcfSFfD2FlJP98J-1mav97zxLbJd1AWPqbw3R4BFyC9CJe4Ma707fn9SKpmxAwnwRwWBuICXoowHTbT69wM)) | not needed: signature matched against the known bug ([review](../antithesis/scratchbook/false-positives.md#prefix-recovery-fails-after-core-restart)) | [same as upstream](../antithesis/scratchbook/rca/decryption-stalls-after-core-restart.md#comparison-with-upstream) | verified ([`a7167532`](https://zama.antithesis.com/report/E3aRgfAZx0FG9ubZyK2gLIoR/WOfMjnEReqZRagmPUuWwUHPDAjmwjhtZw3u5U5iRSuU.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA4OjA5OjE5LjE3MjY0NjYxM1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV09mTWpuRVJlcVpSYWdtUFV1V3dVSFBEQWptd2podFp3M3U1VTVpUlN1VS5odG1sIiwicmVwb3J0X2lkIjoiRTNhUmdmQVp4MEZHOXViWnlLMmdMSW9SIn19feJnQdPR6ASOY1JTnB5-6WNI3-5xqJfWurzelFpKrcEWWRqdnjJ2gCtotLkMWQ5e1aqAmMFoC5nDcB466sYCTwU), [digest](../antithesis/scratchbook/runs/fix-verify-1.md)) |

One finding on the current version reached the adversarial check, and it stood.

**Caveats on the new finding:**
- **One failing timeline,** in the first of three runs with timing fuzzing, and that run also had
  test-machine stalls (an Antithesis error, coredns and journald crashes). The stall-free evidence:
  in the failing history no source goes quiet for more than 3 s around the failed read, and the
  same entry into recovery mode happens without timing fuzzing in [`8196fb3c`](https://zama.antithesis.com/report/RQ8Cbp-xGNyv2LzRK7QJhdaS/Q4j24Mga4r9vKq6G1GGKGJhmWP0f7ZtlCtPmgF4J-dU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUTRqMjRNZ2E0cjl2S3E2RzFHR0tHSmhtV1AwZjdadGxDdFBtZ0Y0Si1kVS5odG1sIiwicmVwb3J0X2lkIjoiUlE4Q2JwLXhHTnl2Mkx6Uks3UUpoZGFTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjUyOjUyLjkwNzU2NjUzOVoiffXOyyh90TorAK1eQ08RnDaqV3Hiuf4ZXbyxANa4Qh-8Ku_qk3g7JPpHFH0alZBWKDgpmQ1bzWKzpgv7_81JSwI) ([details](../antithesis/scratchbook/rca/storage-error-enters-recovery-mode.md#across-the-runs)).
  The two later timing-fuzzing runs ([hunt-current-6](../antithesis/scratchbook/runs/hunt-current-6.md),
  [hunt-current-7](../antithesis/scratchbook/runs/hunt-current-7.md)) passed every guarantee check,
  never entered recovery mode (run-wide searches after they finished), and had no stalls. It's rare: the trigger is a storage error at one
  step of a boot.
- **The check needs all four cores to answer.** Threshold output delivery held: three cores
  answered every request. The finding is that the fourth never comes back on its own, which the
  docs' "re-join an existing set of nodes" promise and Guarantee 2 cover.
- **47 of the run's 48 failing examples of the check are not this bug.** They are one checker
  execution in which the test machine stalled before the client contacted any core
  ([review](../antithesis/scratchbook/false-positives.md#recovery-check-attempt-outlives-timeout)).
  Quote "1 failing example", never 48.
- **The fix isn't checked in Antithesis:** a run long enough to mean anything wouldn't report
  before the cutoff. A unit test covers it instead.


**Caveats on the known-bug check:**
- **The blinding was procedural.** The blinded agent saw the source with no history, the fix's own
  tests removed, and inputs scrubbed of the PR number and the word "keepalive". The upstream fix
  (2026-09-25) is newer than the model's training data, but half-open connections and gRPC
  keep-alive are a well-known pattern.
- **The signature match isn't literal.** The [expected symptom](../antithesis/scratchbook/positive-control.md)
  predicted two lines that never appeared in the first failing timelines. The CLI's own error
  didn't appear because our script's 90 s per-attempt timeout ends the CLI first. The restarted
  core's "(Share reconstruction) Some party has timed out" didn't appear because it falls after the
  300 s window. The substance matches: the restarted core is the missing response, the other three
  answer within milliseconds, and Guarantee 1 holds. The kill-only trigger of the second run was
  anticipated in positive-control.md.
- **The before-the-fix build is a revert, not the historical commit**
  ([why](../antithesis/scratchbook/positive-control.md#why-the-fix-is-reverted-on-current)). It's
  current code minus the fix's production changes.
- **Guarantee 2's windows (600 s, 300 s) are ours,** inferred from the deployed `network_timeout`
  and Kubernetes' back-off; Zama documents no recovery time.
- **Not every failing example was analysed.** In 11 of run 1's 118, all from one history, the core
  stuck answering "not done yet" (kms-core-2) hadn't been restarted, and later attempts reached no
  core. They weren't analysed and may be a different mechanism
  ([RCA, across both runs](../antithesis/scratchbook/rca/decryption-stalls-after-core-restart.md#across-both-runs)).
- **A possible harness gap in "faults stop".** In 5 of run 1's failing examples, a pod kill landed
  2 s after the fault injector's `restore`, so faults hadn't fully stopped when Guarantee 2's
  clock started. Either the eventually phase or `$ANTITHESIS_STOP_FAULTS` didn't stop an
  already-scheduled pod fault. It doesn't explain the other failures, but the launcher's
  behaviour here is worth asking about.

## Unconfirmed findings

<a id="boot-panic-port-in-use"></a>
### A restarting core sometimes can't bind its service port

The report mentions it, labelled unconfirmed ([report entry](speedrun-report.md#boot-panic-port-in-use)).
- **What was seen:** `kms-server` panics with `Could not bind to 0.0.0.0:50100 … AddrInUse` and
  exits with code 101 while restarting. 3 failing examples (2 panics in one history) in iterate-3
  on kms-core-2, and 150 in hunt-current-2, where all 129 panic lines are on kms-core-1. It recurred
  in hunt-current-3 (155), hunt-current-5 (115) and hunt-current-6 (8), not analysed further. In one history the port stays
  taken across four server processes in a row, for at least 42.6 s, with no other container
  running in the pod. A sibling history binds again about 76 s after the stop. No guarantee broke.
- **The specific doubt:** no log line shows the port's holder. The leading explanation is a
  `TIME_WAIT` left by one of the pod's own outgoing connections to MinIO on local port 50100.
  That's consistent with every timing seen, but unproven. An Antithesis-specific network effect
  isn't excluded.
- **What was tried:** logs and code ([probe file](../antithesis/scratchbook/probes/boot-panic-port-in-use.md)).
  Ruled out: a leftover server, another container on the port, and a double bind. A local kernel
  check reproduces the error from a `TIME_WAIT` socket
  ([check](../antithesis/scratchbook/probes/boot-panic-port-in-use/tw-bind-check.md)). Live
  probing wasn't possible: live event streaming timed out on this tenant, and `runs exec` refused
  the completed run.
- **What would settle it:** `ss -tan` inside the pod at the next occurrence, via a live `runs exec`
  or a debugging session on [`bbb951cd`](https://zama.antithesis.com/report/RrQpUXYBRSznhOom3OWSsVwm/GOczSuL6QWj7Sl9UX46ZavqUH-q6DwiQt8cf-yXoqwA.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDAzOjU2OjAzLjUzMjQyMjgxMVoiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiR09jelN1TDZRV2o3U2w5VVg0NlphdnFVSC1xNkR3aVF0OGNmLXlYb3F3QS5odG1sIiwicmVwb3J0X2lkIjoiUnJRcFVYWUJSU3puaE9vbTNPV1NzVndtIn19fV6KMVLXfgSv3BN0DgMakXVvvIoEAi2-twEk9HZOqycO8BOfEEsMjOAaYl8MgRQlvNNY0l4DDvldF3EVrgJg9A4)
  at moment `-6322595181088069127` / `1143.8002873579971`.
- **Evidence:** [false-positive review entry](../antithesis/scratchbook/false-positives.md#boot-panic-port-in-use),
  [hunt-current-2 digest](../antithesis/scratchbook/runs/hunt-current-2.md#exit-101-what-was-happening),
  [iterate-3 digest](../antithesis/scratchbook/runs/iterate-3.md).

## Leads

None.

## Evidence for each finding

| Finding | Run | Failing moment | Log | Local log |
|---|---|---|---|---|
| [A storage error while a core boots leaves it in recovery mode](speedrun-report.md#storage-error-enters-recovery-mode) | [`4e338bff`](https://zama.antithesis.com/report/z0DpS4BEFi0AtQY_3k2xQYil/WNeeUiIs3qYUlUd7UAiS1YdNQh8HKvhl2ofzq82Afa8.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA3OjA0OjQzLjEwMjAyODEzMloiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiV05lZVVpSXMzcVlVbFVkN1VBaVMxWWROUWg4SEt2aGwyb2Z6cTgyQWZhOC5odG1sIiwicmVwb3J0X2lkIjoiejBEcFM0QkVGaTBBdFFZXzNrMnhRWWlsIn19fZI8ndKJGsf6_PbNOmcRvP7XRP6CnD-8mfcqZYL0UYS8iuH35ePerg9wy7HvBDKR8Y_jV7R5W-saZjsBZoGotAo) | input_hash `-7353950694920754647`, vtime `1405.5561482245103` | [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTQwNS41NTYxNDgyMjQ1MTAzIn1dLCJvIjoib3IifSx7ImgiOlt7ImMiOiJtb21lbnQuaW5wdXRfaGFzaCIsImYiOiJnZW5lcmFsLmN1c3RvbSIsIm8iOiJtYXRjaGVzIiwidiI6Ii03MzUzOTUwNjk0OTIwNzU0NjQ3In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6Ijg4Y2ViMWFkZDZiMDM3YjQyNTQ4Yjk4ZTc5OTU4M2U0LTY0LTQifQ) | [hunt-current-3-g2decrypt-7353950694920754647.ndjson](../antithesis/scratchbook/logs/hunt-current-3-g2decrypt-7353950694920754647.ndjson) |
| same, entry into recovery mode never exercised | [`8196fb3c`](https://zama.antithesis.com/report/RQ8Cbp-xGNyv2LzRK7QJhdaS/Q4j24Mga4r9vKq6G1GGKGJhmWP0f7ZtlCtPmgF4J-dU.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUTRqMjRNZ2E0cjl2S3E2RzFHR0tHSmhtV1AwZjdadGxDdFBtZ0Y0Si1kVS5odG1sIiwicmVwb3J0X2lkIjoiUlE4Q2JwLXhHTnl2Mkx6Uks3UUpoZGFTIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjUyOjUyLjkwNzU2NjUzOVoiffXOyyh90TorAK1eQ08RnDaqV3Hiuf4ZXbyxANa4Qh-8Ku_qk3g7JPpHFH0alZBWKDgpmQ1bzWKzpgv7_81JSwI) | input_hash `-5663972180894011767`, vtime `912.4901551296934` | [log](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiOTEyLjQ5MDE1NTEyOTY5MzQifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTU2NjM5NzIxODA4OTQwMTE3NjcifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMjhkNWU1YjY2NjM5ZDI0MDlkN2YwMzZkZTk1MjM3OGUtNjQtNCJ9) | [recovery-mode-8196fb3c.json](../antithesis/scratchbook/logs/recovery-mode-8196fb3c.json) |
| [Decryption stalls after a core restarts](speedrun-report.md#known-bug-check) | [`52a8bf9b`](https://zama.antithesis.com/report/9eEE7zOFd9Dh9U3xoux0L-pj/QKG_cHLnNVVbOYWB0R0HlqKpRTSdfPqStnNZHN3dfPw.html?auth=v2.public.eyJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiUUtHX2NITG5OVlZiT1lXQjBSMEhscUtwUlRTZGZQcVN0bk5aSE4zZGZQdy5odG1sIiwicmVwb3J0X2lkIjoiOWVFRTd6T0ZkOURoOVUzeG91eDBMLXBqIn19LCJuYmYiOiIyMDI2LTEwLTE4VDAzOjU5OjE0LjIyMjgwNjM3N1oifbWHfRwyY5SragY9QudsFg23eqGDVqsOLpO1QjjEXtewl5lI-gUwUNxI3o5onfIw34kyP6XqcyIcKwhz_FiQ4Qk) | input_hash `-1064784367327107482`, vtime `537.2539669850376` | [logs explorer](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTM3LjI1Mzk2Njk4NTAzNzYifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTEwNjQ3ODQzNjczMjcxMDc0ODIifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiMzY4NGYxZGZiNzQxNDY0MWE1ZGU4YWQ2OTRlMGNiZjctNjQtNCJ9) | [hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson](../antithesis/scratchbook/logs/hunt-prefix-1-g2-decrypt--1064784367327107482.ndjson) |
| same, strobed faults | [`336b5b11`](https://zama.antithesis.com/report/Fll8Soc5kCDFTeEZp3ek17Ea/gZZGf9Vks_xaKy0EyS88AGlaJVfemscOEEYb6WG4vAs.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE4VDA0OjAxOjQxLjY1NTk3MDU5M1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoiZ1paR2Y5VmtzX3hhS3kwRXlTODhBR2xhSlZmZW1zY09FRVliNldHNHZBcy5odG1sIiwicmVwb3J0X2lkIjoiRmxsOFNvYzVrQ0RGVGVFWnAzZWsxN0VhIn19fYJapcfSFfD2FlJP98J-1mav97zxLbJd1AWPqbw3R4BFyC9CJe4Ma707fn9SKpmxAwnwRwWBuICXoowHTbT69wM) | input_hash `1785964589558531638`, vtime `542.3516741667408` | [logs explorer](https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiNTQyLjM1MTY3NDE2Njc0MDgifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTc4NTk2NDU4OTU1ODUzMTYzOCJ9XSwibyI6Im9yIn1dLCJvIjoiYW5kIn0sInQiOnsiZyI6ZmFsc2UsIm0iOiIifSwieSI6Im5vbmUifX0sInMiOiJlNWQwZjRlNWQ4MzZiZjIyYmQ2YmZjNGZlNzA2M2EyNy02NC00In0) | [hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson](../antithesis/scratchbook/logs/hunt-prefix-2-g2-decrypt-1785964589558531638.ndjson) |

## Method notes

- **False positives caught:** 5, plus 1 harness gap and 2 suspects
  ([false-positives.md](../antithesis/scratchbook/false-positives.md)). The most instructive: 47 of
  the 48 Guarantee 2 failing examples in hunt-current-3 were a test-machine stall, where the client
  froze mid-way through encrypting its input before contacting any core
  ([entry](../antithesis/scratchbook/false-positives.md#recovery-check-attempt-outlives-timeout)).
  Without that review the run would have been quoted as 48 failures of the new finding. The others:
  the memory warning was the VM's size
  ([entry](../antithesis/scratchbook/false-positives.md#peak-memory-command-backlog)); the
  certificate-fetching init container gives up after 600 s of continuous faults
  ([entry](../antithesis/scratchbook/false-positives.md#load-env-init-gives-up-under-faults)); a core
  that boots while cut off from MinIO exits with code 1 and is restarted
  ([core exits](../antithesis/scratchbook/false-positives.md#core-exits-when-storage-unreachable-at-boot)),
  and the key-generation init container does the same
  ([gen-keys exits](../antithesis/scratchbook/false-positives.md#gen-keys-init-exits-when-storage-unreachable)).
  Both are fail-fast by design. The harness gap: two coverage markers needed pod faults that the
  network-only stage didn't have ([entry](../antithesis/scratchbook/false-positives.md#sometimes-need-pod-faults)).
- **Iteration runs to reach green:** 4 (30 min each), after 2 setup runs: network faults only →
  pod kills → all four guarantees → the full default fault set. No guarantee check failed on the
  current version during iteration.
- **Fault types used:** the `advanced_k8s_test` launcher, which the user added to the tenant during
  the session, raised in stages. Setup and the first iteration: `network`. Iterations 2–3:
  `network,pod_kill`, pod faults every 600 s. Iteration 4 and every hunt: `network,pod_stop,pod_kill,clock_jitter`.
  Later hunts varied this: strobing (quiet windows 60–120 s) in four hunts; timing fuzzing in three
  (`hunt-current-3`, `-6`, `-7`); a 16 GiB VM in two (`-4`, `-6`); and a pod fault every 150 s
  instead of 300 s in one (`-5`). The client and MinIO pods were excluded from pod faults
  throughout. Hunts and the fix check ran on the turbo tier.
- **Fault types needed but unavailable:** none for the four tested guarantees. Byzantine behaviour
  isn't a fault Antithesis injects, and disk faults aren't offered by this launcher. `cpu_pressure`
  was deliberately left off.
- **Harness gaps:**
  - [Guarantee 5](speedrun-report.md#guarantee-5) was deferred: it needs a Rust helper in the
    client image and new builds of both versions, which didn't fit.
  - Guarantee 2's Sometimes marker "a core the client could not connect to after faults stopped
    accepted connections again" was hit in every long run except hunt-prefix-2.
  - The guarantee wording was corrected once mid-session, to "every core accepts connections
    within 600 s, then a decryption by all four within 300 s"
    ([log](../antithesis/scratchbook/speedrun-log.md)).
- **Recurring warnings** (told to the user as they recurred):
  - "No unexpected container exits" (exit 1): every run with pod faults. These are the fail-fast
    boots above.
  - "Peak memory usage": failed in all 7 runs of 2 hours or more on the default 9.71 GiB VM
    (1235, 1650, 615 and 1370 failing examples in the 4-hour runs; 12, 1 and 331 in the fix check,
    hunt-current-5 and hunt-current-7), never in 30-minute runs, and passed in the 105-minute default-VM run (hunt-current-3) and in both
    16 GiB runs.
    It's the backlog of concurrent test commands (183–316 waiting during faults) against the VM's
    size ([entry](../antithesis/scratchbook/false-positives.md#peak-memory-command-backlog)).
    [hunt-current-4](../antithesis/scratchbook/runs/hunt-current-4.md#peak-memory-usage) and [hunt-current-6](../antithesis/scratchbook/runs/hunt-current-6.md) ran with a 16 GiB VM, and "Peak memory usage" passed in both. They were 105 and 125 minutes, not 240, and the property doesn't show the peak value, so a slow leak isn't ruled out.
  - The exit-101 port crash: 5 runs (3 failing examples in iterate-3; 150, 155, 115 and 8 in hunt-current-2, -3, -5 and -6); never on the build before the fix or in the fix check.
- **Test-machine stalls under timing fuzzing:** hunt-current-3 only. "No Antithesis errors"
  (`state_cant_be_materialized`, guest timed out), a coredns exit and a journald abort, in
  timelines where the whole VM went nearly silent for minutes; one such stall also caused 47 of
  that run's 48 Guarantee 2 failing examples
  ([entries](../antithesis/scratchbook/false-positives.md#timing-fuzzing-guest-stalls)). Not seen
  in the two later timing-fuzzing runs. Worth mentioning to the Antithesis team if it recurs.
- **Document review:** a fresh reviewer checked the final documents against the sources in two
  passes (27 items, then 8 follow-ups). All were fixed; the 8 follow-ups weren't re-reviewed.
- **Live debugging:** `snouty runs search --follow` failed to reach the API on an in-progress run
  ([error](../antithesis/scratchbook/logs/live-iterate-1.err)), so no later run was watched or
  cancelled early, and no probe ran inside a live run. All analysis used completed
  runs' logs.
- **Environment trouble on the build VM:**
  - The VM was first too small (2 vCPU, 7 GB). The user resized it to 16 vCPU, 31 GB and 148 GB
    (a stop for the resize).
  - Podman's runc rejected the build's bind mounts, so all images were built with docker.
  - The VM's DNS failed intermittently during builds. A local dnsmasq now forwards to
    169.254.169.254, 8.8.8.8 and 1.1.1.1, and `/etc/resolv.conf` points at it. The original is
    in `/etc/resolv.conf.speedrun-bak`. To restore it:
    `sudo cp /etc/resolv.conf.speedrun-bak /etc/resolv.conf && sudo kill $(cat /run/speedrun-dnsmasq.pid)`.
  - The VM's address range (10.42.0.0/16) overlaps k3s's default pod range. k3s was left running.
  - The `ANTITHESIS_*` environment pointed at a proxy that answers 403, so snouty ran through a
    wrapper that uses its settings file instead.
- **Run spent on a mistake:** the first setup run ([`0f9fd70d`](../antithesis/scratchbook/runs/setup-1.md))
  never started its tests. With the Kubernetes launcher, snouty pushes only the config image, and
  the KMS images hadn't been pushed yet.
- **Peak memory and the workload:** the composer piles up hundreds of concurrent commands and
  reshares during long fault windows. For future runs, cap that concurrency in the workload, or
  give the VM more memory. Changing it mid-hunt would have broken the comparison with the
  before-the-fix runs.

## Content hooks

- "A few seconds of storage outage at the wrong moment of a reboot takes a KMS party out of every
  decryption, indefinitely, while Kubernetes thinks it's healthy." (The new finding: one boot step
  treats a network error as a lost signing key.)
- Angle: the bug hides behind a deliberate feature. Recovery mode exists for restoring a wiped
  node from backups; the bug is only in how a node decides it's been wiped. Nearby code already
  makes the right distinction ("a seed that is present but unreadable is an error, not an absent
  seed").
- Angle: the guarantee that caught it is the same one that caught the known bug. Correct answers
  kept flowing from the other three cores, so only a check that needs every party noticed.
- "We removed one fix from Zama's KMS, and Antithesis found the bug it fixed in both 4-hour runs:
  a core restarted after a pod kill can't help decrypt, because, per the analysis (which upstream's fix confirms), its peers keep writing into a dead
  connection."
- "An analysis that never saw the upstream fix reached the same root cause and the same kind of
  fix: HTTP/2 keep-alive pings on the peer channels."
- Diagram: timeline of one failing history. Pod kill at 235 s, faults stop at 237 s, three cores
  answer in 40 ms, the restarted core waits, failure at 537 s.
- Angle: availability bugs hide behind correct answers. Guarantee 1 (correct plaintext) never
  failed, even on the broken build. Only a recovery check that needs every party catches a party
  that silently can't participate.
- Angle: before and after on one harness. The same manifests and test commands, two builds that
  differ only in the fix, 159 failing examples against none in the current-version runs with the
  same faults, and none in the fix check.

## Still running at the deadline

None: every run reported before the cutoff.

## Open questions

- Guarantee 5 (request-ID retries) is untested.
- What holds port 50100 in the [port crash](#boot-panic-port-in-use).
- Whether memory keeps growing slowly in long runs (a leak): both 16 GiB runs passed, but they were 105 and 125 minutes, and the peak value isn't exposed.
- The recovery-mode fix is checked by a unit test only, not in an Antithesis run.
- How often production cores hit a storage error during that one boot step: the trigger is narrow,
  but a node in recovery mode stays there until restarted, and nothing alerts on it.
- Behaviour at production scale (13 parties, `t = 4`) and with real parameters wasn't tested.

## Artifacts

| What | Where |
|---|---|
| Customer report | [speedrun-report.md](speedrun-report.md) |
| How the tests work | [speedrun-tests.md](speedrun-tests.md) |
| State / log | [speedrun-state.json](../antithesis/scratchbook/speedrun-state.json), [speedrun-log.md](../antithesis/scratchbook/speedrun-log.md) |
| Guarantees | [guarantees.md](../antithesis/scratchbook/guarantees.md) |
| Known bug | [positive-control.md](../antithesis/scratchbook/positive-control.md) |
| Harness | [config/](../antithesis/config/), [config-prefix/](../antithesis/config-prefix/), [config-fixverify-decryption-stalls-after-core-restart/](../antithesis/config-fixverify-decryption-stalls-after-core-restart/), [test/](../antithesis/test/), [images/](../antithesis/images/) |
| Findings | [false-positives.md](../antithesis/scratchbook/false-positives.md), [violations/](../antithesis/scratchbook/violations/), [adversarial/](../antithesis/scratchbook/adversarial/), [rca/](../antithesis/scratchbook/rca/), [fixes/](../antithesis/fixes/), [probes/](../antithesis/scratchbook/probes/) |
| Runs | [runs/](../antithesis/scratchbook/runs/); the full run table is in the [report's appendix](speedrun-report.md#runs) |
| Build provenance | the [report's appendix](speedrun-report.md#builds), plus [patches/](../antithesis/patches/) and the build logs in [logs/](../antithesis/scratchbook/logs/) |
