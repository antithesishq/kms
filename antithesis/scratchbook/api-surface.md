---
sut_path: /home/exedev/kms
commit: b460896e00add082925d43818d4960ed9fb8cdd8
updated: 2026-10-19
---

# API Surface: Zama KMS

## Summary

| Field | Value |
|---|---|
| System | Zama KMS (threshold mode, `insecure` build) |
| Tier 0 confirmed by user | yes |
| Operations | 32 |

The Zama KMS holds FHE key material as secret shares across `n` parties. It runs MPC protocols to generate keys and CRSs, and to decrypt ciphertexts in public or to one user's key. The harness runs threshold mode with n = 4 and t = 1, the `insecure` cargo feature, the mock enclave and `Test` FHE parameters.

Conventions in this file:

- All RPCs are on `kms_service.v1.CoreServiceEndpoint` on the service port 50100, unless a section says otherwise. With the `insecure` feature, the server is generated from `core/grpc/proto/kms-service-insecure.v1.proto` instead of `kms-service.v1.proto` (`core/grpc/build.rs`). That proto adds the `Insecure*` and `PartialKeyGenPreproc` RPCs.
- Every operation runs on one core. A caller sends the same request to every core, and `kms-core-client` does this.
- **Requires** lists only operations that a workload has to call itself. Two things exist at deploy, so no operation lists them. The default MPC context `0700…0001` is written by `kms-server` at every boot from `[threshold.peers]`. The default epoch `0800…0001` is created by the `kms-init` Job, which runs `epoch.create` once.
- Every start operation takes tokens from one rate-limiter bucket per core. In the harness the bucket holds 51000 tokens, and `preproc.start_insecure` needs 50000 of them free when it is called.
- Code locations are for threshold mode. Centralized mode serves the same RPCs from `core/service/src/engine/centralized/`.

## Index

| ID | Name | Tier | Feature group | Kind |
|---|---|---|---|---|
| `preproc.start_insecure` | Start insecure keygen preprocessing | 0 | — | data |
| `preproc.get_insecure_result` | Get insecure keygen preprocessing result | 0 | — | data |
| `keygen.start_insecure` | Start insecure key generation | 0 | — | data |
| `keygen.get_insecure_result` | Get insecure key generation result | 0 | — | data |
| `pubdec.start` | Start public decryption | 0 | — | data |
| `pubdec.get_result` | Get public decryption result | 0 | — | data |
| `userdec.start` | Start user decryption | 0 | — | data |
| `userdec.get_result` | Get user decryption result | 0 | — | data |
| `keygen.abort` | Abort key generation | 1 | — | data |
| `pubdec.sync` | Public decryption (sync) | 1 | — | data |
| `userdec.sync` | User decryption (sync) | 1 | — | data |
| `crs.start` | Start CRS generation | 2 | `crs` | data |
| `crs.get_result` | Get CRS generation result | 2 | `crs` | data |
| `crs.start_insecure` | Start insecure CRS generation | 2 | `crs` | data |
| `crs.get_insecure_result` | Get insecure CRS generation result | 2 | `crs` | data |
| `crs.abort` | Abort CRS generation | 2 | `crs` | data |
| `epoch.reshare` | Create MPC epoch with resharing | 2 | `reshare` | admin |
| `epoch.get_result` | Get epoch result | 2 | `reshare` | admin |
| `context.create` | Create MPC context | 3 | `mpc-admin` | admin |
| `context.destroy` | Destroy MPC context | 3 | `mpc-admin` | admin |
| `epoch.create` | Create MPC epoch (PRSS only) | 3 | `mpc-admin` | admin |
| `epoch.destroy` | Destroy MPC epoch | 3 | `mpc-admin` | admin |
| `custodian.create` | Create custodian context | 3 | `backup` | admin |
| `custodian.destroy` | Destroy custodian context | 3 | `backup` | admin |
| `recovery.get_operator_key` | Get operator public key | 3 | `backup` | admin |
| `recovery.init` | Start custodian recovery | 3 | `backup` | admin |
| `recovery.custodian_recover` | Finish custodian recovery | 3 | `backup` | admin |
| `recovery.restore` | Restore private storage from backup | 3 | `backup` | admin |
| `material.list` | List key material | 3 | — | admin |
| `metastore.get_statuses` | Get request statuses | 3 | `request-status` | admin |
| `metastore.list` | List requests | 3 | `request-status` | admin |
| `metastore.info` | Get meta-store info | 3 | `request-status` | admin |

## Feature Groups

| ID | Description |
|---|---|
| `crs` | Generate, read and abort a ZK common reference string (Tier 2) |
| `reshare` | Reshare key shares into a new epoch, and read the result (Tier 2) |
| `mpc-admin` | Create and destroy MPC contexts and PRSS-only epochs (Tier 3) |
| `backup` | Custodian-based backup and recovery; needs a `[backup_vault]` section that the harness does not set (Tier 3) |
| `request-status` | Query the request meta stores through `MetaStoreStatusService` (Tier 3) |

## Flagged

Left out on purpose (the user confirmed this scope after Phase 1):

- The secure DKG: `KeyGenPreproc`, `GetKeyGenPreprocResult`, `PartialKeyGenPreproc`, `KeyGen` and `GetKeyGenResult` (`core/service/src/engine/threshold/service/preprocessor.rs`, `key_generator.rs`; CLI `preproc-key-gen`, `preproc-key-gen-result`, `partial-preproc-key-gen`, `key-gen`, `key-gen-result`). The customer does not test it in Antithesis. The insecure keygen in Tier 0 shares most of its code (`RealKeyGenerator.inner_key_gen`), and `GetKeyGenResult` reads the same store as `GetInsecureKeyGenResult`.
- `GetHealthStatus` (`core/service/src/engine/threshold/endpoint.rs:get_health_status`): a health endpoint. It reports this core's key material, and it runs core-to-core health-check sessions to report peer reachability. `kms-health-check live` and `full` call it.
- `BandwidthBenchmark` (`core/service/src/engine/threshold/endpoint.rs:bandwidth_benchmark`; `kms-health-check bandwidth-bench`): a benchmark endpoint.
- The `grpc.health.v1.Health` services on the service port (50100) and on the core-to-core port (50001).
- The HTTP endpoints on the metrics port (9646): `/metrics`, `/healthz`, `/health`, `/ready`, `/liveness`, `/live` and `/version` (`observability/src/telemetry.rs`).
- The core-to-core MPC networking service on port 50001 (`core/threshold-networking/`). It carries internal traffic between parties.
- CLI commands that send no RPC: `kms-core-client encrypt` (client-side encryption), `do-nothing`, and `new-testing-mpc-context-file` (`testing` feature; it writes a context file on the client).
- Offline tools that send no RPC: `kms-gen-keys`, `kms-gen-tls-certs`, and `kms-custodian generate|verify|decrypt`. The output of `kms-custodian generate` feeds `custodian.create`, and the output of `kms-custodian decrypt` feeds `recovery.custodian_recover`. `kms-init` sends `epoch.create` and polls `epoch.get_result`.
- Public storage reads: clients read public keys, CRSs and verification keys over HTTP from the S3 bucket (MinIO in the harness), not from the KMS.

Harness limits that a workload must work around:

- The harness core config (`antithesis/config/manifests/31-kms-core-1.yaml` to `34-kms-core-4.yaml`) has no `[backup_vault]` section. So every operation in the `backup` group fails there.
- `context.create` has no usable CLI path in the harness. `new-mpc-context context-toml` is `unimplemented!()`, and only the `testing` build can write a serialized context file. A driver must build `NewMpcContextRequest` itself.
- `custodian-recovery-init`, `custodian-backup-recovery` and `destroy-custodian-context` refuse a client config with more than one core. The harness client config lists 4 cores.
- No client flag builds a `DecompressionOnly` keyset config, so that keygen variant is reachable only through raw gRPC.
- `GetUserDecryptionResult` and `GetEpochResult` have no CLI command of their own. Only `user-decrypt` and `new-epoch` (and `kms-init`) poll them.
- Not verified: whether `kms-core-client get-operator-public-key` accepts the attestation document of the mock enclave.

Conflicts between docs and code:

- Request IDs: the protos say lower-case hex without `0x`. The parser (`core/grpc/src/identifiers.rs`) also accepts upper case, a `0x` prefix and surrounding whitespace, and it rejects the all-zero ID.
- The service-level comment in `kms-service.v1.proto` says that `InvalidArgument` uses up the request ID. For public and user decryption, validation runs before the meta-store insert, so a rejected ID stays free.
- `domain`: the proto calls it optional ("should be set") for `PublicDecrypt`, `CrsGen` and a reshare, and does not list it for `KeyGenPreproc`. The code rejects a missing domain with `InvalidArgument` in all four.
- `NewMpcEpoch` is documented as synchronous. It returns once a background task starts, and completion shows only through `GetEpochResult`.
- `NewMpcEpochRequest.epoch_id` must increase, says `kms.v1.proto`. Creation does not check this. Boot loads each key's metadata from the greatest epoch ID that holds it.
- `UserDecryptionRequest.enc_key` is documented as a bincode v1 ML-KEM-512 key. The code expects a tfhe safe-serialized `UnifiedPublicEncKey` that holds an ML-KEM-512 key. `docs/references/api/core_grpc.md` describes a `crypto_box` key and a different `digest` layout.
- `kms-service.v1.proto` says that `KeyGenPreproc` and `GetKeyGenPreprocResult` return an error on the centralized KMS. The centralized endpoint stores and returns a dummy entry.
- `kms-service.v1.proto` calls the `GetKeyGenPreprocResult` response "an empty structure". It carries `preprocessing_id`, `external_signature` and `signatures`.
- The `KeyGenRequest.params` comment says that an unset value on the insecure endpoint means the default parameters. Threshold mode uses the parameters stored with the preprocessing.
- The `KeyGen` doc says `keyset_added_info` matters only for `DecompressionOnly`. `UseExisting` also needs it. The doc also says `keyset_config` must match the preprocessing request. The server does not compare them.
- The `AbortKeyGen` and `AbortCrsGen` post-conditions say all data of the ID is removed. The aborted entry stays in its meta store, so the result RPC gives `Aborted` and the ID gives `AlreadyExists` until a restart.
- `kms-service.v1.proto` marks `GetOperatorPublicKey`, `RestoreFromBackup`, `CustodianRecoveryInit` and `CustodianBackupRecovery` as "not fully implemented yet". All four are implemented in `core/service/src/engine/backup_operator.rs` and tested in `core/service/src/client/tests/{threshold,centralized}/custodian_backup_tests.rs`. The insecure proto has no such warning.
- The `GetKeyMaterialAvailability` doc lists a total key count. `KeyMaterialAvailabilityResponse` has no such field.
- `metastore-status.v1.proto` and `README-metastore-status.md` say `ListRequests` uses the store capacity as the default page size. The code uses 100, with a maximum of 1000. The README calls `ListRequests` with `ALL`, which the code rejects. The README status list leaves out `DELETED`. The rustdoc of `get_request_statuses` says it fails on an empty ID list, but it returns OK.
- `MetaStoreStatusService` does not expose the epoch and custodian meta stores: `MetaStoreType` has no value for them.
- `docs/references/api/core_grpc.md` is out of date. Its `KeySetAddedInfo`, `StandardKeySetConfig` and CRS messages use old layouts, and it has no `signing_schemes` or `signatures`. It has no sections for `AbortKeyGen`, `PartialKeyGenPreproc`, `InsecureCrsGen`, `AbortCrsGen`, `NewMpcContext`, `DestroyMpcContext`, `NewMpcEpoch`, `GetEpochResult` or `DestroyMpcEpoch`.
- `docs/guides/entry_points.md` says that resharing is "coming soon". It is `NewMpcEpoch` with `previous_epoch`.
- `docs/guides/kms-server-bin.md` ("kms-init") gives the old storage path `PRIV-pX/PrssSetup/` and says that a new init needs a manual delete. The code stores `EpochData/<epoch_id>`, and `NewMpcEpoch` and `DestroyMpcEpoch` add and remove epochs.
- `docs/guides/core_client.md`:
  - It documents `new-mpc-context context-toml`, which is `unimplemented!()`.
  - Its `new-epoch` example uses `epoch-id:` and `crs_id:`. The parser accepts only `epoch_id:` and `crs_id=`.
  - It says that `new-custodian-context` works on one core only. The code sends it to every core.
  - Its custodian e2e example reuses the MPC context ID as the custodian context ID. The client makes a random custodian context ID and prints it.
  - "Backup restoring" says a restore fails on existing entries. The code skips them.
  - It says backups hold all private data "except PRSS setup data". The code backs up and restores `EpochData` and the legacy PRSS types.
  - It shows `custodian-recovery-init -o true`. `-o` is a flag with no value, so `-o true` probably does not parse (not run).
  - It does not document `abort-key-gen`, the `-u` and `--from-existing-shares` flags of `preproc-key-gen`, or the positional `[CONTEXT_ID] [EPOCH_ID]` arguments of `key-gen`.
- `core-client/tests/README.md` describes `GetOperatorPublicKey` as a verification-key fetch and `BackupRestore` as an AWS KMS restore. The RPC returns the backup encryption key of the active custodian context, and the restore also works on unencrypted vaults.
- `ai-docs/ARCHITECTURE.md` says a node in recovery mode "serves only backup recovery". No code gates RPCs in recovery mode. It also says `RestoreFromBackup` is for the AWS KMS path. It also serves unencrypted vaults, and `CustodianBackupRecovery` calls it.
- The rustdoc of `RealBackupOperator::custodian_recovery_init` says it restores the most recent backup. It restores nothing and returns a `RecoveryRequest`.
- The header of `antithesis/config/manifests/40-kms-core-init.yaml` and a comment in `first_generate_key.sh` say that `kms-init` creates the context. It creates only the epoch.
- `parallel_driver_public_decrypt.sh` says that `--max-iter` counts 0.5 s polls. Each result call can wait up to 60 s on the server.

## Tier 0: Core

### `preproc.start_insecure`: Start insecure keygen preprocessing

- **What it does:** Records a dummy preprocessing entry with no material and no MPC (the ID, the DKG parameters and the signatures over the ID). Only `keygen.start_insecure` can consume it.
- **Tier reason:** First step of the harness keygen (`antithesis/test/v1/public_decrypt/first_generate_key.sh`, default path). `docs/guides/core_client.md` documents it under "Insecure (Dummy) Preprocessing", and it is the top-level CLI command `insecure-preproc-key-gen`. The customer does not test the secure DKG in Antithesis, so this is the only preprocessing in scope. Tier 0 confirmed by the user at the checkpoint.
- **Notes:**
  - **Synchronous:** the entry is finished when the call returns `Ok`. There is no background task and no core-to-core session. Each core stores its own entry, so the caller must send the request to every core (the CLI does).
  - Checks run in this order:
    1. Rate limiter: needs `preproc` tokens (default 25000, harness 50000) free at the moment of the call, from the bucket shared by all operations (default 50000, harness 51000). They are released when the call returns. In the harness this gives `ResourceExhausted` whenever other operations hold more than 1000 tokens, for example two running keygens.
    2. Request validation: `InvalidArgument` (bad or missing request ID, bad context or epoch ID, bad `params`, bad `keyset_config`, missing or bad `domain`, unknown signing scheme). `keyset_config` is parsed and must be valid, but is otherwise ignored.
    3. Signing identity: `FailedPrecondition` if the node has no signing key (recovery boot), `InvalidArgument` if a requested scheme needs a root signing seed that the node lacks.
    4. Context and epoch exist and this core has a role in the context: `NotFound` otherwise.
    5. Insert into preproc-requests: `AlreadyExists` if the ID is there in any state.
    6. Signature computation: `Internal` on failure, which leaves the ID as a failed entry.
  - **Kind check:** the stored entry is of the insecure kind. The secure RPCs `GetKeyGenPreprocResult` and `KeyGen` reject it with `FailedPrecondition`.
  - **Request-ID reuse:** there is no redo path. The preprocessing store is in memory only (`MetaStore::new_unlimited`, not reloaded at boot). A core restart loses every entry, after which `preproc.get_insecure_result` and `keygen.start_insecure` give `NotFound` for it, and the old ID can be used again.
  - **What the entry records:** the ID, the DKG parameters and the signatures, but not the `keyset_config`, `context_id` or `epoch_id`. `keygen.start_insecure` does not compare these with its own request.
  - It never runs in the background, so `keygen.abort` cannot cancel it. `keygen.abort` with its ID gives `NotFound` unless an insecure keygen that consumed it is running.
  - **CLI:** `insecure-preproc-key-gen` makes a random request ID, uses the dummy domain, sends `keyset_config` unset and `params` from the client config. It needs all n cores to accept and to return a result through `GetInsecureKeyGenPreprocResult`, checks the signatures, and prints `insecure preproc done`.
  - **Harness:** the default path of `antithesis/test/v1/public_decrypt/first_generate_key.sh` (`KMS_WORKLOAD_KEYGEN` unset or `insecure`) runs `kms-core-client -f config.toml --max-iter 1200 insecure-preproc-key-gen` with no context or epoch flags, so the default context and the kms-init epoch are used. It then runs `insecure-key-gen --preproc-id <id>`. The pair is tried up to 5 times, 10 s apart, each time with a fresh ID. The script runs once per timeline, before any driver and with no faults.
  - **Centralized:** identical to `KeyGenPreproc` (both dummy), and the entries are interchangeable between the two keygen RPCs.

| Field | Value |
|---|---|
| ID | `preproc.start_insecure` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/InsecureKeyGenPreproc` (insecure proto only); `kms-core-client -f config.toml insecure-preproc-key-gen [--context-id <id>] [--epoch-id <id>]` |
| Requires | — |
| Enabled by | `insecure` cargo feature (server and client) |
| Changes state | preproc-requests, preprocessing |
| Reads state | mpc-contexts, epochs, signing-keys |
| Related | `preproc.get_insecure_result`, `keygen.start_insecure`, `keygen.abort`, `material.list`, `metastore.get_statuses`, `metastore.list`, `metastore.info` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:insecure_key_gen_preproc`, `core/service/src/engine/threshold/service/preprocessor.rs:RealPreprocessor.inner_insecure_key_gen_preproc`, `core/service/src/engine/threshold/service/kms_impl.rs:new_insecure_preproc_bucket` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | Required. 32 bytes, so 64 hex chars. The server also accepts upper-case hex, a `0x` prefix and surrounding whitespace. All zeros, a bad length or a missing value gives `InvalidArgument`. Must be new to preproc-requests. Later passed to `insecure-key-gen` as `preproc_id`. CLI: random. |
| params | FheParameter enum | `default`=0 (`BC_PARAMS_SNS`) or `test`=1 (`PARAMS_TEST_BK_SNS`), else `InvalidArgument`. Not optional in proto3, so unset means `default`. Stored in the entry; `keygen.start_insecure` uses it when its own `params` is unset. Harness `Test`. |
| keyset_config | optional KeySetConfig | Parsed, then ignored. `keyset_type`: `Standard`=0 (then `standard_keyset_config` is required, else `InvalidArgument`) or `DecompressionOnly`=1. `compute_key_type`: `CPU`=0 only. `secret_key_config`: `GenerateAll`=0 or `UseExisting`=1. Unknown values give `InvalidArgument`. The CLI leaves it unset. |
| domain | Eip712DomainMsg | Required: missing gives `InvalidArgument` ("missing domain"). `verifying_contract` must be an EIP-55 checksummed address, `chain_id` big-endian bytes (at most 32), `salt` if set exactly 32 bytes. The CLI uses the dummy domain ("Authorization token", "1", chain 8006, `0x66f9664f97F2b50F62D13eA064982f936dE76657`). |
| context_id | RequestId | Optional; default `DEFAULT_MPC_CONTEXT` (`0700…0001`, written at boot from `[[threshold.peers]]`); unknown gives `NotFound`. |
| epoch_id | RequestId | Optional; default `DEFAULT_EPOCH_ID` (`0800…0001`, created by kms-init); must be an epoch of the context on this core, else `NotFound`. Not stored in the entry. |
| extra_data | bytes | Not validated: a bad format only logs a warning. Signed into `external_signature`. Known formats: version 0 (1 byte), 1 (`0x01` ‖ context_id, 33 bytes), 2 (`0x02` ‖ context_id ‖ epoch_id, 65 bytes). The CLI sends version 2. |
| signing_schemes | repeated SigningSchemeType | `ECDSA256K1`=0, `ED25519`=1, `MLDSA44`=2, `MLDSA65`=3, `MLDSA87`=4. Empty means [ECDSA256K1]. Duplicates are dropped. An unknown value gives `InvalidArgument`. Non-ECDSA schemes need a root signing seed on the node, else `InvalidArgument`. CLI: the global `--signing-schemes a,b`. |
| (config) `rate_limiter_conf.preproc` | u32 tokens | Default 25000 of `bucket_size` 50000; harness 50000 of 51000. Must be free when the call arrives; released when it returns. |

### `preproc.get_insecure_result`: Get insecure keygen preprocessing result

- **What it does:** Returns this core's ID and signatures for an insecure preprocessing entry.
- **Tier reason:** `insecure-preproc-key-gen` calls it to confirm that every core holds the entry before `insecure-key-gen` runs. It is the read-back for `preproc.start_insecure`. Tier 0 confirmed by the user at the checkpoint.
- **Notes:**
  - **Long poll:** if the entry is still pending, the call waits up to `DURATION_WAITING_ON_PREPROC_RESULT_SECONDS` (300 s), then gives `Unavailable`. Insecure entries are written before the start call returns, so in practice this call never waits.
  - Responses:
    - Bad ID: `InvalidArgument`.
    - Unknown ID, ID already consumed by `keygen.start_insecure`, or entry lost in a restart: `NotFound`.
    - Failed: `Internal`, or `Aborted` when the stored error text contains "abort".
    - The ID holds a real entry from the secure `KeyGenPreproc` or `PartialKeyGenPreproc`: `FailedPrecondition`.
  - Read-only. A successful read does not consume the entry.
  - **CLI:** `insecure-preproc-key-gen-result -i <id>` polls every core and needs a result from all of them. It does not check signatures. `insecure-preproc-key-gen` calls the same RPC and does check them.
  - **Centralized:** same as `GetKeyGenPreprocResult`.

| Field | Value |
|---|---|
| ID | `preproc.get_insecure_result` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetInsecureKeyGenPreprocResult` (insecure proto only); `kms-core-client -f config.toml insecure-preproc-key-gen-result -i <request_id>` |
| Requires | `preproc.start_insecure` |
| Enabled by | `insecure` cargo feature (server and client) |
| Changes state | — |
| Reads state | preproc-requests |
| Related | `preproc.start_insecure`, `keygen.start_insecure` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_insecure_key_gen_preproc_result`, `core/service/src/engine/threshold/service/preprocessor.rs:RealPreprocessor.get_insecure_result`, `core/service/src/engine/threshold/service/preprocessor.rs:RealPreprocessor.inner_get_result` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | 64 hex chars; `0x` prefix, upper case and surrounding whitespace accepted; all zeros or a bad length gives `InvalidArgument`. The ID used with `InsecureKeyGenPreproc`. |

### `keygen.start_insecure`: Start insecure key generation

- **What it does:** A test-only key generation that consumes an insecure preprocessing entry. Party 1 generates the keyset in the clear and secret-shares the private key to the other cores over the core-to-core network. Each core's private key shares go to private storage and the public keys to public storage, under (request_id, epoch_id). It returns at once; the work runs in the background.
- **Tier reason:** It creates the FHE key that every decryption needs. It is the default keygen of `first_generate_key.sh`. `docs/guides/entry_points.md` ("Insecure mode") describes it as the fast setup for tests. The customer does not test the secure DKG in Antithesis, so this is the only keygen in scope. Tier 0 confirmed by the user at the checkpoint.
- **Notes:**
  - Async. Admission is serialised per core by a lock shared with the secure `KeyGen` (`serial_lock`); the background tasks run concurrently. Checks run in this order:
    1. Rate limiter: takes `keygen` tokens (default 1000, harness 1000) from the bucket shared by all operations (default 50000, harness 51000). The tokens are held until the background task ends. An empty bucket gives `ResourceExhausted`.
    2. Request validation: `InvalidArgument` (bad or missing request ID, bad `preproc_id` format, bad context or epoch ID, `keyset_config` and `keyset_added_info` that do not fit together, bad `params`, missing or bad `domain`, unknown signing scheme).
    3. Context and epoch exist and this core has a role in the context: `NotFound` otherwise.
    4. Preprocessing lookup: `preproc_id` missing gives `InvalidArgument`. Absent, already consumed, or lost in a restart gives `NotFound`. Failed gives `Internal`. A real entry from the secure `KeyGenPreproc` gives `FailedPrecondition`.
    5. No FHE keys already stored at (request_id, epoch_id): `AlreadyExists` otherwise.
    6. Insert into keygen-requests: `AlreadyExists` if the ID is there in any state.
    7. After the insert: session setup (`Internal`), signing identity (`FailedPrecondition` with no signing key, `InvalidArgument` for an unsupported scheme), reading the existing key for `UseExisting` (`Internal`), and another keygen already running on the same `preproc_id` (`AlreadyExists`).
  - **Request-ID reuse:** there is no redo path. A failure in step 7 leaves the request ID as a failed entry. At boot, keygen-requests is reseeded from the key info in private storage (the greatest epoch per key ID), so a completed key ID keeps giving `AlreadyExists` after a restart, while failed or in-flight IDs are forgotten.
  - **Preprocessing consumption:** the preprocessing entry is tombstoned only after every check passes, just before the background task starts. A rejected request leaves it usable. Once consumed, later keygens and `preproc.get_insecure_result` give `NotFound` for it.
  - **Parameters:** `params` unset means the parameters stored by the insecure preprocessing (see Flagged). If set, the request's parameters win without a compatibility check.
  - **Variants** (by `keyset_config`):
    - Standard, `GenerateAll`, `CompressedAll` (the default when unset, and the CLI default): a compressed XOF keyset plus a compact public key.
    - Standard, `GenerateAll`, `CompressedNone` (CLI `-u`): uncompressed `PublicKey` and `ServerKey`.
    - Standard, `UseExisting`, `CompressedAll`: party 1 reconstructs the existing secret key (read at `epoch_id`), rebuilds the compressed keyset from it, and re-shares the same key.
    - Standard, `UseExisting`, `CompressedNone`: accepted, but fails in the background ("only supported for compressed keysets"), so `keygen.get_insecure_result` gives `Internal`.
    - `DecompressionOnly`: reconstructs the GLWE and compression key shares of the from and to keysets and derives the decompression key. The CLI cannot send this variant.
  - **Outcome:** on success the core writes its `ThresholdFheKeys` (private storage, `FheKeyInfo`) and the public key material (public storage), copies them to the backup vault if one is configured (the harness configures none), and marks the request done. A failure is stored and `keygen.get_insecure_result` gives `Internal`. `keygen.abort` with the `preproc_id` while the task runs gives `Aborted`. Key material is written only after generation finishes, so an aborted run writes none.
  - Every core must get the request and take part. `docs/guides/entry_points.md` says it takes only a few seconds, so a `keygen.abort` has a short window to land.
  - **Lifecycle:** the proto says no `NewMpcEpoch`, `DestroyMpcEpoch` or `DestroyMpcContext` may run at the same time. This is a rule for callers.
  - **CLI:** `insecure-key-gen` makes a random request ID and takes the domain from the client config `[default_domain]`, falling back to the dummy domain. It takes `params` from `fhe_params` and always sends an explicit Standard `keyset_config`. It sends the request to every core and needs `num_majority` acceptances (harness 2; with `-a`, all cores). It then polls `GetInsecureKeyGenResult` every 500 ms up to `--max-iter`, downloads the public keys from S3, checks digests and signatures, and prints `insecure keygen done`. The context and epoch are optional positional arguments, not `--context-id`/`--epoch-id`.
  - **Harness:** this is the default keygen of `antithesis/test/v1/public_decrypt/first_generate_key.sh`, which runs `kms-core-client -f config.toml --max-iter 1200 insecure-key-gen --preproc-id <id>` once per timeline before the drivers. So the key uses: `Test` parameters, Standard/`GenerateAll`/`CompressedAll` (no `-u`), the default context and epoch `0800…0001`, ECDSA only, and the dummy domain. Success needs 2 of 4 cores (`num_majority`). Up to 5 attempts, 10 s apart, each with a fresh preprocessing and key ID. The script records the preprocessing ID in `/tmp/kms-workload-state/preproc/<key_id>`, because `anytime_reshare_key.sh` (`epoch.reshare`) must name each key's `preproc_id`.
  - **Centralized:** the key is generated locally, and either preprocessing kind is accepted.

| Field | Value |
|---|---|
| ID | `keygen.start_insecure` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/InsecureKeyGen` (insecure proto only); `kms-core-client -f config.toml insecure-key-gen -i <preproc_id> [-u] [--existing-keyset-id <id>] [--use-existing-key-tag] [--copy-compressed-key-to-original] [CONTEXT_ID] [EPOCH_ID]` |
| Requires | `preproc.start_insecure` |
| Enabled by | `insecure` cargo feature (server and client) |
| Changes state | keygen-requests, keysets, preprocessing, preproc-requests, mpc-sessions |
| Reads state | preprocessing, preproc-requests, keysets, mpc-contexts, epochs, signing-keys |
| Related | `preproc.start_insecure`, `keygen.get_insecure_result`, `keygen.abort`, `pubdec.start`, `userdec.start`, `epoch.reshare`, `epoch.destroy`, `material.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:insecure_key_gen`, `core/service/src/engine/threshold/service/key_generator.rs:RealInsecureKeyGenerator.insecure_key_gen`, `core/service/src/engine/threshold/service/key_generator.rs:RealKeyGenerator.key_gen_background` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | Required. 32 bytes, so 64 hex chars. The server also accepts upper-case hex, a `0x` prefix and surrounding whitespace. All zeros, a bad length or a missing value gives `InvalidArgument`. Must be new to keygen-requests, and no keys may be stored at (request_id, epoch_id). Becomes the key ID that decryptions use. CLI: random. |
| params | optional FheParameter enum | `default`=0 (`BC_PARAMS_SNS`) or `test`=1 (`PARAMS_TEST_BK_SNS`), else `InvalidArgument`. Unset means the parameters stored with the insecure preprocessing. The CLI always sets it (harness `Test`). |
| preproc_id | RequestId | Required (`InvalidArgument` if missing or malformed). Must be a finished, unconsumed insecure preprocessing entry on this core (`preproc.start_insecure`). See the Notes for the codes in every other case. CLI `-i/--preproc-id`, required. |
| domain | Eip712DomainMsg | Required: missing gives `InvalidArgument`. `verifying_contract` must be an EIP-55 checksummed address, `chain_id` big-endian bytes, `salt` if set exactly 32 bytes. Used to sign the result. CLI: `[default_domain]` or the dummy domain; the harness has no `[default_domain]`, so it uses the dummy. |
| keyset_config | optional KeySetConfig | Unset means Standard {CPU, `GenerateAll`, `CompressedAll`}. `keyset_type`: `Standard`=0 (then `standard_keyset_config` is required, else `InvalidArgument`) or `DecompressionOnly`=1. `compute_key_type`: `CPU`=0 only. `secret_key_config`: `GenerateAll`=0 or `UseExisting`=1. `compressed_key_config`: `CompressedAll`=0 or `CompressedNone`=1; any other value is read as `CompressedAll`. Unknown values for the other enums give `InvalidArgument`. Supported variants are listed in the Notes. |
| keyset_added_info.existing_keyset_id | RequestId | Required and parseable when `UseExisting` is set, else `InvalidArgument`. Ignored otherwise. The keyset must exist at (existing_keyset_id, epoch_id). CLI `--existing-keyset-id`. |
| keyset_added_info.use_existing_key_tag | bool | Default false. `UseExisting` only: reads the tag from the existing keyset's public material; a read failure gives `Internal`. CLI `--use-existing-key-tag`. |
| keyset_added_info.copy_compressed_key_to_original | bool | Default false. Only acted on with `UseExisting` and `CompressedAll`: copies the new compressed keyset to `existing_keyset_id` after success. CLI `--copy-compressed-key-to-original` (requires `--existing-keyset-id`, conflicts with `-u`). |
| keyset_added_info.from_keyset_id_decompression_only, to_keyset_id_decompression_only | RequestId | Both required and parseable when `DecompressionOnly` is set, else `InvalidArgument`. Both keysets must exist at `epoch_id`. No CLI flag. |
| context_id | RequestId | Optional; default `DEFAULT_MPC_CONTEXT` (`0700…0001`); unknown gives `NotFound`. CLI: optional positional `[CONTEXT_ID]`. |
| epoch_id | RequestId | Optional; default `DEFAULT_EPOCH_ID` (`0800…0001`); must be an epoch of the context, else `NotFound`. Keys are stored under it, and `UseExisting`/`DecompressionOnly` read their source keysets at it. CLI: optional positional `[EPOCH_ID]`. |
| extra_data | bytes | Not validated: a bad format only logs a warning. Signed into the result. Formats: version 0 (1 byte), 1 (`0x01` ‖ context_id, 33 bytes), 2 (`0x02` ‖ context_id ‖ epoch_id, 65 bytes). The CLI sends version 2. |
| signing_schemes | repeated SigningSchemeType | `ECDSA256K1`=0, `ED25519`=1, `MLDSA44`=2, `MLDSA65`=3, `MLDSA87`=4. Empty means [ECDSA256K1]. Duplicates are dropped. An unknown value gives `InvalidArgument` before the insert. A scheme the node cannot serve (no root signing seed) gives `InvalidArgument` after the insert. CLI: the global `--signing-schemes a,b`. |
| (config) `rate_limiter_conf.keygen` | u32 tokens | Default 1000 of `bucket_size` 50000; harness 1000 of 51000. Held until the keygen ends or is aborted. |

### `keygen.get_insecure_result`: Get insecure key generation result

- **What it does:** Returns this core's result for a key generation: the request ID, the consumed preprocessing ID, one digest per piece of public key material, the deprecated EIP-712 `external_signature`, and the per-scheme `signatures`.
- **Tier reason:** It returns the key ID and digests, and `insecure-key-gen` polls it. Without it a caller cannot tell that keygen finished. Tier 0 confirmed by the user at the checkpoint.
- **Notes:**
  - A single read with no server-side wait. Responses:
    - Pending: `Unavailable`.
    - Unknown ID: `NotFound`.
    - Failed: `Internal`, or `Aborted` when the stored error text contains "abort", as after `keygen.abort`.
    - Bad ID: `InvalidArgument`.
  - **After a restart:** completed keys are reloaded from private storage (the key info at the greatest epoch per key ID), so their results stay readable. Pending and failed requests come back as `NotFound`.
  - **Shared store:** the secure `GetKeyGenResult` reads the same store with no kind check, so either RPC returns the result of any keygen.
  - Digests are hashed with the domain separator `PDAT_KEY` and sorted by key type. An uncompressed key has the server key and the public key; a compressed key has the compressed keyset and the public key.
  - **CLI:** `insecure-key-gen-result -i <id>` polls every core every 500 ms while `Unavailable`, up to `--max-iter`, and stops once it has `num_majority` results (harness 2; all cores with `-a`). It then downloads the public keys (`-u` for the uncompressed layout) and verifies digests and signatures against the domain and the `extra_data` rebuilt from `--context-id` and `--epoch-id`. Pass `--no-verify` to skip the check. `insecure-key-gen` calls the same RPC internally.
  - **Centralized:** same semantics.

| Field | Value |
|---|---|
| ID | `keygen.get_insecure_result` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetInsecureKeyGenResult` (insecure proto only); `kms-core-client -f config.toml insecure-key-gen-result -i <request_id> [-u] [--context-id <id>] [--epoch-id <id>] [--no-verify]` |
| Requires | `keygen.start_insecure` |
| Enabled by | `insecure` cargo feature (server and client) |
| Changes state | — |
| Reads state | keygen-requests |
| Related | `keygen.start_insecure`, `keygen.abort`, `metastore.get_statuses` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_insecure_key_gen_result`, `core/service/src/engine/threshold/service/key_generator.rs:RealInsecureKeyGenerator.get_result`, `core/service/src/engine/threshold/service/key_generator.rs:RealKeyGenerator.inner_get_result` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | 64 hex chars; `0x` prefix, upper case and surrounding whitespace accepted; all zeros or a bad length gives `InvalidArgument`. The keygen request ID (the key ID), not the preprocessing ID. |

### `pubdec.start`: Start public decryption

- **What it does:** Starts a threshold decryption of a batch of ciphertexts under an existing FHE key and returns `Empty` at once. In the background each core runs one MPC decryption session per ciphertext, signs the plaintexts (one KMS signature per requested scheme plus the EIP-712 `external_signature`) and stores the signed response in its public-decryption meta store.
- **Tier reason:** Decryption is the main job of the KMS (`docs/getting-started/README.md`, `docs/guides/entry_points.md` "Public Decryption"). It is the top-level CLI command `public-decrypt` and the main operation of the harness drivers. Tier 0 confirmed by the user at the checkpoint.
- **Notes:** Check order in `RealPublicDecryptor.public_decrypt`: rate-limiter token (`ResourceExhausted`); request structure (`InvalidArgument`); context and epoch known on this core (`NotFound`); signing key present (`FailedPrecondition`, only when booted in recovery mode) and requested signing schemes supported (`InvalidArgument`); key shares for `(key_id, epoch_id)` loadable (`NotFound`); then the meta-store entry. All of these run before the request ID is recorded, so a request they reject leaves no entry and the same ID can be sent again. Request-ID reuse (`add_or_redo_failed_in_meta_store`): an unknown ID is inserted as Pending; an ID whose earlier attempt Failed is reset to Pending and decrypted again from the new request's content; an ID that is Pending or Completed is rejected with `AlreadyExists` (the new request's content is not compared). A full store gives `ResourceExhausted` (see `dec_capacity`). Problems found after the call returns (bad ciphertext bytes, unsupported FHE type, unsupported decryption mode, a failed MPC session, an external handle over 32 bytes, signing failure) only show as a Failed entry, i.e. `Internal` (or `Aborted` if the error text contains "abort") from `pubdec.get_result`; the KMS does not check ciphertexts up front. Decryption is an MPC protocol among the context's parties using the epoch's PRSS setup, so the request must reach enough cores; the harness CLI waits for `num_majority` = 2 matching responses (all 4 with `-a`). The rate-limiter token is held until the background task has stored its result. Meta stores are in memory only, so a core restart forgets every decryption request ID. Harness keys come from `first_generate_key.sh` (`keygen.start_insecure` by default, `KeyGen` with `KMS_WORKLOAD_KEYGEN=secure`); the default epoch comes from `kms-init` (`epoch.create`); a non-default `epoch_id` needs an `epoch.reshare` that completed on that core. Harness use: `parallel_driver_public_decrypt.sh` runs `kms-core-client -l -f config.toml --max-iter 120 [-a] public-decrypt from-args --to-encrypt 0x<v> --data-type <ebool|euint8..euint256> --key-id <k> --batch-size <1|2|3> [--context-id 07..01 --epoch-id <e>] [--sync] [--no-compression] [--no-precompute-sns]` under `timeout 300`, with a config of all four cores or of three (one left out, still `num_parties = 4`), up to 3 attempts 10 s apart, each with a new random request ID (the harness never reuses an ID). Without `--sync` the CLI sends `PublicDecrypt` to every configured core, fails unless `num_majority` cores accept, then polls `pubdec.get_result`. `anytime_reshare_key.sh` (source-epoch check, async or sync) and `eventually_recovers_after_faults.sh` (`-a`, `--max-iter 60`) also run `public-decrypt`. Centralized: same request-ID rules; capacity is fixed at `DEC_CAPACITY` = 10000 / `MIN_DEC_CACHE` = 6000; decryption is local (no MPC); an `epoch_id` other than the default is rejected with `InvalidArgument`.

| Field | Value |
|---|---|
| ID | `pubdec.start` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `PublicDecrypt`; `kms-core-client public-decrypt from-args --to-encrypt <hex> --data-type <type> --key-id <id>` (or `public-decrypt from-file --input-path <file>`) |
| Requires | `keygen.start_insecure` |
| Enabled by | — |
| Changes state | pubdec-requests, mpc-sessions |
| Reads state | keysets, epochs, mpc-contexts, signing-keys |
| Related | `pubdec.get_result`, `pubdec.sync`, `userdec.start`, `keygen.start_insecure`, `epoch.reshare`, `epoch.destroy`, `metastore.get_statuses`, `metastore.list`, `metastore.info` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:public_decrypt`, `core/service/src/engine/threshold/service/public_decryptor.rs:RealPublicDecryptor.public_decrypt`, `core/service/src/engine/threshold/service/public_decryptor.rs:RealPublicDecryptor.inner_decrypt` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | 32 bytes as 64 hex chars. Docs say lower-case without `0x`; the parser also accepts upper-case, a `0x` prefix and surrounding whitespace. All-zero ID rejected (`InvalidArgument`). Must be unknown to this core, or known with a Failed attempt (redo). |
| ciphertexts | repeated TypedCiphertext | At least 1 (`InvalidArgument` if empty). No count limit in code; the whole request is bounded by `service.grpc_max_message_size` (harness and shipped configs 104857600 = 100 MiB; allowed 1..2147483647). One MPC session per ciphertext, all run in parallel; session ID derived from request ID + index. Harness: batch of 1–3 copies of one ciphertext. |
| ciphertexts[].ciphertext | bytes | tfhe safe-serialized ciphertext (`FheBool`/`FheUint*`, compressed list, or squashed-noise types for the Big formats); deserialization limit 4 GiB (`SAFE_SER_SIZE_LIMIT`). Not checked before the call returns. |
| ciphertexts[].fhe_type | int32 (tfhe-rs `FheTypes`) | Decryptable: Bool=0, Uint4=1, Uint8=2, Uint16=3, Uint32=4, Uint64=5, Uint128=6, Uint160=7, Uint256=8, Uint512=9, Uint1024=10, Uint2048=11, and Uint80; anything else Fails in the background. CLI `--data-type`: ebool, euint4 … euint2048; harness uses ebool, euint8 … euint256. |
| ciphertexts[].ciphertext_format | enum CiphertextFormat | SmallCompressed=0 (default; an unknown value is read as this), SmallExpanded=1, BigCompressed=2, BigExpanded=3. Small formats make the server run switch-and-squash (needs the SnS key); SmallCompressed also needs the decompression key. In BitDecSmall mode only Small formats work. CLI: default BigCompressed; `--no-compression` → BigExpanded; `--no-precompute-sns` → SmallCompressed; both → SmallExpanded. |
| ciphertexts[].external_handle | bytes | Caller's handle, covered by the EIP-712 signature. At most 32 bytes (left-padded); only checked at signing time, so a longer handle makes the request Fail in the background. CLI uses distinct 32-byte handles per batch entry (`integration_test_handles`). |
| key_id | RequestId | Required. Must name key shares this core holds for `epoch_id` (`NotFound` otherwise, before any meta-store entry). |
| domain | Eip712DomainMsg | Required by code (missing → `InvalidArgument` "missing domain"). `verifying_contract` must be an EIP-55 checksummed address; `chain_id` big-endian, at most 32 bytes; `salt` optional, exactly 32 bytes if set; `name` and `version` free strings. CLI uses the config's default domain. |
| extra_data | bytes | Signed verbatim into `external_signature`. Not validated: anything other than v0 (1 byte), v1 (33 bytes: version + context ID) or v2 (65 bytes: version + context ID + epoch ID), or IDs that do not match the request, only logs a warning. CLI builds v2 from the context and epoch. |
| context_id | RequestId | Optional; default `0700…0001` (`DEFAULT_MPC_CONTEXT`). Must be a context this core knows (`NotFound`). |
| epoch_id | RequestId | Optional; default `0800…0001` (`DEFAULT_EPOCH_ID`, the epoch `kms-init` creates). Must be an epoch of `context_id` on this core (`NotFound`). Harness sets it only for reshared epochs. |
| signing_schemes | repeated SigningSchemeType | ECDSA256K1=0, ED25519=1, MLDSA44=2, MLDSA65=3, MLDSA87=4. Empty → ECDSA only; duplicates dropped; unknown value → `InvalidArgument`; non-ECDSA schemes need a root signing seed on the node (`InvalidArgument` otherwise). CLI `--signing-schemes`. |
| (config) rate limiter | `rate_limiter_conf` | Costs `pub_decrypt` tokens (default 1, harness 1) from one bucket shared by all operations: `bucket_size` default 50000, harness 51000; harness costs `preproc` 50000, `keygen` 1000, `crsgen` 100, `new_epoch` 25, `user_decrypt` 1. Not enough tokens → `ResourceExhausted` (retryable with the same request). |
| (config) meta-store capacity | `threshold.dec_capacity`, `threshold.min_dec_cache` | Required settings; harness 10000 / 6000. Below capacity every insert succeeds. At capacity the oldest completed entry without a permit holder is evicted, but only while more than `min_dec_cache` completed entries exist; otherwise `ResourceExhausted`. |
| (config) decryption mode | `threshold.decryption_mode` | NoiseFloodSmall (default, harness) or BitDecSmall. NoiseFloodLarge and BitDecLarge parse, but every decryption then Fails in the background ("Unsupported Decryption Mode"). One mode per core, not per request. |

### `pubdec.get_result`: Get public decryption result

- **What it does:** Returns this core's signed `PublicDecryptionResponse` (plaintexts, KMS signatures, EIP-712 `external_signature`, `extra_data`) for a public decryption started with `pubdec.start` or `pubdec.sync`.
- **Tier reason:** It is the async half of public decryption. The proto documents the flow `PublicDecrypt` then `GetPublicDecryptionResult`, and `public-decrypt` without `--sync` polls it. Tier 0 confirmed by the user at the checkpoint.
- **Notes:** Blocking poll: if the entry is Pending, the server waits up to `DURATION_WAITING_ON_RESULT_SECONDS` = 60 s for it to settle, then returns `Unavailable` (retryable). Unknown or evicted ID → `NotFound`; Failed attempt → `Internal`, or `Aborted` when the stored error text contains "abort" (a task that dropped its permit is failed by the meta store's reaper with "request abandoned: meta store permit dropped before an outcome was recorded"). Malformed ID → `InvalidArgument`. Returns `Internal` if the stored payload's request ID differs from the one asked for. A completed result can be fetched any number of times until it is evicted or the core restarts. Reads only this core's store; the caller combines responses from several cores. No rate-limiter cost. Server-wide gRPC timeout is `timeout_secs` + 300 s (harness 360 + 300 = 660 s). CLI: `public-decrypt` without `--sync` polls every configured core, sleeping 0.5 s between calls, up to `--max-iter` retries per core (default 30, harness 120), retrying only on `Unavailable`; each call can itself block up to 60 s. Standalone: `kms-core-client public-decrypt-result --request-id <id> --handle <hex>...` verifies the KMS and external signatures (handles required unless `--no-verify`; `--context-id`/`--epoch-id` rebuild `extra_data`). Centralized: same behaviour.

| Field | Value |
|---|---|
| ID | `pubdec.get_result` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `GetPublicDecryptionResult`; `kms-core-client public-decrypt-result --request-id <id> --handle <hex> [--context-id <id>] [--epoch-id <id>] [--no-verify]`; also polled by `kms-core-client public-decrypt` without `--sync` |
| Requires | `pubdec.start` |
| Enabled by | — |
| Changes state | — |
| Reads state | pubdec-requests |
| Related | `pubdec.start`, `pubdec.sync`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_public_decryption_result`, `core/service/src/engine/threshold/service/public_decryptor.rs:RealPublicDecryptor.get_result`, `core/service/src/util/meta_store.rs:retrieve_from_meta_store_with_timeout` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | 64 hex chars, parsed as in `pubdec.start`; all-zero rejected. Server wait window 60 s per call (`DURATION_WAITING_ON_RESULT_SECONDS`, a constant). |

### `userdec.start`: Start user decryption

- **What it does:** Starts a user decryption and returns `Empty` at once. In the background each core partially decrypts every ciphertext with its key share, signcrypts each partial result under the user's ML-KEM-512 public key, signs the response and stores it; the user reconstructs the plaintext from enough cores' responses.
- **Tier reason:** User decryption is one of the two decryption kinds that `docs/guides/entry_points.md` and `docs/getting-started/README.md` list as main uses. It is the top-level CLI command `user-decrypt` and the harness driver `parallel_driver_user_decrypt.sh`. It was proposed as Tier 1, and the user moved it to Tier 0 at the checkpoint.
- **Notes:** Check order in `RealUserDecryptor.user_decrypt`: rate-limiter token (`ResourceExhausted`); request structure, EIP-712 link and ML-KEM key (`InvalidArgument`); context and epoch known on this core (`NotFound`); signing key present (`FailedPrecondition`, only in recovery mode) and requested schemes supported (`InvalidArgument`); key shares for `(key_id, epoch_id)` loadable (`NotFound`); then the meta-store entry. Rejections before the meta-store step record nothing, so the ID can be sent again. Request-ID reuse is the same as `pubdec.start` (`add_or_redo_failed_in_meta_store`): unknown → Pending; Failed → reset and redone from the new request; Pending or Completed → `AlreadyExists`; full store → `ResourceExhausted`. The request carries no user signature; the core computes the EIP-712 hash of `UserDecryptionLinker {publicKey: enc_key, handles, userAddress: client_address}` under `domain` and returns it as the payload `digest`. In NoiseFloodSmall mode (default and harness) the partial decryption is local: the core derives its mask from the epoch's PRSS setup and the per-ciphertext session ID and opens no network session. BitDecSmall opens an MPC session per ciphertext. Ciphertexts are processed one after another in a single background task; a bad FHE type or ciphertext makes the whole request Fail (`Internal` from `userdec.get_result`). The response carries `party_id` (1-based) and `degree` = the context's threshold (harness 1). The rate-limiter token is held until the result is stored. Meta store is in memory only, so a restart forgets every ID. The client needs `num_reconstruct` responses (harness 3, all 4 with `-a`), and the client's `decryption_mode` must match the cores'. Harness use: `parallel_driver_user_decrypt.sh` runs `kms-core-client -l -f config.toml --max-iter 120 [-a] user-decrypt from-args --to-encrypt 0x<v> --data-type <ebool|euint8..euint256> --key-id <k> --batch-size <1|2|3> [--context-id 07..01 --epoch-id <e>] [--sync] [--no-compression] [--no-precompute-sns]` under `timeout 300`, always with the four-core config, up to 3 attempts 10 s apart; each attempt uses a new request ID and a new ephemeral ML-KEM-512 key. Without `--sync` the CLI, per core, sends `UserDecrypt` and then polls `userdec.get_result` in the same task. The CLI batch repeats one ciphertext with the same handle (`dummy_handle`, 32 bytes of 0x17). Centralized: same request-ID rules; capacity fixed at 10000 / 6000; local decryption; only the default epoch.

| Field | Value |
|---|---|
| ID | `userdec.start` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `UserDecrypt`; `kms-core-client user-decrypt from-args --to-encrypt <hex> --data-type <type> --key-id <id>` (or `user-decrypt from-file --input-path <file>`) |
| Requires | `keygen.start_insecure` |
| Enabled by | — |
| Changes state | userdec-requests |
| Reads state | keysets, epochs, mpc-contexts, signing-keys |
| Related | `userdec.get_result`, `userdec.sync`, `pubdec.start`, `keygen.start_insecure`, `epoch.reshare`, `epoch.destroy`, `metastore.get_statuses`, `metastore.list`, `metastore.info` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:user_decrypt`, `core/service/src/engine/threshold/service/user_decryptor.rs:RealUserDecryptor.user_decrypt`, `core/service/src/engine/threshold/service/user_decryptor.rs:RealUserDecryptor.inner_user_decrypt` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | 32 bytes as 64 hex chars; parser also accepts upper-case, `0x` prefix and whitespace; all-zero rejected (`InvalidArgument`). Must be unknown, or known with a Failed attempt (redo). |
| typed_ciphertexts | repeated TypedCiphertext | At least 1 (`InvalidArgument`). No count limit beyond `service.grpc_max_message_size` (harness 100 MiB). Processed sequentially, one session ID per index. Harness batch 1–3. |
| typed_ciphertexts[].ciphertext / fhe_type / ciphertext_format | bytes / int32 / enum | Same values as `pubdec.start` (FHE types Bool…Uint2048 and Uint80; formats SmallCompressed=0 … BigExpanded=3; 4 GiB deserialization limit). Checked only in the background. BitDecSmall accepts only Small formats. |
| typed_ciphertexts[].external_handle | bytes | At most 32 bytes, checked up front (`InvalidArgument`); part of the EIP-712 link. |
| key_id | RequestId | Required. Key shares for `epoch_id` must be on this core (`NotFound`). |
| client_address | string | EIP-55 checksummed address with `0x` (`InvalidArgument` otherwise). Must differ from `domain.verifying_contract`. Used as the signcryption receiver ID. |
| enc_key | bytes | tfhe safe-serialized `UnifiedPublicEncKey` holding an ML-KEM-512 key (4 GiB limit). ML-KEM-1024 and MLKEM1024-P384 keys are rejected (`InvalidArgument`). The original bytes are what gets signed. |
| domain | Eip712DomainMsg | Required (`InvalidArgument` if missing). `verifying_contract` required, EIP-55, not equal to `client_address`; `chain_id` big-endian, at most 32 bytes; `salt` 32 bytes if set. CLI uses the config's default domain. |
| extra_data | bytes | Signed verbatim; format v0/v1/v2 only checked with a warning (see `pubdec.start`). |
| context_id | RequestId | Optional; default `0700…0001`. Must exist on this core (`NotFound`). |
| epoch_id | RequestId | Optional; default `0800…0001` (the `kms-init` epoch). Must be an epoch of the context on this core (`NotFound`). |
| signing_schemes | repeated SigningSchemeType | ECDSA256K1=0 … MLDSA87=4; empty → ECDSA only; unknown → `InvalidArgument`; non-ECDSA needs a root signing seed. |
| (config) rate limiter | `rate_limiter_conf.user_decrypt` | Default 1, harness 1, from the bucket shared with all operations (harness 51000). Exhausted → `ResourceExhausted`. |
| (config) meta-store capacity | `threshold.dec_capacity`, `threshold.min_dec_cache` | Separate store with the same settings as public decryption (harness 10000 / 6000). |
| (config) decryption mode | `threshold.decryption_mode` | NoiseFloodSmall (local, default, harness) or BitDecSmall (MPC session). NoiseFloodLarge / BitDecLarge make every request Fail in the background ("Unsupported Decryption Mode for user_decrypt"). |

### `userdec.get_result`: Get user decryption result

- **What it does:** Returns this core's signed `UserDecryptionResponse` (signcrypted partial decryptions, `digest`, `party_id`, `degree`, KMS signatures, `external_signature`) for a user decryption started with `userdec.start` or `userdec.sync`.
- **Tier reason:** It is the async half of user decryption, and `user-decrypt` without `--sync` polls it. It follows `userdec.start` into Tier 0 by the user's choice.
- **Notes:** Same waiting and error behaviour as `pubdec.get_result`: a Pending entry is waited on for up to 60 s, then `Unavailable`; unknown or evicted ID → `NotFound`; Failed → `Internal` (or `Aborted` if the error mentions "abort"); malformed ID → `InvalidArgument`. Unlike public decryption it does not compare the stored payload's request ID. No rate-limiter cost. No standalone CLI command: only `kms-core-client user-decrypt` without `--sync` calls it, polling each core after its `UserDecrypt` succeeds, 0.5 s apart, up to `--max-iter` retries, retrying only on `Unavailable`. Centralized: same.

| Field | Value |
|---|---|
| ID | `userdec.get_result` |
| Tier | 0 |
| Feature group | — |
| Kind | data |
| How to call | `GetUserDecryptionResult`; polled by `kms-core-client user-decrypt` without `--sync` |
| Requires | `userdec.start` |
| Enabled by | — |
| Changes state | — |
| Reads state | userdec-requests |
| Related | `userdec.start`, `userdec.sync`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_user_decryption_result`, `core/service/src/engine/threshold/service/user_decryptor.rs:RealUserDecryptor.get_result`, `core/service/src/util/meta_store.rs:retrieve_from_meta_store_with_timeout` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | 64 hex chars, parsed as in `userdec.start`. Server wait window 60 s per call (`DURATION_WAITING_ON_RESULT_SECONDS`). |

## Tier 1: Core variants

### `keygen.abort`: Abort key generation

- **What it does:** Cancels, by preprocessing ID, a running key generation that consumed that preprocessing.
- **Tier reason:** It cancels a running keygen and adds no new concept. It sits next to `KeyGen` on the main proto service and is the top-level CLI command `abort-key-gen`.
- **Notes:**
  - Synchronous. It takes the **preprocessing ID**, not the keygen request ID. There is no rate limiting and no meta-store insert.
  - Order:
    1. Cancel a running keygen that consumed this preprocessing. Secure and insecure keygens share the same running-task map, keyed by preprocessing ID.
    2. Cancel a running secure `KeyGenPreproc` or `PartialKeyGenPreproc` with this ID. Both are out of scope here.
  - Returns `Ok` if either step cancelled something.
  - Returns `NotFound` ("No ongoing key generation found for the supplied preprocessing ID") when nothing is running under the ID: an unknown ID, an insecure preprocessing (it never runs in the background), or a keygen that has already finished. A malformed ID gives `InvalidArgument`.
  - **Effect:** cancellation is cooperative. The background task races the protocol against the cancel token. On cancel, the keygen records "Key generation was aborted", and `keygen.get_insecure_result` gives `Aborted`. The token is only raced against the generation step; key material is written after it. The rate-limiter tokens are returned when the task exits.
  - **Request-ID reuse:** entries are not removed. The aborted keygen request ID stays taken (`AlreadyExists` if reused) until a restart. The preprocessing consumed by an aborted keygen is gone.
  - **Lifecycle:** the proto says no `NewMpcEpoch`, `DestroyMpcEpoch` or `DestroyMpcContext` may run at the same time. This is a rule for callers.
  - **CLI:** `abort-key-gen -i <preproc_id>` sends the abort to every core, retries a core only on `Unavailable` (up to `--max-iter`), waits for an answer from all n cores, and prints each core's status-code text. A `NotFound` does not make the command fail.
  - Not used by the harness scripts. With the insecure keygen (`keygen.start_insecure`) the abort window is a few seconds.
  - **Centralized:** only aborts a running keygen started with this `preproc_id` (`core/service/src/engine/centralized/service/key_gen.rs:abort_key_gen_impl`).
- **Uncertain:** `docs/guides/core_client.md` and `docs/references/api/core_grpc.md` do not document it, which leans Tier 3. With only the insecure keygen in scope, it has a window of a few seconds to cancel anything. It stays in Tier 1 because it is on the main service and in the main CLI.

| Field | Value |
|---|---|
| ID | `keygen.abort` |
| Tier | 1 |
| Feature group | — |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/AbortKeyGen`; `kms-core-client -f config.toml abort-key-gen -i <preproc_id>` |
| Requires | `keygen.start_insecure` (still running) |
| Enabled by | — |
| Changes state | keygen-requests, preproc-requests |
| Reads state | keygen-requests, preproc-requests |
| Related | `preproc.start_insecure`, `keygen.start_insecure`, `keygen.get_insecure_result`, `crs.abort` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:abort_key_gen`, `core/service/src/engine/threshold/service/key_generator.rs:RealKeyGenerator.inner_abort_key_gen`, `core/service/src/engine/threshold/service/preprocessor.rs:RealPreprocessor.abort_key_gen_preproc` |
| Confidence | low |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | The preprocessing ID: the `request_id` given to `InsecureKeyGenPreproc`, which is also the keygen's `preproc_id`. 64 hex chars; `0x` prefix, upper case and surrounding whitespace accepted; all zeros or a bad length gives `InvalidArgument`. A keygen must be running under it, else `NotFound`. CLI `-i/--request-id`. |

### `pubdec.sync`: Public decryption (sync)

- **What it does:** Runs `pubdec.start` and then `pubdec.get_result` on the same core in one call and returns the `PublicDecryptionResponse` directly.
- **Tier reason:** The proto documents it as the synchronous form of `PublicDecrypt` plus `GetPublicDecryptionResult` with the same request. It is the CLI flag `public-decrypt --sync`, and the harness uses it with a probability of 10 to 90 %.
- **Notes:** Implemented as `public_decrypt` followed by `get_result`, so every call, including one that only attaches, takes a rate-limiter token and passes all start-time checks (validation, context/epoch, signing key, key lookup) before it reaches the meta store. If `public_decrypt` returns `AlreadyExists` (ID Pending or Completed), the error is dropped (`defuse`, not counted as an error) and the call attaches to the existing entry; the rest of the new request is ignored. A Failed ID is redone from the new request, as in `pubdec.start`. It then waits up to 60 s for the result; if not ready it returns `Unavailable` while the decryption keeps running, and the caller can re-send the same request (which attaches) or call `pubdec.get_result`. Other start errors come back as from `pubdec.start`. The result stays in the meta store and can be fetched again with `pubdec.get_result`. CLI: `--sync` makes `public-decrypt` send `PublicDecryptSync` to every configured core and re-send the identical request (same request ID) on `Unavailable` or `ResourceExhausted`, 0.5 s apart, up to `--max-iter` times. Harness: `parallel_driver_public_decrypt.sh` adds `--sync` with a per-timeline probability of 10, 50 or 90 %. Centralized: same structure.

| Field | Value |
|---|---|
| ID | `pubdec.sync` |
| Tier | 1 |
| Feature group | — |
| Kind | data |
| How to call | `PublicDecryptSync`; `kms-core-client public-decrypt from-args ... --sync` (or `public-decrypt from-file --input-path <file> --sync`) |
| Requires | `keygen.start_insecure` |
| Enabled by | — |
| Changes state | pubdec-requests, mpc-sessions |
| Reads state | pubdec-requests, keysets, epochs, mpc-contexts, signing-keys |
| Related | `pubdec.start`, `pubdec.get_result`, `userdec.sync`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:public_decrypt_sync`, `core/service/src/engine/threshold/service/public_decryptor.rs:RealPublicDecryptor.public_decrypt_sync`, `core/service/src/util/meta_store.rs:add_or_redo_failed_in_meta_store` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | Parsed as in `pubdec.start`. Need not be fresh: unknown → new decryption; Pending or Completed → attach (rest of the request ignored, but it must still pass validation and key lookup); Failed → redo from this request. |
| ciphertexts | repeated TypedCiphertext | Same limits as `pubdec.start`. |
| key_id | RequestId | Same as `pubdec.start`; checked even when attaching. |
| domain | Eip712DomainMsg | Same as `pubdec.start` (required). |
| extra_data | bytes | Same as `pubdec.start`. |
| context_id | RequestId | Same as `pubdec.start`. |
| epoch_id | RequestId | Same as `pubdec.start`. |
| signing_schemes | repeated SigningSchemeType | Same as `pubdec.start`. |
| (config) rate limiter | `rate_limiter_conf.pub_decrypt` | One token per call, attach included (harness 1 of 51000). |
| (server) wait window | constant | 60 s (`DURATION_WAITING_ON_RESULT_SECONDS`), then `Unavailable`. |

### `userdec.sync`: User decryption (sync)

- **What it does:** Runs `userdec.start` and then `userdec.get_result` on the same core in one call and returns the `UserDecryptionResponse` directly.
- **Tier reason:** The proto documents it as the synchronous form of `UserDecrypt` plus `GetUserDecryptionResult` with the same request. It is the CLI flag `user-decrypt --sync`, and the harness uses it with a probability of 10 to 90 %.
- **Notes:** Same structure as `pubdec.sync`: calls `user_decrypt` (rate-limiter token, full validation, context/epoch, signing key and key lookup on every call), drops an `AlreadyExists` and attaches to the Pending or Completed entry (rest of the request ignored), redoes a Failed ID from the new request, then waits up to 60 s and returns `Unavailable` if the result is not ready; the decryption keeps running and the caller can re-send the same request or call `userdec.get_result`. CLI: `user-decrypt ... --sync` sends `UserDecryptSync` to every core and re-sends the identical request on `Unavailable` or `ResourceExhausted`, 0.5 s apart, up to `--max-iter` times. Harness: `parallel_driver_user_decrypt.sh` adds `--sync` with a per-timeline probability of 10, 50 or 90 %. Centralized: same structure.

| Field | Value |
|---|---|
| ID | `userdec.sync` |
| Tier | 1 |
| Feature group | — |
| Kind | data |
| How to call | `UserDecryptSync`; `kms-core-client user-decrypt from-args ... --sync` (or `user-decrypt from-file --input-path <file> --sync`) |
| Requires | `keygen.start_insecure` |
| Enabled by | — |
| Changes state | userdec-requests |
| Reads state | userdec-requests, keysets, epochs, mpc-contexts, signing-keys |
| Related | `userdec.start`, `userdec.get_result`, `pubdec.sync`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:user_decrypt_sync`, `core/service/src/engine/threshold/service/user_decryptor.rs:RealUserDecryptor.user_decrypt_sync`, `core/service/src/util/meta_store.rs:add_or_redo_failed_in_meta_store` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (string) | Need not be fresh: unknown → new decryption; Pending or Completed → attach (the request must still validate and its key must load); Failed → redo from this request. |
| typed_ciphertexts | repeated TypedCiphertext | Same limits as `userdec.start`. |
| key_id | RequestId | Same as `userdec.start`; checked even when attaching. |
| client_address | string | Same as `userdec.start`. |
| enc_key | bytes | Same as `userdec.start` (ML-KEM-512 only). The harness makes a new key per attempt; a re-sent sync request reuses the same key. |
| domain | Eip712DomainMsg | Same as `userdec.start` (required, `verifying_contract` ≠ `client_address`). |
| extra_data | bytes | Same as `userdec.start`. |
| context_id | RequestId | Same as `userdec.start`. |
| epoch_id | RequestId | Same as `userdec.start`. |
| signing_schemes | repeated SigningSchemeType | Same as `userdec.start`. |
| (config) rate limiter | `rate_limiter_conf.user_decrypt` | One token per call, attach included. |
| (server) wait window | constant | 60 s, then `Unavailable`. |

## Tier 2: Features

### `crs.start`: Start CRS generation

- **What it does:** Starts the distributed ZK CRS ceremony for a given context and epoch and returns at once. The ceremony runs in the background. Each party then stores the CRS in public storage (`PUB-p<i>/CRS/<crs_id>`) and its signed `CrsInfo` in private storage under the epoch.
- **Tier reason:** CRS generation has its own sections in `docs/guides/entry_points.md` ("CRS generation"), `docs/guides/core_client.md` ("CRS-generation") and `docs/references/api/core_grpc.md` ("CRS Generation"). It adds CRS material, a new kind of state that decryption does not use.
- **Notes:**
  - Async. Checks run in this order:
    1. Rate limiter: takes `crsgen` tokens (default 100, harness 100) from the shared bucket (default 50000, harness 51000). The tokens are held until the background task ends. An empty bucket gives `ResourceExhausted`. While a preprocessing runs (it holds 50000 tokens in the harness), only 1000 tokens are left for everything else.
    2. Request validation: `InvalidArgument`.
    3. Context and epoch exist and this party has a role in the context: `NotFound` otherwise.
    4. No CRS is already stored for (request_id, epoch_id): `AlreadyExists` otherwise.
    5. The signing identity is present (`FailedPrecondition` if not) and supports the requested schemes (`InvalidArgument` if not).
    6. Insert into `crs-requests`: `AlreadyExists` if the ID is already there in any state.
    7. Session setup: `Internal` on failure.
  - **Request-ID reuse:** a failed or aborted ID cannot be reused while the process lives. There is no redo-on-failure path. At boot, `crs-requests` is reseeded only with completed CRSes from private storage, taking the greatest epoch per CRS ID. After a restart a failed or aborted ID is forgotten, but a completed one still gives `AlreadyExists`.
  - **Ceremony:** runs over a `Sync` network session of the context. It raises the session timeout to `network_timeout_bk_sns` (harness 1200 s), because each party takes a sequential turn. A failure is stored in `crs-requests` and reported by `crs.get_result`.
  - **Lifecycle:** no lifecycle lease is taken. The proto says no `NewMpcEpoch`, `DestroyMpcEpoch` or `DestroyMpcContext` may run at the same time. This is a rule for callers.
  - **CLI:** `crs-gen` sends the same request to every configured core. It needs `num_majority` start acknowledgements (harness 2; with `-a`, all cores). It then polls `GetCrsGenResult` every 500 ms for up to `--max-iter` tries, downloads the CRS from S3, and checks the signatures. The CLI makes a random request ID and builds `extra_data` version 2 from the context and epoch.
  - **Centralized:** generates the CRS locally, with no ceremony (`core/service/src/engine/centralized/service/crs_gen.rs`).

| Field | Value |
|---|---|
| ID | `crs.start` |
| Tier | 2 |
| Feature group | `crs` |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/CrsGen`; `kms-core-client -f config.toml crs-gen --max-num-bits <n> [--context-id <id>] [--epoch-id <id>]` |
| Requires | — |
| Enabled by | — |
| Changes state | crs-requests, crs, mpc-sessions |
| Reads state | mpc-contexts, epochs, crs, signing-keys |
| Related | `crs.get_result`, `crs.start_insecure`, `crs.abort`, `epoch.reshare`, `epoch.destroy`, `material.list`, `metastore.get_statuses` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:crs_gen`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.inner_crs_gen_from_request`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.crs_gen_background` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | 32 bytes, so 64 hex chars. A `0x` prefix and surrounding whitespace are accepted. All zeros, a bad length or a missing value gives `InvalidArgument`. Must be new to `crs-requests` and not already stored as a CRS (see Notes). |
| params | FheParameter enum | `default`=0, `test`=1. Any other value gives `InvalidArgument`. The harness client sends `Test`. |
| max_num_bits | optional uint32 | Must be a power of 2 from 1 to 2048 (`verify_max_num_bits`), else `InvalidArgument`. Unset means 2048 (`ZK_DEFAULT_MAX_NUM_BITS`). Larger values give a larger witness dimension and a longer ceremony. The CLI flag `-m/--max-num-bits` is required and has no default. |
| domain | Eip712DomainMsg | Required: missing gives `InvalidArgument` ("missing domain"). `verifying_contract` must be an EIP-55 checksummed address. `chain_id` is big-endian bytes. `salt`, if set, must be 32 bytes. The CLI uses `[default_domain]` from its config, or else the dummy domain ("Authorization token", "1", chain 8006, `0x66f9664f97F2b50F62D13eA064982f936dE76657`). The harness uses the dummy domain. |
| context_id | RequestId | Optional. Unset means `DEFAULT_MPC_CONTEXT` (`0700…0001`). An unknown context, or one where this party has no role, gives `NotFound`. |
| epoch_id | RequestId | Optional. Unset means `DEFAULT_EPOCH_ID` (`0800…0001`, created by kms-init). It must be an epoch of `context_id`, else `NotFound`. The CRS metadata is stored under this epoch. |
| extra_data | bytes | Not validated: a bad format only logs a warning. It is signed into the EIP-712 result. The CLI sends version 2 (`0x02` ‖ context_id ‖ epoch_id, 65 bytes). |
| signing_schemes | repeated SigningSchemeType | `ECDSA256K1`=0, `ED25519`=1, `MLDSA44`=2, `MLDSA65`=3, `MLDSA87`=4. Empty means [ECDSA256K1]. Duplicates are dropped. An unknown value gives `InvalidArgument`. Non-ECDSA schemes need a root signing seed on the node, else `InvalidArgument`. CLI: the global `--signing-schemes a,b`. |

### `crs.get_result`: Get CRS generation result

- **What it does:** Returns this party's result for a CRS request ID: the CRS digest, `max_num_bits` and signatures. The CRS itself is fetched from public storage.
- **Tier reason:** It is the read-back for `crs.start` and only makes sense with it. CRS generation has its own sections in `docs/guides/entry_points.md` ("CRS generation"), `docs/guides/core_client.md` ("CRS-generation") and `docs/references/api/core_grpc.md` ("CRS Generation"). It adds CRS material, a new kind of state that decryption does not use.
- **Notes:**
  - Reads only the in-memory `crs-requests`. Responses:
    - Pending: `Unavailable`.
    - Unknown ID: `NotFound`.
    - Failed: `Internal`, or `Aborted` when the stored error text contains "abort", as after `crs.abort`.
    - Bad ID: `InvalidArgument`.
  - **After a restart:** completed CRSes are reloaded from private storage (the `CrsInfo` at the greatest epoch per CRS ID), so their results stay readable. Pending and failed requests come back as `NotFound`.
  - **Legacy (V0) entries:** return an empty digest and signatures and `max_num_bits` 0.
  - **Shared store:** `GetCrsGenResult` and `GetInsecureCrsGenResult` read the same store, so either one returns results of both secure and insecure requests.
  - **CLI:** `crs-gen-result` polls every core every 500 ms up to `--max-iter` and stops once it has `num_majority` results. It then downloads the CRS and verifies each signature against the domain and the `extra_data` derived from `--context-id` and `--epoch-id`. Pass `--no-verify` to skip the check. `crs-gen` calls the same RPC internally.

| Field | Value |
|---|---|
| ID | `crs.get_result` |
| Tier | 2 |
| Feature group | `crs` |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetCrsGenResult`; `kms-core-client -f config.toml crs-gen-result -i <request_id> [--context-id <id>] [--epoch-id <id>] [--no-verify]` (also polled by `crs-gen`) |
| Requires | `crs.start` |
| Enabled by | — |
| Changes state | — |
| Reads state | crs-requests |
| Related | `crs.start`, `crs.get_insecure_result`, `crs.abort`, `metastore.get_statuses` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_crs_gen_result`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.inner_get_result` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | 32 bytes, so 64 hex chars, not all zero. Otherwise `InvalidArgument`. The CLI flags `--context-id`/`--epoch-id` only rebuild `extra_data` on the client side for the signature check. They are not sent to the server. |

### `crs.start_insecure`: Start insecure CRS generation

- **What it does:** Same request and checks as `crs.start`, but there is no ceremony. Party 1 samples the CRS locally (`async_generate_crs`) and sends it to the other parties of the session (`transfer_crs`). Every party then signs and stores it like a normal CRS.
- **Tier reason:** It is the fast test form of `crs.start` (`insecure` feature; `docs/guides/core_client.md` "Insecure CRS-generation"). CRS generation has its own sections in `docs/guides/entry_points.md` ("CRS generation"), `docs/guides/core_client.md` ("CRS-generation") and `docs/references/api/core_grpc.md` ("CRS Generation"). It adds CRS material, a new kind of state that decryption does not use.
- **Notes:**
  - Shares the secure path's validation, rate limiter (`crsgen` tokens), `crs-requests` store, ongoing-task map and storage. An ID already used by either kind gives `AlreadyExists`.
  - Party 1 must be in the session and reachable, because it is the only sampler.
  - Much faster than the ceremony. The docs say it must not be used in production.
  - **CLI:** `insecure-crs-gen` has the same flags as `crs-gen` and polls `GetInsecureCrsGenResult`.
  - **Centralized:** the same local generation as the secure path.

| Field | Value |
|---|---|
| ID | `crs.start_insecure` |
| Tier | 2 |
| Feature group | `crs` |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/InsecureCrsGen` (insecure proto); `kms-core-client -f config.toml insecure-crs-gen --max-num-bits <n> [--context-id <id>] [--epoch-id <id>]` |
| Requires | — |
| Enabled by | `insecure` cargo feature (server: `kms-service-insecure.v1.proto`; client: `kms-core-client` built with `insecure`); harness builds both with it |
| Changes state | crs-requests, crs, mpc-sessions |
| Reads state | mpc-contexts, epochs, crs, signing-keys |
| Related | `crs.get_insecure_result`, `crs.start`, `crs.abort`, `epoch.reshare` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:insecure_crs_gen`, `core/service/src/engine/threshold/service/crs_generator.rs:RealInsecureCrsGenerator.insecure_crs_gen`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.crs_gen_background` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | Same as `crs.start`. |
| params | FheParameter enum | `default`=0, `test`=1. The harness uses `Test`. |
| max_num_bits | optional uint32 | A power of 2 from 1 to 2048. Unset means 2048. The CLI requires `-m`. |
| domain | Eip712DomainMsg | Required, as for `crs.start`. |
| context_id | RequestId | Optional, defaults to `DEFAULT_MPC_CONTEXT`. Must be known with a role for this party (`NotFound`). |
| epoch_id | RequestId | Optional, defaults to `DEFAULT_EPOCH_ID`. Must belong to the context (`NotFound`). |
| extra_data | bytes | Warning-only checks. The CLI sends version 2. |
| signing_schemes | repeated SigningSchemeType | Same rules as `crs.start`. |

### `crs.get_insecure_result`: Get insecure CRS generation result

- **What it does:** Returns this party's CRS result for a request ID. It has the same response and errors as `crs.get_result`.
- **Tier reason:** It is the read-back for `crs.start_insecure`, and `insecure-crs-gen` polls it. CRS generation has its own sections in `docs/guides/entry_points.md` ("CRS generation"), `docs/guides/core_client.md` ("CRS-generation") and `docs/references/api/core_grpc.md` ("CRS Generation"). It adds CRS material, a new kind of state that decryption does not use.
- **Notes:**
  - It calls `RealCrsGenerator.inner_get_result` on the same `crs-requests` store as `GetCrsGenResult`, so it also returns results of secure CRS requests.
  - The difference from `crs.get_result` is only the metric tag: it reports under the insecure CRS request tag.
  - **CLI:** `insecure-crs-gen-result` (also polled by `insecure-crs-gen`) takes the same flags as `crs-gen-result`.

| Field | Value |
|---|---|
| ID | `crs.get_insecure_result` |
| Tier | 2 |
| Feature group | `crs` |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetInsecureCrsGenResult` (insecure proto); `kms-core-client -f config.toml insecure-crs-gen-result -i <request_id> [--context-id <id>] [--epoch-id <id>] [--no-verify]` |
| Requires | `crs.start_insecure` |
| Enabled by | `insecure` cargo feature |
| Changes state | — |
| Reads state | crs-requests |
| Related | `crs.start_insecure`, `crs.get_result`, `crs.abort` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_insecure_crs_gen_result`, `core/service/src/engine/threshold/service/crs_generator.rs:RealInsecureCrsGenerator.get_result`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.inner_get_result` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | 32 bytes, so 64 hex chars, not all zero. Otherwise `InvalidArgument`. |

### `crs.abort`: Abort CRS generation

- **What it does:** Cancels an ongoing CRS generation (secure or insecure) on this party, using its request ID.
- **Tier reason:** It cancels a running CRS generation, so it only makes sense inside the CRS feature. It is the top-level CLI command `abort-crs-gen`.
- **Notes:**
  - Sync and local. It removes the ID from the in-memory ongoing-task map and fires its cancellation token. If the ID is not in the map, the call returns `NotFound`. That includes unknown IDs, CRSes that already finished or failed, and repeated aborts.
  - The background task races generation against cancellation and only writes storage after generation succeeds. A cancel that lands before then records "aborted before completion" in `crs-requests` and writes no CRS. After that, `crs.get_result` returns `Aborted`, and reusing the ID returns `AlreadyExists` until a restart.
  - Cancellation is only observed while the CRS is being generated. Once generation has finished, the result is written anyway.
  - Each party aborts on its own. Aborting on only some parties leaves the other parties running the ceremony.
  - The proto says no `NewMpcEpoch`, `DestroyMpcEpoch` or `DestroyMpcContext` may run concurrently. This is a rule for callers.
  - **CLI:** `abort-crs-gen -i <id>` sends the abort to every core and retries only on `Unavailable`. It prints each core's status code, so `NotFound` is reported but does not fail the command. It needs a response from every configured core.

| Field | Value |
|---|---|
| ID | `crs.abort` |
| Tier | 2 |
| Feature group | `crs` |
| Kind | data |
| How to call | `kms_service.v1.CoreServiceEndpoint/AbortCrsGen`; `kms-core-client -f config.toml abort-crs-gen -i <request_id>` |
| Requires | `crs.start` (still running; crs.start_insecure also works) |
| Enabled by | — |
| Changes state | crs-requests |
| Reads state | crs-requests |
| Related | `crs.start`, `crs.start_insecure`, `crs.get_result`, `crs.get_insecure_result`, `keygen.abort` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:abort_crs_gen`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.inner_abort_crs_gen`, `core/service/src/engine/threshold/service/crs_generator.rs:RealCrsGenerator.crs_gen_background` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId (hex string) | The CRS request ID. 32 bytes, so 64 hex chars, not all zero (`InvalidArgument`). It must be in this party's ongoing map, else `NotFound`. |

### `epoch.reshare`: Create MPC epoch with resharing

- **What it does:** `NewMpcEpoch` with `previous_epoch` set. It creates a new epoch and, in the same step, reshares the FHE private key shares of the listed keys from a source epoch and context into the new epoch. It also re-signs the listed CRSes for the new epoch. The public key material stays the same.
- **Tier reason:** Resharing has its own sections in `docs/guides/entry_points.md` ("Key reshare") and `docs/guides/core_client.md` ("New Epoch (Resharing)"). It adds epochs as a new concept with their own state. The harness driver `anytime_reshare_key.sh` runs it.
- **Notes:**
  - **Same entry and checks as `epoch.create`**, plus these synchronous steps before the RPC returns:
    1. `verify_epoch_info` parses `previous_epoch`: `InvalidArgument` on a bad or missing ID, unknown `key_parameters`, an unknown `key_type`, or a wrong digest set. Uncompressed keys need exactly ServerKey + PublicKey; compressed keys need CompressedXofKeySet + PublicKey.
    2. `domain` is required: missing gives `InvalidArgument`.
    3. The creation lease also read-locks the source context and source epoch. Destroying either one while the reshare runs gives `FailedPrecondition`.
    4. `initiate_resharing_and_crs_resign`:
       - builds a two-sets session over the source and target contexts. Every party must know both contexts and be in at least one of them, else `InvalidArgument`;
       - verifies each CRS digest against the core's own public `CRS/<id>`, or against a peer's copy fetched over S3 via `public_storage_url`. A mismatch or fetch failure gives `Internal`;
       - checks each `preproc_id` against the one stored with the key: `InvalidArgument` on a mismatch, or when a set-1 party cannot read the key at the source epoch;
       - verifies key digests against the public material.
  - **Background task:**
    - PRSS for the new epoch, if this core is in the target context.
    - The reshare protocol: lift at set 1, then set-2 preprocessing, then online reshare.
    - Store under the new epoch: new `FheKeyInfo` per key, and a re-signed `CrsInfo` per CRS. Public bytes are written only if missing.
    - Then the backup vault is updated.
    - On a storage failure the core rolls back what it wrote under the new epoch and deletes the epoch if it is then empty.
    - A failure is stored in `epoch-requests`, so a retry needs a new epoch ID while the process lives.
  - **Roles:** a party in both contexts is `Both`. In the harness, which reshares within the default context, all 4 cores are `Both`. A set-1-only party returns the source epoch's metadata instead of re-signing.
  - **Peer fetch in the default context:** `DEFAULT_MPC_CONTEXT` has empty `public_storage_url`, so in that context public material cannot be fetched from peers. Each core must already hold it.
  - **The workload has to supply:**
    - key IDs, from `keygen.*`;
    - each key's original preproc ID, which no public object records;
    - SHAKE-256 digests (`PDAT_KEY` prefix) of the stored public objects;
    - for CRSes, `crs_id` plus a `PDAT_CRS` digest.
  - **Harness, `antithesis/test/v1/public_decrypt/anytime_reshare_key.sh`:**
    - It picks a key recorded by `first_generate_key.sh` (default insecure keygen) and its preproc ID.
    - Source epoch: `0800…0001`, or an earlier confirmed reshared epoch. New epoch: a random `08…` ID.
    - It downloads `PUB-p1/CompressedXofKeySet/<key>` (or `ServerKey`) and `PublicKey` from MinIO, and computes digests as `openssl dgst -shake256 -xoflen 32` over `PDAT_KEY` ‖ bytes.
    - It runs `kms-core-client -f config.toml --max-iter 1200 new-epoch --new-epoch-id <new> --new-context-id 0700…0001 --previous-epoch-params "context_id:0700…0001;epoch_id:<src>;previous_keys:[key_id=<k>,preproc_id=<p>,xof_key_digest=<d>,public_key_digest=<d>]"`, under `timeout 900`. It passes no `previous_crs`.
  - **CLI checks:** the CLI uses the config's default domain (the dummy domain in the harness) and FHE params (`Test`). It then checks:
    - every core's `GetEpochResult` lists the expected key and preproc IDs in order;
    - the public material can be fetched from all cores;
    - each signature verifies with either the new or the source epoch's `extra_data`.
  - **Centralized:** not supported (only the default epoch).
- **Uncertain:** The gateway or the operator triggers a reshare, not an application developer, which leans Tier 3. It stays in Tier 2 because it is a documented main feature that changes the key shares that decryption uses.

| Field | Value |
|---|---|
| ID | `epoch.reshare` |
| Tier | 2 |
| Feature group | `reshare` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/NewMpcEpoch` with `previous_epoch` set; `kms-core-client -f config.toml new-epoch --new-epoch-id <id> --new-context-id <id> --previous-epoch-params "context_id:<ctx>;epoch_id:<ep>;previous_keys:[key_id=…,preproc_id=…,xof_key_digest=…\|server_key_digest=…,public_key_digest=…;…];previous_crs:[crs_id=…,digest=…;…]"` |
| Requires | `keygen.start_insecure` (each reshared key) |
| Enabled by | Threshold mode |
| Changes state | epochs, epoch-requests, keysets, crs, mpc-sessions |
| Reads state | mpc-contexts, epochs, keysets, crs, signing-keys |
| Related | `epoch.get_result`, `epoch.create`, `epoch.destroy`, `keygen.start_insecure`, `crs.start`, `pubdec.start`, `userdec.start`, `context.create` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:new_mpc_epoch`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.initiate_resharing_and_crs_resign`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.store_reshared_keys` |
| Confidence | low |

| Input | Type | Limits and notes |
|---|---|---|
| context_id | RequestId | The target context. Optional, defaults to `0700…0001`. Must be known (`NotFound` on the PRSS-role lookup, or `InvalidArgument` from the two-sets session). |
| epoch_id | RequestId | The new epoch. Same rules as `epoch.create`, and it must differ from the source epoch. |
| previous_epoch.context_id | RequestId | Required (`InvalidArgument`). The source context, which every party must know. It may equal `context_id` (the harness does this). |
| previous_epoch.epoch_id | RequestId | Required. An existing epoch that holds the listed keys and CRSes. Destroying it during the reshare is blocked (`FailedPrecondition`). |
| previous_epoch.keys_info[].key_id | RequestId | Required per key. Must be readable at the source epoch on set-1 and `Both` parties (`InvalidArgument`). The list may be empty. |
| previous_epoch.keys_info[].preproc_id | RequestId | Required. Must equal the preproc ID stored with the key (`InvalidArgument`); a legacy key records none and only logs a warning. |
| previous_epoch.keys_info[].key_parameters | FheParameter | `default`=0 or `test`=1. The CLI sends its config's `fhe_params` (harness `Test`). |
| previous_epoch.keys_info[].key_digests | repeated KeyDigest | `key_type` strings parse as PubDataType. Exactly {`ServerKey`, `PublicKey`} or {`CompressedXofKeySet`, `PublicKey`}, non-empty. Each value is SHAKE-256 (32 bytes) with the `PDAT_KEY` prefix over the stored object, and must match the stored bytes. CLI fields: `server_key_digest`, `xof_key_digest` (mutually exclusive) and `public_key_digest`, as hex. |
| previous_epoch.crs_info[] | repeated CrsInfo | `crs_id` (RequestId) and `crs_digest` (`PDAT_CRS` digest bytes; CLI `digest=<hex>`). May be empty. |
| domain | Eip712DomainMsg | Required here (`InvalidArgument` if missing). The CLI sends its default domain. |
| extra_data | bytes | Signed into the new results. The CLI sends version 2 for the new context and epoch. |
| signing_schemes | repeated SigningSchemeType | Same rules as `crs.start`. The CLI's global flag is `--signing-schemes`. |

### `epoch.get_result`: Get epoch result

- **What it does:** Returns the outcome of a `NewMpcEpoch` on this core. For a PRSS-only epoch both lists are empty. For a reshare it returns one `KeyGenResult` per reshared key (`request_id` = key_id, `preprocessing_id`, `key_digests`, signatures) and one `CrsGenResult` per re-signed CRS.
- **Tier reason:** It is the read-back for `epoch.reshare`, and `new-epoch` polls it. It also reports PRSS-only epochs from `epoch.create` (Tier 3), which `kms-init` polls.
- **Notes:**
  - Reads only the in-memory `epoch-requests`, which is unbounded and not seeded at boot. Responses:
    - Pending: `Unavailable`.
    - Unknown: `NotFound`. That includes every epoch created before the last restart, the kms-init epoch among them.
    - Failed: `Internal`, or `Aborted` if the error text contains "abort".
    - Bad ID: `InvalidArgument`.
    - Legacy metadata in a result: `InvalidArgument`.
  - **Destroy does not clear it:** destroying an epoch does not remove its entry here.
  - **No status listing:** `epoch-requests` is not registered with the metastore status service (`MetaStoreStatusServiceImpl::new` in `kms_impl.rs` registers no epoch store).
  - **Key digest order:** digests are sorted by PubDataType.
  - **Callers:** kms-init polls it (1 s, 120 tries); CLI `new-epoch` polls it (500 ms, `--max-iter`). There is no standalone CLI command.
  - **Centralized:** `unimplemented!()`.

| Field | Value |
|---|---|
| ID | `epoch.get_result` |
| Tier | 2 |
| Feature group | `reshare` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetEpochResult` (polled by `kms-init` and `kms-core-client new-epoch`) |
| Requires | `epoch.reshare` |
| Enabled by | Threshold mode |
| Changes state | — |
| Reads state | epoch-requests |
| Related | `epoch.create`, `epoch.reshare`, `epoch.destroy` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_epoch_result`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.get_epoch_result` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_id | RequestId | The `epoch_id` used in `NewMpcEpoch`. 32 bytes, so 64 hex chars, not all zero (`InvalidArgument`). |

## Tier 3: Specialized

### `context.create`: Create MPC context

- **What it does:** Registers a new MPC context on this core: a party set with a threshold, software version and PCR allowlist. The core writes it to private storage (`ContextInfo`) and adds it to the session maker, so that later epochs can be created in it.
- **Tier reason:** The gateway manages MPC contexts and epochs (`ai-docs/ARCHITECTURE.md`), so these are operator actions. Only `docs/guides/core_client.md` ("MPC Context Management") covers it. The harness has no usable CLI path: `new-mpc-context context-toml` is unimplemented.
- **Notes:**
  - **Sync and per core.** The caller must send the same context to every core that should know it. `ContextInfo.verify` checks:
    - party_ids are unique and lie in `1..=n`;
    - `n == 3·threshold + 1`, or `n == 1` with threshold 0;
    - `mpc_identity` values are unique;
    - ECDSA signer addresses are unique;
    - each `ca_cert` subject equals its `mpc_identity`;
    - each `external_url` parses with a host and a port;
    - PCR values are non-empty, but only when the node needs a PCR allowlist (Nitro auto-TLS without `mock_enclave`; not the harness).
  - **Own role:** the core finds its role by matching its own 20-byte ECDSA address against each node's `scheme_digests`/`signer_address`. If no node matches, the context is still stored, but with no role for this core. Each core publishes its address under `PUB-p<i>/VerfAddress/`.
  - **Errors:**
    - Any parse or verify failure: `InvalidArgument`.
    - A `context_id` already in storage or in memory: `AlreadyExists`.
    - A storage or session-maker failure: `Internal`. The stored context is rolled back.
  - **Serialized:** all context creates and destroys on a core go through one mutex in the context manager.
  - **Default context:** `DEFAULT_MPC_CONTEXT` (`0700…0001`) always exists. kms-server deletes it and writes it again at every boot from `[threshold.peers]` (`ensure_default_threshold_context_in_storage`). kms-init does not create it. That default context lists only the booting core's own scheme digest, and `public_storage_url` is empty for every node. Creating a context with that ID gives `AlreadyExists`.
  - **CLI:** `new-mpc-context serialized-context-path --input-path <file>` reads a safe-serialized `ContextInfo` and sends it to every configured core. It fails on the first error. `new-mpc-context context-toml` is `unimplemented!()` and panics. Only `new-testing-mpc-context-file` (`testing` feature) writes such a file, and it needs `config_path` for each core in the client config. The harness client is built with `insecure` only and has no `config_path`, so a harness driver has to build `NewMpcContextRequest` itself.
  - **Centralized:** `CentralizedContextManager.new_mpc_context` in the same file. It has no session maker.

| Field | Value |
|---|---|
| ID | `context.create` |
| Tier | 3 |
| Feature group | `mpc-admin` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/NewMpcContext`; `kms-core-client -f config.toml new-mpc-context serialized-context-path --input-path <file>` |
| Requires | — |
| Enabled by | — |
| Changes state | mpc-contexts |
| Reads state | mpc-contexts, signing-keys |
| Related | `context.destroy`, `epoch.create`, `epoch.reshare`, `custodian.create` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:new_mpc_context`, `core/service/src/engine/context_manager.rs:ThresholdContextManager.new_mpc_context`, `core/service/src/engine/context.rs:ContextInfo.verify` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| new_context | MpcContext | Required; missing gives `InvalidArgument`. The whole request is bounded by `grpc_max_message_size` (harness 104857600 bytes). |
| new_context.context_id | RequestId | 32 bytes, so 64 hex chars, not all zero. Must not exist yet (`AlreadyExists`); `0700…0001` always exists. The proto calls it a "monotonically increasing counter stored on the Gateway", but the KMS does not check order. |
| new_context.mpc_nodes | repeated MpcNode | n nodes. The harness peers are `kms-core-<i>-core-<i>`, i = 1..4. |
| mpc_nodes[].mpc_identity | string | Unique. Must equal the CN of `ca_cert` when that is set. |
| mpc_nodes[].party_id | int32 | Unique, in `1..=n`. A negative value fails conversion (`InvalidArgument`). |
| mpc_nodes[].external_url | string | URL with a host and a port, e.g. `https://kms-core-1-core-1:50001`; the harness peer port is 50001. |
| mpc_nodes[].ca_cert | optional bytes | Must parse as X.509 PEM. |
| mpc_nodes[].signer_address | optional bytes | Deprecated; 20 raw bytes. Must equal the ECDSA256K1 entry of `scheme_digests` when both are set. |
| mpc_nodes[].scheme_digests | repeated SchemeDigest | ECDSA256K1 is the 20-byte address, ED25519 the 32-byte key, MLDSA* a 32-byte digest. Conflicting entries for one scheme give `InvalidArgument`. These decide this core's role (see Notes). |
| mpc_nodes[].extra_signer_addresses | repeated bytes | Each must be a 20-byte address. |
| mpc_nodes[].public_storage_url / public_storage_prefix | string / optional string | Used to fetch a peer's public material during a reshare; must be an S3 URL (not `file://`) for that to work. The prefix defaults to `PUB`. |
| new_context.software_version | string | Semver with at least a major part, e.g. `1`, `1.2`, `1.2.3-alpha`. A leading `v` is allowed. |
| new_context.threshold | int32 | `n == 3·t + 1`, or `t == 0` when n == 1. The harness uses t = 1. |
| new_context.pcr_values | repeated PcrValues | May be empty in the harness (`mock_enclave = true`). |

### `context.destroy`: Destroy MPC context

- **What it does:** Erases every epoch of a context on this core (key shares, CRS metadata and PRSS data), then removes the context from storage and memory. It returns the IDs of the epochs it erased.
- **Tier reason:** The gateway manages MPC contexts and epochs (`ai-docs/ARCHITECTURE.md`), so these are operator actions. Only `docs/guides/core_client.md` ("Destroying an MPC Context") covers it.
- **Notes:**
  - **Sync and per core.** Steps in order:
    1. Parse `context_id`: `InvalidArgument`.
    2. Take the exclusive context destruction lease: `FailedPrecondition` ("Retry once epoch creation has settled") while any `NewMpcEpoch` targets this context or reshares from it.
    3. Destroy each of the context's epochs (see `epoch.destroy`). Epochs already gone are skipped. An epoch whose creation lease is held gives `FailedPrecondition`. The node's last epoch gives `FailedPrecondition` ("only epoch remaining"). Storage errors give `Internal`. It keeps going after a failure and returns the first error, and the context is then left in place.
    4. Context manager: the context is not in the session maker gives `NotFound`. It is the only context left gives `FailedPrecondition`. A storage or session-maker error gives `Internal`.
  - **Retries:** a retry after a partial failure may return an empty or shorter `epoch_ids`. After success, further calls return `NotFound`.
  - **Caller rules:** the KMS does not track which context is active. The proto asks callers not to destroy a context while CRS, keygen or decryption requests on it run.
  - **Default context comes back:** `DEFAULT_MPC_CONTEXT` is written again at the next kms-server boot from `[threshold.peers]`, so destroying it is undone on restart. Its epochs are not restored.
  - **CLI:** `destroy-mpc-context --context-id <id>` sends the request to every configured core and fails on the first error.
  - **Centralized:** only the context manager runs, because there are no epochs. It returns an empty `epoch_ids`.

| Field | Value |
|---|---|
| ID | `context.destroy` |
| Tier | 3 |
| Feature group | `mpc-admin` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/DestroyMpcContext`; `kms-core-client -f config.toml destroy-mpc-context --context-id <id>` |
| Requires | `context.create` |
| Enabled by | — |
| Changes state | mpc-contexts, epochs, keysets, crs |
| Reads state | mpc-contexts, epochs |
| Related | `context.create`, `epoch.destroy`, `epoch.create`, `epoch.reshare` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:destroy_mpc_context`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.destroy_epochs_for_context`, `core/service/src/engine/context_manager.rs:ThresholdContextManager.destroy_mpc_context` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| context_id | RequestId | Required (`InvalidArgument` if missing or malformed). 32 bytes, so 64 hex chars, not all zero. Must be a context in this core's session maker (`NotFound`) and not the last one (`FailedPrecondition`). |

### `epoch.create`: Create MPC epoch (PRSS only)

- **What it does:** `NewMpcEpoch` without `previous_epoch`. It creates a new epoch in a context by running the PRSS setup (z128 and z64) among the context's parties. Each party stores the result as `EpochData/<epoch_id>` in private storage and registers the epoch in its session maker. The new epoch holds no keys.
- **Tier reason:** The gateway manages MPC contexts and epochs (`ai-docs/ARCHITECTURE.md`), so these are operator actions. `kms-init` runs it once at deploy (`docs/guides/kms-server-bin.md` "kms-init"). A PRSS-only epoch holds no keys, so a workload gains nothing for decryption from more of them.
- **Notes:**
  - **Async**, despite the proto saying "synchronous": the RPC returns once a background task has been spawned. Completion is read with `epoch.get_result`. Steps in order:
    1. Rate limiter: `new_epoch` tokens (default 1, harness 25). Held until the task ends. `ResourceExhausted` if the bucket is empty.
    2. Validation: `InvalidArgument`.
    3. Epoch creation lease, read locks on the target context and epoch: `FailedPrecondition` while a `DestroyMpcContext` of that context or a `DestroyMpcEpoch` of that epoch holds the exclusive lease.
    4. Epoch already registered in the session maker: `InvalidArgument` ("Epoch ID … already exists"), not `AlreadyExists`.
    5. RNG reseed: `Unavailable` on failure.
    6. Context lookup: `NotFound` if the context is unknown.
    7. Insert into `epoch-requests`: `AlreadyExists` if this process has seen the ID before, including a failed or still-running attempt.
  - **Retry with a new ID:** a failed epoch creation cannot be retried under the same epoch ID until restart.
  - **PRSS, background task:**
    - It runs over a `Sync` network session of the context, derived from the epoch ID, and needs the other parties to take part.
    - A core that is not a member of the context skips PRSS and records `PRSSInitOnly`.
    - A failure is stored in `epoch-requests`; the epoch is registered only after `EpochData` is written.
    - The lease is held for the whole task.
  - **Epoch ID ordering:** the proto requires every new epoch ID to be greater than the previous one, comparing the raw bytes as a big-endian integer. This is not checked at creation. At boot, `select_data_from_max_epoch` (defined in `core/service/src/vault/storage/mod.rs`, called from `core/service/src/engine/threshold/service/kms_impl.rs`) loads each key's and CRS's metadata from the greatest epoch ID that holds it.
  - **Proto caller rule:** no `KeyGen`, `CrsGen`, `AbortKeyGen` or `AbortCrsGen` concurrently.
  - **Deploy, kms-init:** the harness Job `kms-core-init-threshold-init` runs `bin/kms-init --addresses` with the four addresses `http://kms-core-<i>-core-<i>:50100` once, with a 1200 s timeout and `backoffLimit: 6`.
    - It sends `NewMpcEpoch{context_id: DEFAULT_MPC_CONTEXT 0700…0001, epoch_id: DEFAULT_EPOCH_ID 0800…0001, previous_epoch: None, domain: None, extra_data: v2(default ctx, default epoch), signing_schemes: [ECDSA256K1]}` to all 4 cores in parallel.
    - It then polls `GetEpochResult(0800…0001)` once per second, up to 120 times, and panics on any code other than `Unavailable`.
    - A rerun against a core that already holds the epoch gets `InvalidArgument`, or `AlreadyExists` if it is the same process.
    - Requests that leave out `epoch_id` (decryption, keygen, CRS) default to this epoch.
  - **CLI:** `new-epoch --new-epoch-id <id> --new-context-id <id>` without `--previous-epoch-params` sends the request to every core (domain unset). It then polls `GetEpochResult` every 500 ms up to `--max-iter`. On a core error it panics (`do_new_epoch(...).unwrap()`).
  - **Centralized:** only `DEFAULT_EPOCH_ID` is accepted, and the context must exist (`core/service/src/engine/centralized/service/initiator.rs:init_impl`).

| Field | Value |
|---|---|
| ID | `epoch.create` |
| Tier | 3 |
| Feature group | `mpc-admin` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/NewMpcEpoch` with `previous_epoch` unset; `kms-init --addresses <url>...` (harness deploy); `kms-core-client -f config.toml new-epoch --new-epoch-id <id> --new-context-id <id>` |
| Requires | — |
| Enabled by | Threshold mode (centralized accepts only the default epoch) |
| Changes state | epochs, epoch-requests, mpc-sessions |
| Reads state | mpc-contexts, epochs |
| Related | `epoch.get_result`, `epoch.reshare`, `epoch.destroy`, `context.create`, `context.destroy`, `pubdec.start`, `userdec.start`, `crs.start` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:new_mpc_epoch`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.new_mpc_epoch`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.init_epoch` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| context_id | RequestId | Optional. Unset means `DEFAULT_MPC_CONTEXT` (`0700…0001`). Must be known to this core (`NotFound`). |
| epoch_id | RequestId | Required. 32 bytes, so 64 hex chars, not all zero (`InvalidArgument`). Must be new: a registered epoch gives `InvalidArgument`; an ID this process has seen gives `AlreadyExists`. Callers must keep IDs increasing (see Notes). The harness uses `0800…0001` (kms-init) and random `08…` IDs (`new_epoch_id` in `helper_lib.sh`). |
| previous_epoch | PreviousEpochInfo | Unset for this operation. Set means `epoch.reshare`. |
| domain | Eip712DomainMsg | Ignored when `previous_epoch` is unset. kms-init and the CLI send none. |
| extra_data | bytes | Warning-only checks. Both kms-init and the CLI send version 2 (`0x02` ‖ context_id ‖ epoch_id). |
| signing_schemes | repeated SigningSchemeType | `ECDSA256K1`=0 … `MLDSA87`=4. Empty means ECDSA. An unknown value gives `InvalidArgument`. |

### `epoch.destroy`: Destroy MPC epoch

- **What it does:** Erases one epoch on this core: every `FheKeyInfo` and `CrsInfo` stored under it, then its `EpochData` (PRSS) and any legacy `PrssSetup`. It also drops the epoch's FHE key cache entries and unregisters it from the session maker. Public key and CRS objects are not touched.
- **Tier reason:** The gateway manages MPC contexts and epochs (`ai-docs/ARCHITECTURE.md`), so these are operator actions. It retires an epoch after a reshare. Only `docs/guides/core_client.md` ("Destroying an MPC Epoch") covers it.
- **Notes:**
  - **Sync and per core.** Errors in order:
    1. Missing or malformed ID: `InvalidArgument`.
    2. Exclusive epoch destruction lease: `FailedPrecondition` ("Retry once epoch creation has settled") while a `NewMpcEpoch` is creating this epoch or resharing from it.
    3. Epoch not registered: `NotFound`.
    4. Only epoch on the node: `FailedPrecondition`.
    5. Storage failure: `Internal`. The epoch stays registered, and the call can be retried.
  - **Caller rules:** the KMS does not track an active epoch, so a caller can destroy `0800…0001` while another epoch exists. Requests that omit `epoch_id` then name an epoch that is gone. The proto asks callers not to destroy an epoch while keygen, CRS or decryption requests on it run.
  - **ID cannot be reused yet:** the `epoch-requests` entry stays, so `GetEpochResult` still answers, and creating the same epoch ID again gives `AlreadyExists` until restart.
  - **CLI:** `destroy-mpc-epoch --epoch-id <id>` sends the request to every configured core and fails on the first error.
  - **Centralized:** `unimplemented!()`.

| Field | Value |
|---|---|
| ID | `epoch.destroy` |
| Tier | 3 |
| Feature group | `mpc-admin` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/DestroyMpcEpoch`; `kms-core-client -f config.toml destroy-mpc-epoch --epoch-id <id>` |
| Requires | `epoch.reshare` (or a second epoch from epoch.create) |
| Enabled by | Threshold mode |
| Changes state | epochs, keysets, crs |
| Reads state | epochs |
| Related | `epoch.create`, `epoch.reshare`, `context.destroy`, `epoch.get_result` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:destroy_mpc_epoch`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.destroy_mpc_epoch`, `core/service/src/engine/threshold/service/epoch_manager.rs:RealThresholdEpochManager.destroy_epoch` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| epoch_id | RequestId | Required. 32 bytes, so 64 hex chars, not all zero (`InvalidArgument`). Must be registered on this core (`NotFound`) and must not be its only epoch (`FailedPrecondition`). |

### `custodian.create`: Create custodian context

- **What it does:** Installs a new custodian context on one node: samples a fresh per-context MLKEM1024-P384 backup key pair, Shamir-shares the private half to the `n` custodians (signcrypted to each), writes the signed `RecoveryValidationMaterial` to the backup vault, re-encrypts the whole backup vault under the new public key, and anchors the context in private storage so it becomes the one the node backs up under.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set. It also needs a `secret_sharing` keychain.
- **Notes:**
  - Needs a backup vault with the `SecretSharing` keychain (`[backup_vault.keychain.secret_sharing]`). The harness config (`antithesis/config/manifests/31-kms-core-1.yaml`, and the other three cores) has no `[backup_vault]` section at all. There, a well-formed request passes the request checks and then fails with `Internal` ("Backup vault is not configured") before it touches the meta store. With an `AwsKms` keychain, or a vault with no keychain, it fails with `Internal` ("A secret sharing keychain is not configured") after it has claimed the meta-store entry, so the ID is used up until the next restart.
  - Synchronous: the RPC returns `Empty` once setup finishes. The setup runs on the node's task tracker, so it still completes if the caller disconnects or the gRPC deadline passes (harness `timeout_secs = 360`). A setup that starts after shutdown has begun is refused with `Unavailable`. It re-encrypts every private object into the vault (`update_backup_vault(overwrite=true)`), so its duration grows with the amount of key material.
  - The check order and the codes a caller sees: missing or unparsable `mpc_context_id` → `InvalidArgument`; missing `new_custodian_context` or a bad `custodian_context_id` → `InvalidArgument`; no `ContextInfo` in private storage for `mpc_context_id` → `InvalidArgument`; the custodian context ID was already seen by the custodian meta store → `AlreadyExists`; `InternalCustodianContext::validate_nodes` fails (threshold, roles, payload decode, scheme, duplicate keys) → `InvalidArgument`. Every failure inside the setup task is `Internal`: no vault, no SecretSharing keychain, no root signing seed (`ensure_supported(BACKUP_SIGNING_SCHEMES)`), too few valid setup messages, more than 15 custodians, ID equal to the keychain's current context, a vault re-encryption failure, or a failed write of the recovery material or the anchor.
  - Request-ID reuse: the custodian meta store rejects any ID it has held since boot (pending, completed, failed, or destroyed) with `AlreadyExists`. There is no redo or attach. At boot the meta store is rebuilt from the `RecoveryMaterial` entries in the backup vault only, so a failed or destroyed ID can be reused after a restart.
  - A failed setup is rolled back: the keychain goes back to its previous `(context_id, backup_enc_key)` and the vault entries written under the new ID are purged (`rollback_failed_custodian_setup`). The old context's backups and recovery material stay. A successful create does not delete earlier contexts.
  - It holds `custodian_context_lock` from setup through rollback, so it is serialized with `custodian.destroy` and `recovery.custodian_recover`.
  - Per-node, with no MPC between cores. `kms-core-client new-custodian-context` sends the same request to every core in the client config (it does not have the single-core restriction that the recovery commands have). It makes a random custodian context ID with `RequestId::new_random` and prints it as `new custodian context created - "request_id": "<id>"`. `-i` is the MPC context ID, not the custodian context ID. The default MPC context `0700…0001` is written to private storage at boot (`ensure_default_threshold_context_in_storage`), so no `context.create` is needed first.
  - Offline prerequisite: each custodian runs `kms-custodian generate --custodian-role <r> --custodian-name <name> [--randomness <s>]`, which prints `The custodian setup message is: <base64>` and a 24-word seed phrase (`The SECRET seed phrase for the custodian keys is: …`). The base64 strings go to `-m`. `kms-custodian` is in the harness core-client image (`antithesis/images/kms-binaries.Dockerfile` copies it to `/out/core-client/bin/`). `generate` is not deterministic: it mixes in system entropy.
  - Each setup message's timestamp must be within 24 h of the server clock, and its header must equal `ZAMA TKMS SETUP TEST OPERATORS-CUSTODIAN`. A message that fails either check is skipped, and the call fails (`Internal`) only if fewer than `t + 1` valid messages remain.
  - Centralized mode runs the same code (`SharedContextManager`).

| Field | Value |
|---|---|
| ID | `custodian.create` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/NewCustodianContext`; `kms-core-client new-custodian-context -t <threshold> -i <mpc-context-id> -m <b64 setup msg> [-m …]`, with setup messages from `kms-custodian generate` |
| Requires | — |
| Enabled by | `[backup_vault]` with `[backup_vault.keychain.secret_sharing]` (env `KMS_CORE__BACKUP_VAULT__KEYCHAIN__SECRET_SHARING__ENABLED=true`); not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`); node must have a root signing seed |
| Changes state | custodian-contexts, backup-vault |
| Reads state | mpc-contexts, signing-keys, private-storage, custodian-contexts |
| Related | `custodian.destroy`, `recovery.get_operator_key`, `recovery.init`, `recovery.custodian_recover`, `recovery.restore`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:new_custodian_context`, `core/service/src/engine/context_manager.rs:SharedContextManager.inner_new_custodian_context`, `core/service/src/backup/custodian.rs:InternalCustodianContext.validate_nodes` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| new_custodian_context.custodian_context_id | RequestId | Required. 32 bytes as 64 hex chars (optional `0x` prefix), not all zero. Must be new to the custodian meta store since boot (`AlreadyExists` otherwise) and must differ from the keychain's current context. The CLI always generates it at random. |
| new_custodian_context.threshold | uint32 | `t ≥ 1` and `2t < n`. `t + 1` custodian outputs are needed later to recover. |
| new_custodian_context.custodian_nodes | repeated CustodianSetupMessage | `n ≥ 2t + 1`, so at least 3. At most 15: Shamir sharing over `ResiduePolyF4Z64` cannot embed role 16 (`get_from_exceptional_sequence`), and that fails as `Internal`. Roles must be exactly `1..n`, each once (role 0, a role above `n`, or a duplicate role → `InvalidArgument`). No two nodes may share an encryption key or any verification key (`InvalidArgument`). |
| custodian_nodes[].custodian_role | uint64 | 1-based. See above. |
| custodian_nodes[].name | string | Free text, not validated. |
| custodian_nodes[].payload | bytes | Safe-serialized `CustodianSetupMessagePayload` (limit `SAFE_SER_SIZE_LIMIT`). The encryption key must be MLKEM1024-P384. The verification key set must cover ECDSA-secp256k1 and ML-DSA-87 (`BACKUP_SIGNING_SCHEMES`). Header and ±24 h timestamp are checked at setup (failures are skipped, see Notes). |
| mpc_context_id | RequestId (ContextId) | Required. `ContextInfo` must exist in private storage (`InvalidArgument` otherwise). The harness default is `0700000000000000000000000000000000000000000000000000000000000001`. |
| (whole request) | — | Capped by `grpc_max_message_size` (harness 104857600 bytes). No rate-limiter cost. |

### `custodian.destroy`: Destroy custodian context

- **What it does:** Deletes a retired custodian context from one node: erases every backup entry stored under that context ID in the backup vault, confirms none are left, deletes its `RecoveryValidationMaterial`, and tombstones its custodian meta-store entry.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set.
- **Notes:**
  - Synchronous. It runs on the request itself, not on the task tracker. If the request is dropped, repeat the destroy to finish it. It holds `custodian_context_lock`, so it is serialized with `custodian.create` and `recovery.custodian_recover`.
  - The check order and the codes a caller sees: missing or bad `context_id` → `InvalidArgument`; ID not in the custodian meta store → `NotFound`; entry locked by another in-flight permit → `FailedPrecondition`; entry already tombstoned → `FailedPrecondition`; ID is the context anchored in private storage → `FailedPrecondition`; fewer than 2 successfully completed contexts in the meta store → `FailedPrecondition`; no backup vault → `FailedPrecondition`; vault deletion fails, entries remain after deletion, or the ID is the keychain's current context (`remove_old_backup`) → `Internal`. In the `Internal` cases the meta-store entry is kept, so the call can be retried.
  - So it needs at least two successful `custodian.create` calls on that node, and the target must not be the newest anchored context. In the harness there is no backup vault, so the custodian meta store is always empty and every call returns `NotFound`.
  - Request-ID reuse: after a successful destroy, the ID is tombstoned until restart. A second destroy then gets `FailedPrecondition`, and a create with that ID gets `AlreadyExists`.
  - `kms-core-client destroy-custodian-context` refuses a client config with more than one core ("Custodian destruction is only supported for a single core"). The harness client config (`40-kms-core-init.yaml`) lists 4 cores, so a driver needs its own single-core config per node, or must call gRPC directly.
  - Proto pre-conditions (`kms-service.v1.proto`) match the code. The code adds the "at least two contexts" rule, which `docs/guides/core_client.md#destroy-context` also states.

| Field | Value |
|---|---|
| ID | `custodian.destroy` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/DestroyCustodianContext`; `kms-core-client destroy-custodian-context -i <custodian-context-id>` (single-core config only) |
| Requires | `custodian.create` (at least two on the node; the target must not be the active one) |
| Enabled by | `[backup_vault]` with `[backup_vault.keychain.secret_sharing]`; not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`) |
| Changes state | custodian-contexts, backup-vault |
| Reads state | custodian-contexts |
| Related | `custodian.create`, `recovery.init`, `recovery.custodian_recover`, `metastore.get_statuses`, `metastore.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:destroy_custodian_context`, `core/service/src/engine/context_manager.rs:SharedContextManager.destroy_custodian_context`, `core/service/src/vault/storage/mod.rs:delete_custodian_context_at_id` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| context_id | RequestId | Required. 64 hex chars, not all zero. Must be a completed context in this node's custodian meta store. It must not be the anchored (active) context, and at least 2 completed contexts must exist. |

### `recovery.get_operator_key`: Get operator public key

- **What it does:** Returns the backup encryption public key of the custodian context the node currently backs up under. This is the safe-serialized MLKEM1024-P384 key `pk^B` in the node's `SecretSharing` keychain. With it comes an attestation document over `SHAKE256("ATTESTPK" ‖ key)` when the node has a security module.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set.
- **Notes:**
  - Synchronous, read-only, no request ID.
  - The codes a caller sees: no backup vault → `Unavailable` ("Backup vault is not configured"); vault with an `AwsKms` keychain or no keychain → `Unimplemented`; `SecretSharing` keychain with no context installed yet → `Internal` ("Secret sharing keychain is not initialized"); attestation failure → `Internal`. In the harness there is no `backup_vault` in `31-kms-core-1.yaml`, so every call returns `Unavailable`.
  - A context is installed by a successful `custodian.create`, by boot-time adoption of the anchored context (`adopt_custodian_context`), or by `recovery.custodian_recover` on a node with no anchor. A node in recovery mode skips boot-time adoption, so this returns `Internal` there until a recovery has run.
  - The attestation document is empty when the node has no security module. The harness has one (a mock `DevNitro`), because `[threshold.tls.auto]` with `mock_enclave = true` needs a security module.
  - `kms-core-client get-operator-public-key` sends to every configured core, parses each attestation document with `attestation_doc_validation::validate_and_parse_attestation_doc`, checks the digest, and prints the key as hex. `docs/guides/core_client.md` says it rejects an empty document and "only works against enclave-backed deployments". Whether it accepts the mock-enclave document was not verified. `kms-health-check` also calls this RPC in its live check and records the result without failing health.
  - Centralized mode runs the same code (`RealBackupOperator`).

| Field | Value |
|---|---|
| ID | `recovery.get_operator_key` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/GetOperatorPublicKey`; `kms-core-client get-operator-public-key`; `kms-health-check` (live check) |
| Requires | `custodian.create` |
| Enabled by | `[backup_vault]` with `[backup_vault.keychain.secret_sharing]`; not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`) |
| Changes state | — |
| Reads state | custodian-contexts |
| Related | `custodian.create`, `recovery.init`, `recovery.custodian_recover` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_operator_public_key`, `core/service/src/engine/backup_operator.rs:RealBackupOperator.get_operator_public_key`, `core/service/src/vault/keychain/secretsharing.rs:SecretShareKeychain.operator_public_key_bytes` |
| Confidence | high |

No inputs.

### `recovery.init`: Start custodian recovery

- **What it does:** Starts a custodian-based recovery on one node. It picks the custodian context to recover under, reads that context's `RecoveryValidationMaterial` from the backup vault, checks the operator signatures on it, makes an in-memory ephemeral MLKEM1024-P384 key pair, and returns a `RecoveryRequest`. The request holds the ephemeral public key, the operator's backup verification keys, and the per-custodian signcrypted shares.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set.
- **Notes:**
  - Synchronous, no request ID. The ephemeral private key lives only in process memory: a restart drops it, and a successful `recovery.custodian_recover` clears it. It holds the ephemeral-key mutex for the whole call, but not `custodian_context_lock`.
  - Reuse rule: if an ephemeral key already exists and `overwrite_ephemeral_key` is false → `AlreadyExists`. This is checked before anything else, including the vault check. With `overwrite_ephemeral_key = true` the old key is replaced, which makes custodian outputs made for the previous request useless.
  - Context selection (`recovery_context`): a node with an anchored context recovers under that one, and naming a different ID → `FailedPrecondition` (Conflict). A node with no anchor uses the named ID (`NotFound` if the vault has no material for it) or, when none is named, the only context in the vault. More than one context → `FailedPrecondition` (Ambiguous, the message lists the IDs), and none → `FailedPrecondition` (NoContext).
  - Other codes: no backup vault → `Unavailable`; keychain is not `SecretSharing` → `Unavailable`; malformed `custodian_context_id` → `InvalidArgument`; material fails signature validation → `InvalidArgument`; anchor or storage read errors and request build errors → `Internal`. In the harness there is no `backup_vault`, so after the ephemeral-key check every call returns `Unavailable`.
  - It works on a healthy node as well as on a node in recovery mode. Recovery mode is a node that booted without its signing key (`boot_base_kms` → `BaseKmsStruct::new_no_signing_key`). Such a node skips boot-time storage verification, peer sync and custodian-context adoption, and runs without core-to-core TLS. Its ECDSA verification key comes from public storage, or from the `operator_verf_keys` embedded in the vault's recovery material when public storage lost it. Without a signing identity, this RPC validates the material with the ECDSA key alone and takes the other backup keys from the material. All RPCs stay registered in recovery mode, with no gate at the gRPC layer. Operations that need the signing key fail, and the recovery RPCs (`recovery.init`, `recovery.custodian_recover`, `recovery.restore`) are the ones meant to be used.
  - In the harness, the `kms-core-init-gen-keys` init container runs `kms-gen-keys` before `kms-server` at every pod start. That makes a new signing identity if private storage has none, or fails. So a plain pod restart after losing the signing key is not expected to boot in recovery mode (not verified end to end).
  - `kms-core-client custodian-recovery-init` refuses a config with more than one core. It skips fetching verification keys from public storage, prints the request base64-encoded (`<b64> - no request_id returned`), and prints every operator key fingerprint. With `--expected-operator-key SCHEME=0x…` it fails on a mismatch (a client-side check only). The base64 request then goes to each custodian's `kms-custodian decrypt` (see `recovery.custodian_recover`).
  - Centralized mode runs the same code.

| Field | Value |
|---|---|
| ID | `recovery.init` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/CustodianRecoveryInit`; `kms-core-client custodian-recovery-init [-o] [-i <custodian-context-id>] [--expected-operator-key SCHEME=VALUE …]` (single-core config only) |
| Requires | `custodian.create` |
| Enabled by | `[backup_vault]` with `[backup_vault.keychain.secret_sharing]`; not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`) |
| Changes state | recovery-session |
| Reads state | custodian-contexts, backup-vault, signing-keys, recovery-session |
| Related | `custodian.create`, `recovery.custodian_recover`, `recovery.get_operator_key`, `custodian.destroy` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:custodian_recovery_init`, `core/service/src/engine/backup_operator.rs:RealBackupOperator.custodian_recovery_init`, `core/service/src/engine/backup_operator.rs:recovery_context` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| overwrite_ephemeral_key | bool | Default false. When false and a recovery is already started → `AlreadyExists`. CLI `-o`/`--overwrite-ephemeral-key` (a clap 4 `bool` field, so a presence flag). |
| custodian_context_id | optional RequestId | 64 hex chars, not all zero (`InvalidArgument` otherwise). With an anchored context, must be omitted or equal to it (`FailedPrecondition`). With no anchor, required when the vault holds more than one recovery material (`FailedPrecondition`), and must exist in the vault (`NotFound`). CLI `-i`/`--custodian-context-id`. |
| expected-operator-key (CLI only) | `SCHEME=0x…`, repeatable | Client-side check of the returned operator keys. Each scheme at most once. Not sent to the server. |

### `recovery.custodian_recover`: Finish custodian recovery

- **What it does:** Takes the custodians' re-signcrypted shares for the started recovery and checks each against the vault's `RecoveryValidationMaterial`. When at least `t + 1` are valid, it rebuilds the backup decryption key and puts it in the `SecretSharing` keychain for the length of the call, then runs `recovery.restore` to refill private storage from the vault. If the node had no anchored context, it then anchors the recovered context.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set. It also needs offline `kms-custodian decrypt` runs between `recovery.init` and this call.
- **Notes:**
  - Synchronous, no request ID. It holds `custodian_context_lock` from context selection to the end of the restore, so it is serialized with `custodian.create` and `custodian.destroy`.
  - The check order and codes: no ephemeral key (no `recovery.init` since boot, or already consumed) → `FailedPrecondition` (checked first); no backup vault → `Unavailable`; missing or bad `custodian_context_id` → `InvalidArgument`; context selection errors as in `recovery.init` (an anchored node asked for another ID → `FailedPrecondition`; unknown ID → `NotFound`; keychain not `SecretSharing` → `Unavailable`); material signature check → `InvalidArgument`; fewer than `t + 1` valid outputs → `InvalidArgument` (`RecoveryThresholdNotMet`, with the skip reasons); key reconstruction or decode failure → `Internal`; keychain or anchor moved to another context during the call → `Aborted`; restore failure → `Internal`; anchor-install failure after a successful restore → `Internal`. In the harness there is no `backup_vault`, so the reachable outcomes are `FailedPrecondition` (no `recovery.init` succeeded) and `Unavailable`.
  - Retry: the ephemeral key is cleared only after a successful restore. After a failure the same `recovery.init` request can be used again with more or different outputs. After a success, another call gets `FailedPrecondition` until a new `recovery.init`.
  - The reconstructed key is cleared from the keychain when the call ends, cancellation included (`RecoveredKeys` drop guard). Restored data is not loaded into memory: the node must restart to use it, and a node that booted in recovery mode stays in recovery mode until then.
  - On a healthy node with an anchored context, the call has to name that context. The restore skips every entry already in private storage, so it can succeed without changing anything.
  - Offline steps a driver must automate between `recovery.init` and this call. For each custodian role `r` (at least `t + 1` of them): `kms-custodian decrypt --seed-phrase "<24 words from generate>" --custodian-role <r> --recovery-request <b64 from custodian-recovery-init> [--randomness <s>]`. It prints `The custodian recovery output is: <b64>`. Then pass all outputs with `-r` to `custodian-backup-recovery -i <custodian-context-id>`. `kms-custodian decrypt` fails if the request has no share for that role. It is not deterministic (it mixes in system entropy).
  - `kms-core-client custodian-backup-recovery` refuses a config with more than one core, errors locally on zero `-r` values, and skips fetching verification keys from public storage.
  - Centralized mode runs the same code.

| Field | Value |
|---|---|
| ID | `recovery.custodian_recover` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/CustodianBackupRecovery`; `kms-custodian decrypt …` per custodian, then `kms-core-client custodian-backup-recovery -i <custodian-context-id> -r <b64> [-r …]` (single-core config only) |
| Requires | `recovery.init`, `custodian.create` |
| Enabled by | `[backup_vault]` with `[backup_vault.keychain.secret_sharing]`; not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`) |
| Changes state | private-storage, custodian-contexts, recovery-session |
| Reads state | backup-vault, custodian-contexts, recovery-session, signing-keys |
| Related | `recovery.init`, `recovery.restore`, `custodian.create`, `custodian.destroy`, `material.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:custodian_backup_recovery`, `core/service/src/engine/backup_operator.rs:RealBackupOperator.custodian_backup_recovery`, `core/service/src/engine/backup_operator.rs:filter_custodian_data` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| custodian_context_id | RequestId | Required (`InvalidArgument` if missing or malformed). 64 hex chars, not all zero. On an anchored node it must equal the anchored context. Otherwise it must have recovery material in the vault (`NotFound`). |
| custodian_recovery_outputs | repeated CustodianRecoveryOutput | Needs at least `t + 1` valid entries, where `t` is the context's threshold and `n ≤ 15` its custodian count. Invalid entries are skipped, not fatal: role 0 or above `n`, missing or unparsable signcryption, failed validation, or a duplicate role (the first one counts). |
| custodian_recovery_outputs[].custodian_role | uint64 | 1-based, `1..n`. |
| custodian_recovery_outputs[].backup_output.signcryption | bytes | Custodian→operator signcryption from `kms-custodian decrypt`, bound to the current ephemeral key. |
| custodian_recovery_outputs[].backup_output.pke_type | enum PkeSchemeType | `MLKEM512 = 0`, `MLKEM1024 = 1`, `MLKEM1024_P384 = 2`. Outputs made by `kms-custodian` use `MLKEM1024_P384`. |
| (whole request) | — | Capped by `grpc_max_message_size` (harness 104857600 bytes). No rate-limiter cost. |

### `recovery.restore`: Restore private storage from backup

- **What it does:** Copies every object in the backup vault that private storage lacks back into private storage, decrypting it with the vault's keychain if there is one. It writes in a fixed order (`RESTORE_ORDER`): `ContextInfo`, `EpochData`, legacy `PrssSetupCombined` and `PrssSetup`, `FheKeyInfo`, `FhePrivateKey`, `CrsInfo`, `SigningSeed`, `SigningKey`.
- **Tier reason:** Only the backup docs cover it (`docs/guides/backup.md`, `docs/guides/core_client.md` "Backup and recovery"). It needs a `[backup_vault]` section that the harness config does not set.
- **Notes:**
  - Synchronous, no request ID, idempotent. Entries already in private storage are skipped with a warning and never overwritten. A restore that stops half-way can be run again. It holds the private-storage and backup-vault locks for the whole copy. Restored data is only loaded at boot, so the node must restart afterwards.
  - Codes: no backup vault → `Unavailable`; any read, decrypt or write error → `Internal` ("Failed to restore backup data"). In the harness there is no `backup_vault` in `31-kms-core-1.yaml`, so every call returns `Unavailable`.
  - Behaviour by keychain:
    - No keychain: a plain copy (an unencrypted "import/export" vault).
    - `AwsKms` keychain: decrypts each object through AWS KMS. The harness has no AWS KMS endpoint configured.
    - `SecretSharing` keychain: decryption needs the reconstructed key, which only exists inside `recovery.custodian_recover` (which calls this function). Called on its own, it fails with `Internal` when the keychain has no context, or when any vault entry is missing from private storage. It succeeds, changing nothing, when everything is already present.
  - What fills the vault: once `[backup_vault]` is set, the node copies new private objects into it at every boot (`update_backup_vault(false, OP_BOOT)`) and after every private-storage write (`CryptoMaterialStorage.write_all` → `update_backup_vault`). A failed backup update makes that write fail with a backup error. With a `SecretSharing` keychain nothing is backed up until a custodian context is installed.
  - `kms-core-client backup-restore` sends to every core in the config (there is no single-core restriction), after fetching the cores' verification keys from public storage.
  - Centralized mode runs the same code.

| Field | Value |
|---|---|
| ID | `recovery.restore` |
| Tier | 3 |
| Feature group | `backup` |
| Kind | admin |
| How to call | `kms_service.v1.CoreServiceEndpoint/RestoreFromBackup`; `kms-core-client backup-restore` |
| Requires | — |
| Enabled by | `[backup_vault]` (any keychain: none, `aws_kms`, or `secret_sharing`; with `secret_sharing` it is only useful through `recovery.custodian_recover`); not set in the harness (`31-kms-core-1.yaml` has no `backup_vault`) |
| Changes state | private-storage |
| Reads state | backup-vault, private-storage |
| Related | `recovery.custodian_recover`, `custodian.create`, `material.list` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:restore_from_backup`, `core/service/src/engine/backup_operator.rs:RealBackupOperator.restore_from_backup`, `core/service/src/engine/backup_operator.rs:restore_data` |
| Confidence | high |

No inputs.

### `material.list`: List key material

- **What it does:** Returns the IDs of the FHE keys and CRSs this core has in its private storage, the IDs of its completed preprocessing sets that no keygen has used yet (threshold only), and a storage description string.
- **Tier reason:** It is an inventory read. Its only caller is `kms-health-check`, which uses it as a fallback, so it is an operator tool. `docs/references/api/core_grpc.md` gives it its own section ("Key Material Availability").
- **Notes:** Read-only: no request ID, no rate-limiter cost, no MPC, and no peer queries (asking peers is what `GetHealthStatus` does). Threshold: `fhe_key_ids` = every ID with `FheKeyInfo` in private storage under any epoch, deduplicated, in no defined order; `crs_ids` = every ID with `CrsInfo` under any epoch; `preprocessing_ids` = the Completed (`Done(Ok)`) entries of the in-memory preprocessing meta store. Secure and insecure preprocessing share that store. A preprocessing that keygen consumed is tombstoned and drops out. The store is not reloaded at boot, so the list is empty after a restart. `storage_info` = "<kms type> - <private storage info>". The call holds the private-storage mutex while it lists, so it waits behind anything else holding that lock. A storage listing error → `Internal`. Centralized: `fhe_key_ids` come from `FhePrivateKey` entries and `preprocessing_ids` is empty. Callers: `kms-health-check live` / `full` call it only as a fallback when `GetHealthStatus` fails. The harness drivers do not call it; they find keys by listing `PUB-p1/PublicKey/` in MinIO (`helper_lib.sh:find_key_id`).
- **Uncertain:** It is a cheap read of what keygen and CRS generation created, so it could sit in Tier 1 as a read-back. It stays in Tier 3 because only the health-check tool calls it.

| Field | Value |
|---|---|
| ID | `material.list` |
| Tier | 3 |
| Feature group | — |
| Kind | admin |
| How to call | `GetKeyMaterialAvailability` (empty request); `kms-health-check live --endpoint <host>:50100` (only as fallback after `GetHealthStatus` fails) |
| Requires | — |
| Enabled by | — |
| Changes state | — |
| Reads state | keysets, crs, preproc-requests |
| Related | `keygen.start_insecure`, `crs.start`, `crs.start_insecure`, `preproc.start_insecure`, `keygen.abort`, `epoch.reshare`, `recovery.restore` |
| Code locations | `core/service/src/engine/threshold/endpoint.rs:get_key_material_availability`, `core/service/src/engine/utils.rs:query_key_material_availability`, `core/service/src/engine/threshold/service/preprocessor.rs:RealPreprocessor.get_all_preprocessing_ids` |
| Confidence | low |

No inputs.

### `metastore.get_statuses`: Get request statuses

- **What it does:** Looks up a list of request IDs in this core's in-memory meta stores and returns, for each ID found, the store it is in and its status: PROCESSING, COMPLETED, FAILED (with the error text) or DELETED.
- **Tier reason:** It is on the separate `MetaStoreStatusService`, which has its own README (`core/grpc/proto/README-metastore-status.md`). The README names the KMS connector as its user, to resync after a connector failure. No CLI or client in the repo calls it.
- **Notes:** Separate gRPC service `metastore_status.v1.MetaStoreStatusService`, served on the same port as `CoreServiceEndpoint` (50100) but registered without a message-size override, so tonic's default 4 MiB decode limit applies and `grpc_max_message_size` does not. Read-only; no rate limiter. Threshold stores searched: key generation (seeded at boot with every key in storage, so keys from before a restart show COMPLETED), public decryption, user decryption, CRS (also seeded at boot), and preprocessing (in memory only). Epoch/reshare requests and custodian contexts are not covered: `MetaStoreType` has no value for them. IDs that do not parse are skipped (warning log). IDs not found are left out of the response; if none of the given IDs is found the call returns `NotFound`; an empty `request_ids` list returns OK with no statuses. An ID present in several stores yields one entry per store. No client or CLI in this repo calls the service; the README names the external KMS connector as its user (state sync after a connector failure). Centralized: there is no preprocessing store.

| Field | Value |
|---|---|
| ID | `metastore.get_statuses` |
| Tier | 3 |
| Feature group | `request-status` |
| Kind | admin |
| How to call | `metastore_status.v1.MetaStoreStatusService/GetRequestStatuses` on port 50100 (no CLI or client in the repo) |
| Requires | — |
| Enabled by | — |
| Changes state | — |
| Reads state | keygen-requests, pubdec-requests, userdec-requests, crs-requests, preproc-requests |
| Related | `metastore.list`, `metastore.info`, `pubdec.start`, `pubdec.get_result`, `userdec.start`, `userdec.get_result`, `crs.start` |
| Code locations | `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.get_request_statuses`, `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.get_store_status` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| request_ids | repeated string | Each 64 hex chars (`0x` prefix, upper-case and whitespace accepted; the all-zero ID is accepted here). Unparsable entries skipped. No count limit other than the 4 MiB message limit. |
| meta_store_type | optional MetaStoreType | ALL=0, KEY_GENERATION=1, PUBLIC_DECRYPTION=2, USER_DECRYPTION=3, CRS_GENERATION=4, PREPROCESSING=5. Unset, ALL, or an unknown value → all stores. |

### `metastore.list`: List requests

- **What it does:** Lists the request IDs and statuses held in one meta store, optionally filtered by status, one page at a time.
- **Tier reason:** It is on the separate `MetaStoreStatusService`, which has its own README (`core/grpc/proto/README-metastore-status.md`). The README names the KMS connector as its user, to resync after a connector failure. No CLI or client in the repo calls it.
- **Notes:** `meta_store_type` must name one store. ALL, which is also what an unset field reads as (proto3 default 0), is rejected with `InvalidArgument` "Use specific store type for listing"; an unknown value → `InvalidArgument`; a store the mode lacks (PREPROCESSING on centralized) → `Unavailable`. Page size: unset or ≤ 0 → 100, larger values clamped to 1000. `page_token` is a decimal offset into the filtered sequence; `next_page_token` = offset + page length, and is set only when more items exist. Each page is taken under the store's read lock; between calls the store keeps changing (inserts, completions, evictions), so the same offset can cover different entries on the next call. Order: COMPLETED and FAILED in completion order, oldest first; PROCESSING, ANY and DELETED in hash-map order. ANY includes tombstoned entries. Same service, port, size limit and set of stores as `metastore.get_statuses`. Read-only; no rate limiter.

| Field | Value |
|---|---|
| ID | `metastore.list` |
| Tier | 3 |
| Feature group | `request-status` |
| Kind | admin |
| How to call | `metastore_status.v1.MetaStoreStatusService/ListRequests` on port 50100 (no CLI or client in the repo) |
| Requires | — |
| Enabled by | — |
| Changes state | — |
| Reads state | keygen-requests, pubdec-requests, userdec-requests, crs-requests, preproc-requests |
| Related | `metastore.get_statuses`, `metastore.info`, `pubdec.start`, `userdec.start`, `crs.start` |
| Code locations | `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.list_requests`, `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.list_store_requests` |
| Confidence | high |

| Input | Type | Limits and notes |
|---|---|---|
| meta_store_type | MetaStoreType | KEY_GENERATION=1, PUBLIC_DECRYPTION=2, USER_DECRYPTION=3, CRS_GENERATION=4, PREPROCESSING=5. ALL=0 (or unset) → `InvalidArgument`; unknown → `InvalidArgument`. |
| status_filter | optional RequestProcessingStatus | PROCESSING=0, COMPLETED=1, FAILED=2, ANY=3, DELETED=4. Unset or unknown → ANY. |
| max_results | optional int32 | Unset or ≤ 0 → 100 (`DEFAULT_PAGE_SIZE`); above 1000 → 1000 (`MAX_PAGE_SIZE`). Decryption stores hold up to `dec_capacity` entries (harness 10000). |
| page_token | optional string | Decimal `usize` offset. Empty or unset → 0; non-numeric → `InvalidArgument`; past the end → empty page. |

### `metastore.info`: Get meta-store info

- **What it does:** Returns, for each meta store the status service holds, its type, its capacity and its current number of entries.
- **Tier reason:** It is on the separate `MetaStoreStatusService`, which has its own README (`core/grpc/proto/README-metastore-status.md`). The README names the KMS connector as its user, to resync after a connector failure. No CLI or client in the repo calls it.
- **Notes:** `capacity` for the public and user decryption stores is `threshold.dec_capacity` (harness 10000; centralized constant 10000). The key generation, CRS and preprocessing stores are unlimited and report -1 (`usize::MAX` cast to int32). `current_count` counts every entry in the store, including completed, failed and tombstoned ones, not only in-flight requests. `min_dec_cache` is not reported. Threshold returns five entries in the order KEY_GENERATION, PUBLIC_DECRYPTION, USER_DECRYPTION, CRS_GENERATION, PREPROCESSING; centralized leaves out PREPROCESSING. No error path in the handler. Same service and port as `metastore.get_statuses`; read-only; no rate limiter.

| Field | Value |
|---|---|
| ID | `metastore.info` |
| Tier | 3 |
| Feature group | `request-status` |
| Kind | admin |
| How to call | `metastore_status.v1.MetaStoreStatusService/GetMetaStoreInfo` (empty request) on port 50100 (no CLI or client in the repo) |
| Requires | — |
| Enabled by | — |
| Changes state | — |
| Reads state | keygen-requests, pubdec-requests, userdec-requests, crs-requests, preproc-requests |
| Related | `metastore.get_statuses`, `metastore.list`, `pubdec.start`, `userdec.start` |
| Code locations | `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.get_meta_store_info`, `core/service/src/grpc/metastore_status_service.rs:MetaStoreStatusServiceImpl.get_store_info` |
| Confidence | high |

No inputs.
