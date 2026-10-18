<a id="storage-error-enters-recovery-mode"></a>
# Adversarial review: a storage error while a core boots leaves it in recovery mode

Reviews the write-up [violations/storage-error-enters-recovery-mode.md](../violations/storage-error-enters-recovery-mode.md).

## Verdict

**stands.** The decision to enter recovery mode is made entirely inside unmodified kms-server code.
[`boot_base_kms`](../../../core/service/src/engine/backup_operator.rs#L850) treats a transient S3
"dispatch failure" as a lost signing key. The key was present before and after the error. It was
read without error at 919.25 and again at 1100.82, 11 s after the failed read, and the same boot's
migration step treats this identical error as fatal. Nothing in the harness sits between the
partition and the stranded node. The production chart has the same storage path, SDK defaults and
probes, and no probe or documented runbook restarts a node in this state. The mechanism also
appears in a run without timing fuzzing, on a different core.

## 1. Harness intervention

None found between the fault and the symptom.

- **SUT code is unmodified.** `git diff main...HEAD` changes nothing under `core/`. The only non-harness
  change links the coverage shim into the observability crate
  ([lib.rs](../../../observability/src/lib.rs), [kms-binaries.Dockerfile](../../images/kms-binaries.Dockerfile)).
  The two patch sets in [patches/](../../patches/) touch only networking and config (HTTP/2
  keepalive, sending service), and they apply only to the pre-fix and fix-verify builds, not to
  this build (current: upstream [`4a644c85`](https://github.com/zama-ai/kms/commit/4a644c8546abc8b002b7e45c19bf195996e7d229) plus coverage instrumentation). `boot_base_kms` comes from upstream commit ba64e7f6 (#896).
- **No supervisor or wrapper.** The kms-core container runs `/bin/sh -c '… kms-server --config-file=kms-server.toml'`
  with `restartPolicy: Always`, with no restart loop
  ([32-kms-core-2.yaml, line 290](../../config/manifests/32-kms-core-2.yaml#L290)). Its probes are the chart's values unchanged
  ([lines 334–355](../../config/manifests/32-kms-core-2.yaml#L334-L355) vs.
  [values.yaml, lines 210–224](../../../charts/kms-core/values.yaml#L210-L224)).
- **Nothing selects recovery mode.** The config has no backup vault, no custodian setting and no
  environment variable that affects boot. TLS is configured (`[threshold.tls.auto]`,
  [line 427](../../config/manifests/32-kms-core-2.yaml#L427)), which the recovery-mode warning itself
  says should not be the case for a deliberate recovery boot.
- **The key was not made absent.** Neither the gen-keys init container nor any workload script
  removes it. In the failing history,
  `kms-core-init-gen-keys` finds the existing threshold signing keys (749.87, `overwrite: false`).
  The new kms-server reads `PRIV-p2/SigningKey/60b7…` during its migration (919.25). After
  entering recovery mode it reads the same object and the seed again without error (1100.82)
  ([log](../logs/hunt-current-3-g2decrypt-7353950694920754647.ndjson)). No workload script writes
  to or deletes from `kms-private`. The bootstrap job runs `kms-gen-keys` once before faults start.
- **The harness's init-container change** (CA-fetch retry in `kms-core-init-load-env`) runs before
  kms-server and finished at 714.10. It doesn't touch the private vault.

## 2. Configuration and tuning

The enabling condition is not a tuned value.

- **S3 client:** the SUT builds its S3 client from `aws_config::defaults(BehaviorVersion::v2026_01_12())`
  with only region, endpoint and identity-cache timeout set
  ([aws.rs, line 16](../../../core/service/src/vault/aws.rs#L16);
  [s3.rs, line 635](../../../core/service/src/vault/storage/s3.rs#L635)). There is no config knob
  for retries or timeouts. Neither the chart nor the harness sets `AWS_MAX_ATTEMPTS` or `AWS_RETRY_MODE`. Production gets the
  same SDK default retry policy (standard mode, a few attempts) as the harness.
- **Storage layout:** the harness keeps the private vault on S3 (MinIO), as the documented
  production deployment does (`privateVault.s3.enabled: true` plus an AWS KMS keychain,
  [production-deployment.md](../../../docs/operations/production-deployment.md), lines 295–302).
  The chart's default is a file vault on a PVC (`privateVault.s3.enabled: false`,
  [values.yaml, lines 173–182](../../../charts/kms-core/values.yaml#L173-L182)). There, the trigger
  would be a local read error instead of a network one. The keychain the harness leaves out doesn't
  change the failing call, an S3 listing (`all_data_ids`,
  [vault/mod.rs, line 341](../../../core/service/src/vault/mod.rs#L341)).
- **Nothing in [tuning.md](../tuning.md) touches storage or boot.**
- **No documented operator expectation makes this intended.**
  - The troubleshooting guide says recovery mode follows an *absent* key: "A `SigningKey` is
    required for serving boot; if it is absent, the server enters recovery mode"
    ([troubleshooting.md](../../../docs/operations/advanced/troubleshooting.md), lines 218–221).
  - The only "restart to leave recovery mode" instruction belongs to the deliberate custodian
    recovery flow
    ([backup.md](../../../docs/guides/backup.md), line 253).
  - In recovery mode, readiness and liveness both report SERVING. The SUT's own health contract says
    "Liveness fails only when a component reports a fault that the process cannot recover from
    without a restart" ([health.rs, lines 7–9](../../../observability/src/health.rs#L7-L9)). A node
    stuck in recovery mode is exactly that case, but nothing calls `report_fatal`. So Kubernetes
    never restarts it, in production or here.

## 3. Faults beyond the guarantee's promise

The faults were heavy, but the guarantee covers this case.

- Faults ran without a break from 228.10 to 1100.67. Several pod faults overlapped, so more than one
  core was down at once (for example kms-core-3 booting from 950.03 and kms-core-1 stopped at
  1068.96 while kms-core-2 booted). That exceeds t = 1 *during* faults. Guarantee 2 only judges the
  time after faults stop ([guarantees.md](../guarantees.md#guarantee-2)), and the stranded state
  belongs to one node and doesn't depend on its peers. It comes from a single failed read on
  kms-core-2.
- The fault does no lasting damage: the network is restored at 1100.67, MinIO is never pod-faulted,
  and the object is readable 0.15 s later.
- **Is the read error a platform stall rather than a network fault?** No.
  - kms-core-2's last line before the error is 1053.08, the socket-address print just before
    `boot_base_kms`. So the failing listing spanned 1053.08 → 1089.59.
  - Over that span the fault injector keeps cutting or degrading kms-core-2's path to MinIO:
    - partitions that separate the two at 1053.09 (Stopped), 1067.74 (Stopped), 1073.32 (Slowed),
      1074.92 (Jammed) and 1079.90 (Slowed);
    - clogs on kms-core-2 at 1052.67, 1061.16, 1061.36 (Stopped), 1063.98, 1067.16 (Stopped) and
      1074.64;
    - one full restore at 1080.27, then a Jammed clog on kms-core-2 and MinIO at 1083.19;
    - at 1085.75, an asymmetric 6.7 s Stopped partition that separates all four cores and the client
      from MinIO.
  - Between 1050 and 1101 no source goes quiet for more than 3 s. The composer, the fault injector,
    coredns and the other cores keep logging, and kms-core-1's init container sees MinIO listings
    fail in the same window (1074.70, 1090.37).
  - None of the signs of [timing-fuzzing-guest-stalls](../false-positives.md#timing-fuzzing-guest-stalls)
    appear: no long silence and no API-server TLS failures.
- **A side observation:** in this history, faults stopping is what strands the node. The
  recovery-mode boot's follow-up read of the public verification key
  ([`recovery_mode_verf_key`](../../../core/service/src/engine/backup_operator.rs#L817)) was issued
  at 1089.65 during the partition and returned just after the 1100.67 restore. In 9 sibling
  timelines descending from the same 1089.64 entry, that read failed too ("Could not read the
  verification key in public storage (dispatch failure)", 1100.79–1100.86,
  [backup-operator-4e338bff.ndjson](../logs/backup-operator-4e338bff.ndjson)). With no backup vault,
  `boot_base_kms` then returns an error
  ([line 833](../../../core/service/src/engine/backup_operator.rs#L833)) and the process exits,
  which is the restartable path. So whether the node ends up stuck depends on whether that second read succeeds.
  This is ordinary network timing, not something the harness injected.

## 4. The checker

The checker doesn't misreport. In [eventually_recovers_after_faults.sh](../../test/v1/public_decrypt/eventually_recovers_after_faults.sh#L97-L101)
it sends a fresh `-a public-decrypt` with `timeout 90` per attempt, 10 s apart, for 300 s, and
reports what the CLI returns.

- All 27 failures in history A are kms-core-2 refusing with gRPC code 9, "Signing key is not
  present. This should only happen when server is booted in recovery mode" (27 lines,
  1126.14–1395.52). Cores 1, 3 and 4 sign every result.
- Requiring all four cores is a stricter promise than threshold output delivery: three of four
  would have answered a client using the threshold. But this is Guarantee 2 as written. It checks
  that the cluster heals, and it rests on the documented claim "When a threshold node restarts, it
  will automatically use init material it finds on disk. This allows failing nodes to re-join"
  ([kms-server-bin.md](../../../docs/guides/kms-server-bin.md), line 271;
  [property file](../properties/recovers-after-faults.md)).
- A minor imprecision: the 300 s window started at attempt 1 (1100.69, `connect_wait_s 0`), before
  kms-core-3 accepted connections at 1114.60. That cost the cores about 14 s and is immaterial here.
  The node had no path out of recovery mode short of a restart, and no restart came (restart_count
  0 throughout).

## 5. Reproduction

The same mechanism shows up in two runs, on two cores, with and without timing fuzzing.

- **[hunt-current-1](../runs/hunt-current-1.md)** (8196fb3c, no timing fuzzing, the same level-3
  faults): kms-core-1, restart_count 0, at 912.49 logs `backup_operator.rs:860` "Error loading signing key: … Failed to
  read SigningKey from "S3 storage with bucket kms-private": Getting all ids failed: dispatch
  failure", then line 861 "ENTERING RECOVERY MODE"
  ([backup-operator-8196fb3c.ndjson](../logs/backup-operator-8196fb3c.ndjson)). It finishes booting
  in recovery mode ("Initializing KMS without a signing key") in 5 timelines at 914.74–917.08
  ([no-signing-key-boot-8196fb3c.ndjson](../logs/no-signing-key-boot-8196fb3c.ndjson)). No checker
  reached it there.
- **Timing fuzzing is not the enabling condition.** The trigger is an S3 read failing under network
  partitions, and hunt-current-1 has no timing fuzzing.
- **Within hunt-current-3**, kms-core-4 hits the identical read error at 1278–1280 in several
  timelines, but during the migration step. There it ends the process ("Could not complete
  migration", [kms-server.rs, lines 529–536](../../../core/service/src/bin/kms-server.rs#L529-L536);
  [signing-key-read-failed-4e338bff.ndjson](../logs/signing-key-read-failed-4e338bff.ndjson)).
  The migration checks `data_exists` first (absent: skip) and treats a read error as fatal
  ([migration.rs, lines 242–252](../../../core/service/src/engine/migration.rs#L242-L252)). The
  same boot therefore separates "absent" from "unreadable" a few seconds before `boot_base_kms`
  merges them. The root-seed reader does the same
  ([utils.rs, lines 426–432](../../../core/service/src/vault/storage/crypto_material/utils.rs#L426-L432)).
- **Only execution A of the two failing checker executions is this finding.** Execution B (47 of
  the 48 counterexamples; history saved as
  [hunt-current-3-g2decrypt-execB-453276507424875132.ndjson](../logs/hunt-current-3-g2decrypt-execB-453276507424875132.ndjson))
  has no recovery mode: 0 lines of "ENTERING RECOVERY MODE", "Signing key is not present" or
  "Initializing KMS without a signing key". It split from A at 227.09. In B, the fault injector
  pauses at 1196.59, then **stops kms-core-2's pod at 1225.20, inside the quiet window**. The
  checker's second attempt then runs from 1245.77 to "Terminated" at 1533.02, with events arriving
  10–25 s apart. That belongs to
  [recovery-check-attempt-outlives-timeout](../false-positives.md#recovery-check-attempt-outlives-timeout),
  not to this finding.
- **Hunts 5–7: not reproduced.** Searches of the finished runs hunt-current-5, -6 and -7 for
  "ENTERING RECOVERY MODE" (by the orchestrator, after this review, at 10:58 UTC) return no event
  and no error, while the same search returns the one entry in hunt-current-3
  ([search outputs](../logs/), `recovery-mode-<run>.json`). Every guarantee check passed in those
  three runs ([hunt-current-5](../runs/hunt-current-5.md), [-6](../runs/hunt-current-6.md),
  [-7](../runs/hunt-current-7.md)).

## Strongest case for the system

The best defence combines three arguments.

1. **Output delivery held.** Zama promises output delivery with up to t = 1 node offline or
   misbehaving. Throughout the window, three cores decrypted and signed every request, so a client
   collecting the threshold rather than all four would have been served. A node in recovery mode is
   one "misbehaving" node, inside the budget.
2. **The trigger is narrow and the faults are extreme.** The S3 listing has to fail through the SDK's
   retries at one specific boot step. The follow-up public read then has to succeed, or the node
   exits and restarts cleanly, as it did in 9 sibling timelines. Only 870 s of unbroken
   partitions every few seconds makes that combination common.
3. **Recovery mode is a documented state,** and the docs tell operators to restart a node to leave
   it.

**Why it doesn't hold:**

- On argument 1: Guarantee 2 is about rejoining, and the docs promise that a restarted node rejoins
  by itself from the material on storage. Here the material was there and readable seconds later,
  yet the node never rejoins.
- It also fails silently: the node passes readiness and liveness, so neither Kubernetes nor a
  probe-based alert ever reacts. The cluster runs with no fault margin indefinitely, which is
  exactly the risk Guarantee 2's rationale names.
- On argument 2: narrowness bears on severity, not validity. The window is a few seconds of S3
  unavailability during a restart, and restarts often happen during incidents. The result is
  permanent and out of all proportion to a transient error. The mechanism recurred in a second run
  without timing fuzzing.
- On argument 3: the docs tie recovery mode to an *absent* key, and the restart instruction belongs
  to the custodian-recovery flow. The SUT's own migration and seed readers treat "unreadable" as an
  error, not absence, so `boot_base_kms` is the outlier.

## What would change the verdict

- **To `harness-caused`:** evidence that the listing error came from harness configuration rather
  than the partition. For example, a MinIO policy or path that fails `ListObjectsV2` on
  `kms-private/PRIV-p2/SigningKey/`. The successful reads at 919.25 and 1100.82 argue against this.
  Another route would be a harness process found to restart, pause or reconfigure kms-core-2
  between 1053 and 1100.
- **To "intended behaviour, documentation gap"** (still worth reporting, but not a breach): a Zama
  statement or runbook that any storage error at boot is meant to enter recovery mode, together
  with an alert or probe that restarts such a node. None exists in this tree.
- **Narrower reach:** if hunts 5–7 and further runs only ever show it under unbroken fault windows,
  the finding stays real but its likelihood in production is lower. Outcome: hunts 5–7 (two
  strobed, two with timing fuzzing) didn't reproduce it, so this narrower reading applies: two
  entries into recovery mode in ten long runs searched, one of them exercised by the checker.
