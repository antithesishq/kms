<a id="storage-error-enters-recovery-mode"></a>
# A storage error while a core boots leaves it in recovery mode, refusing every decryption

Name: `storage-error-enters-recovery-mode` · Guarantee: [Guarantee 2](../guarantees.md#guarantee-2) ·
Build: current (upstream [`4a644c85`](https://github.com/zama-ai/kms/commit/4a644c8546abc8b002b7e45c19bf195996e7d229) plus coverage instrumentation) · Classified `real` by the false-positive review
([entry](../false-positives.md#storage-error-enters-recovery-mode)) · Adversarial review:
[adversarial/storage-error-enters-recovery-mode.md](../adversarial/storage-error-enters-recovery-mode.md)

## Where it was seen

- **Run:** [hunt-current-3](../runs/hunt-current-3.md) (`4e338bff64a6f329ebadc856cace0692-64-4`, 105 m, default
  fault set plus timing fuzzing). One checker execution fails because of it: the first
  counterexample of the Guarantee 2 property, at vtime 1405.556
  ([digest section](../runs/hunt-current-3.md#failing-public-decryption-answered-by-all-four-cores-succeeds-within-300-s-of-every-core-accepting-connections),
  log [hunt-current-3-g2decrypt-7353950694920754647.ndjson](../logs/hunt-current-3-g2decrypt-7353950694920754647.ndjson)).
- **The same entry into recovery mode in another run:** [hunt-current-1](../runs/hunt-current-1.md)
  (`8196fb3cff90b7a677b4394f5e24e550-64-4`, no timing fuzzing): kms-core-1 logs "SIGNING KEY NOT
  AVAILABLE, ENTERING RECOVERY MODE!!!!" at vtime 912.49 (input_hash -5663972180894011767,
  restart_count 0; search result [recovery-mode-8196fb3c.json](../logs/recovery-mode-8196fb3c.json)).
  No decryption reached that core in recovery mode in that history ("booted in recovery mode": 0
  events in the run), so Guarantee 2 wasn't checked against it there.
- Searches for "ENTERING RECOVERY MODE" in hunt-current-2, -4, -5, -6 and -7, the fix check and both
  pre-fix hunts return nothing (searches of the finished runs at 10:58 and 11:05 UTC, no errors;
  outputs `recovery-mode-<run>.json` in [logs/](../logs/)).

## What happened (hunt-current-3, the failing history)

1. kms-core-2's pod is killed at 690.62 under continuous network faults. Its new kms-server starts at
   862.89 and spends about 238 s reading its private and public material from MinIO.
2. At 1085.75 a 6.7 s partition cuts every core off from MinIO.
3. At 1089.59 kms-core-2 logs `Failed to read SigningKey from "S3 storage with bucket kms-private":
   Getting all ids failed: dispatch failure`, and at 1089.64 "SIGNING KEY NOT AVAILABLE, ENTERING
   RECOVERY MODE!!!!" ([`backup_operator.rs:861`](../../../core/service/src/engine/backup_operator.rs#L861)).
4. Faults stop at 1100.67. kms-core-2 logs "Initializing KMS without a signing key. ONLY BACKUP
   RECOVERY OPERATIONS WILL BE POSSIBLE." and serves on 0.0.0.0:50100 from 1100.82. Its readiness
   probe passes, so Kubernetes treats it as healthy. All four cores accept connections by 1114.60.
5. For 300 s the checker sends 27 fresh public decryptions. kms-core-2 refuses every one with gRPC
   code 9, "Signing key is not present. This should only happen when server is booted in recovery
   mode". Cores 1, 3 and 4 decrypt and sign each one. No core restarts in that span.
6. The Guarantee 2 Always fails at 1405.556: "all cores accepted connections after 0 s; decryption
   ok=false after 27 attempt(s)".

## The code path

[`boot_base_kms`](../../../core/service/src/engine/backup_operator.rs#L850) calls
[`get_core_signing_identity`](../../../core/service/src/vault/storage/crypto_material/utils.rs#L433)
and treats **any** error as "this node lost its signing key": it boots
`BaseKmsStruct::new_no_signing_key`, recovery mode. The read error here was a transient S3
"dispatch failure" during a partition, not a missing key. The same file's doc comment describes
recovery mode as the path for "a node that lost it". Nearby code makes the distinction this path
doesn't: the root signing seed's reader returns `None` only for an absent seed, and says "a seed
that is present but unreadable is an error, not an absent seed"
([`utils.rs`](../../../core/service/src/vault/storage/crypto_material/utils.rs#L426-L432)). Other storage
errors at boot end the process, and Kubernetes restarts it
([core-exits-when-storage-unreachable-at-boot](../false-positives.md#core-exits-when-storage-unreachable-at-boot)).
A core in recovery mode stays there until something restarts it.

## Not the same as the other Guarantee 2 counterexamples in that run

47 of the 48 counterexamples come from a second checker execution (started at 1196.45). There, the
client's decryption attempt stalled before contacting any core while the whole test VM went quiet
for about 290 s, and recovery mode doesn't appear. That one is an environment stall:
[recovery-check-attempt-outlives-timeout](../false-positives.md#recovery-check-attempt-outlives-timeout).

## Adversarial review

Verdict **stands**: [adversarial/storage-error-enters-recovery-mode.md](../adversarial/storage-error-enters-recovery-mode.md).
In short: recovery mode is chosen inside unmodified upstream code, with no harness step between the
fault and the symptom; the key was present (read at 919.25, and again without error at 1100.82);
the same boot's migration step treats the same read error as fatal; production uses S3 with the
SDK's default retries and the same probes, which stay SERVING in recovery mode; and the same entry
into recovery mode happens without timing fuzzing in [hunt-current-1](../runs/hunt-current-1.md), where the boot
finished in recovery mode in 5 timelines (914.7–917.1).
