---
sut_path: /home/exedev/kms
commit: cded11934d315d8079efb8049d4db68fc3770377
updated: 2026-10-19
---

# Coverage setup

Set up for `antithesis-coverage-workload` on the existing Kubernetes harness. The user asked
for no log sidecar and no change to the harness topology, so only the driver interface, the
local coverage build and the local runner exist (no `antithesis/sidecar/`, no reducers).

- **How drivers reach the system:** two ways, both in the `kms-core-client-0` pod.
  - The existing `kms-core-client` CLI, through `helper_common.run_cli()`, for the
    operations that start work. It encrypts, signs, polls and verifies, which a driver
    can't do without the Rust crypto.
  - Direct gRPC to one core's service port (50100), through
    `helper_grpc.call_with_request_id()`, for the RPCs that take only a `RequestId`: the
    result RPCs and `AbortKeyGen`. The CLI has no command for some of them
    (`GetUserDecryptionResult`), and rejects malformed IDs before sending.

  There is no `helper_client.py`; `helper_common.py` and `helper_grpc.py` hold the above.
- **Shared state:** `/tmp/kms-workload-state` in the client container: pools of
  preprocessing IDs, key IDs and request IDs, and each timeline's knobs.
- **Logs:** no sidecar. SUT output goes to container stdout (`kubectl logs` locally;
  Antithesis collects it). The property catalog stays in the workload as SDK assertions.
- **Local runs:** `antithesis/local/run-local.sh <label> [seed]`, after `make build`,
  `make build-coverage` and `make k3s`, with the same `ENGINE` as the builds (on this VM
  `ENGINE=docker`; with the default podman the LCOV conversion can't find the tools image). It redeploys the kapp app `kms` from scratch with the
  coverage build, runs `local/local_composer.py` (the skill's composer, unchanged) in the
  client pod for `DURATION` = 480 s with 4 drivers at once, stops the cores, and converts
  their profiles. One run takes about 11 minutes. It produces `out/<label>/coverage.lcov`
  (kms-server, all four cores merged), plus `ops.txt`, `workload.log` and `sdk.jsonl`.
- **Coverage format and paths (local):**
  `coverage_report.py normalize --format lcov out/<label>/coverage.lcov --repo /home/exedev/kms --strip-prefix /app/kms-binaries/`.
  The baseline normalized to 248 SUT files, 2125 functions, 11961 lines (3 seeds merged).
- **Coverage format and paths (Antithesis):** `.results.coverage` of
  `snouty --json runs show <run-id>` (through `build/bin/snouty`). The zama tenant's
  `advanced_k8s_test` exports it only for runs launched after 2026-10-20; the baseline run
  `26624b2b…-64-4` has none. Save it as `antithesis/local/antithesis/<run-id>.json` and
  normalize with
  `coverage_report.py normalize --format antithesis <file> --repo /home/exedev/kms --label <name>`.
  No `--keep-function` is needed: SUT paths are repo-relative (`core/…`, `core-client/…`,
  `observability/…`), and the dependency paths that are relative too (`src/…`, tfhe-rs and
  others) don't exist in the repo, so `--repo` drops them. The first export normalized to 127
  files, 1,283 functions, 2,554 lines and 5,801 edges. It covers kms-server, kms-core-client,
  kms-init and kms-gen-keys, and names functions differently from `llvm-cov`, so a diff
  against a local snapshot lists many names on both sides that are the same code: compare
  Antithesis runs with each other, and use local runs for what was never reached.
  snouty answers `runs show` from a local cache, so a run fetched before it finished can come
  back stale: set `SNOUTY_API_CACHE_DIR` to an empty folder to fetch it fresh.

## Coverage build

- `antithesis/images/coverage.Dockerfile`, built by `images/build-coverage.sh`
  (`make build-coverage`): kms-server only, `-C instrument-coverage` with runtime counter
  relocation, no `--cfg antithesis`. Only the repo's own crates are instrumented
  (`images/coverage-rustc.sh`, a `RUSTC_WRAPPER`, since 2026-10-20): with every crate
  instrumented the dependencies' multithreaded crypto loops ran 65–70x slower (an insecure CRS
  took 269–468 s instead of 4–7 s), and their coverage is dropped by `--repo` anyway. Snapshots
  before and after are comparable file by file, but the faster build runs more commands per
  local run, so iter05b re-measures iter05's workload on it. It replaces kms-server in a copy of the core-service
  image tagged `<TAG>-coverage`. That tag is not in `settings.sh`'s `IMAGES`, so it is never
  pushed, validated or launched.
- `localhost/kms-antithesis/kms-coverage-tools:intermediate` holds `llvm-profdata`, `llvm-cov`,
  `rustfilt` and the exact instrumented binary at `/out/kms-server`; `run-local.sh` converts in
  it.
- `antithesis/local/coverage-config.py` renders `build/config-coverage/` from `build/config/`:
  in the containers that run kms-server it swaps in the `-coverage` image, sets
  `LLVM_PROFILE_FILE=/coverage/%p-%c.profraw` (continuous mode: counters reach the file while
  the server runs), and mounts the host folder `/var/lib/kms-coverage/<statefulset>`.
- Writing coverage on stop: checked. `run-local.sh` scales the core StatefulSets to 0 before
  it copies the profiles, and the first run got one non-empty `.profraw` per core.

## Known gaps

- Function names: `llvm-cov export` ignores `-Xdemangler`, so `run-local.sh` pipes the LCOV
  through `rustfilt`. Without it the names stay v0-mangled (`_R...`) and nothing matches.
- `coverage_report.py by-op` shows async trait methods and the gRPC endpoint methods (the
  `endpoint.rs` entries in api-surface.md) as `name?` even when reached: Rust's LLVM coverage
  records them only as their `{closure#N}` bodies, and the matcher compares whole names. Read
  their reach from the lines column, or search the snapshot for `<method>::{closure`.
- Local coverage is kms-server only. Antithesis also instruments kms-core-client, kms-init and
  kms-gen-keys, so compare the two by function, on server code.
- No faults locally, and the composer skips `eventually_` commands, so the recovery check
  never runs in a local measurement.
- The composer stops the drivers still running when the time is up; they show as non-zero
  exits in its summary (4 per run at concurrency 4). Property verdicts are in `sdk.jsonl`.
- Disk: k3s deletes unused images and evicts pods at 85 % disk use, which ruins a run without
  an error (it happened once: the client pod and the MinIO image went, and driver runs fell
  from ~700 to ~30). `run-local.sh` stops at 82 %. A run leaves about 600 MB in
  `out/<label>/`, mostly `coverage.lcov`: delete that once `snapshot.json` is normalized
  (`raw/` and the tools image can regenerate it).
- On this VM k3s runs with `cluster-cidr 10.52.0.0/16` (`/etc/rancher/k3s/config.yaml`),
  because the VM's own network is k3s' default `10.42.0.0/16`. `kubectl` needs
  `KUBECONFIG=~/.kube/config`.
