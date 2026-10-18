# Probes: a restarting core panics because its service port is already bound

<!-- Internal evidence, written by the orchestrator (live-debugging.md). The plan comes first and
is written BEFORE any probe runs. Never given to the blinded root-cause step: the explanations and
"ruled out" lines are hypotheses. The raw outputs in probes/<name>/ are observations. -->

- **Finding name:** `boot-panic-port-in-use` (entry: [false-positives.md](../false-positives.md#boot-panic-port-in-use))
- **Guarantee:** none directly. The failing property is Antithesis's default "No unexpected container exits" (kms-core, exit code 101). It touches [Guarantee 2](../guarantees.md#guarantee-2) (a restarted core rejoins), because a core that panics at boot stays down until kubelet restarts it.
- **Run:** [`5a41ff45`][report] (iterate-3, completed 23:25:59Z; triage digest [iterate-3.md](../runs/iterate-3.md))
- **Probed inside the run:** no. The run had completed and `runs exec` refused it ([Probe 1](#timeline-a)). Debugging sessions were out of scope for this pass, so everything below comes from logs and code.

| Timeline | What distinguishes it | Failure | Log |
|---|---|---|---|
| [Timeline A](#timeline-a) | the triaged counterexample. kms-core-2 is in a boot crash loop while network faults cut it off from MinIO | kms-core-2 `kms-core` panics at `kms-server.rs:594` "Could not bind to 0.0.0.0:50100 … AddrInUse" at vtime 1122.87; exits 101 at 1123.32 | [log][a] |
| [Timeline B](#timeline-b) | a sibling branch: same history as Timeline A up to vtime 1107.42, then a different fault schedule | the same panic at vtime 1123.24 | [log][b] |

## What the logs show

From [the downloaded log](../logs/iterate-3-exit101-kms-core-7321595884095562299.ndjson) (Timeline A, root to 1123.32):

- **Each boot failure of kms-core-2 is followed at once by its init containers running again.**
  `kms-core` exits at 644.00, 717.44, 810.61, 901.06, 992.21 and 1048.67, each time with "reading
  failed for FheKeyInfo … streaming error". Between 0.2 and 0.8 s later, `kms-core-init-load-env`
  starts again, then `kms-core-init-gen-keys`, then a new `kms-core`. The log source's
  `restart_count` alternates 0, 1, 0, 1… instead of growing. Kubelet re-runs init containers only
  when it recreates the pod sandbox. So each restart probably gets a new sandbox, and with it a new
  network namespace. No log line states this directly.
- **The last cycle before the panic:**
  - The previous `kms-core` printed "KMS Server service socket address: 0.0.0.0:50100" at 1034.58
    and bound the port without error. It got as far as "KMS verifying key is …" (line 611) and
    failed with the FheKeyInfo error at 1048.67.
  - `kms-core-init-load-env` ran from 1049.00 to 1062.35 and made about 8 `curl` calls to
    `minio:9000`.
  - `kms-core-init-gen-keys` ran from 1063.01 to 1107.12 and made 40 S3 operations against
    `minio:9000`, under several Stopped partitions and clogs between kms-core-2 and MinIO
    (1068.27 to 1100.39).
  - The new `kms-core` started at 1108.05 and bound the metrics port 9646 at once. It then made
    43 S3 operations against `minio:9000` (migration checks and key existence checks). The
    last one was at 1122.828, 45 ms before it printed the socket address and panicked on the bind
    at 1122.8736.
- **The bind** (`kms-server.rs:592-594`) is `tokio::net::TcpListener::bind`. It comes after
  `migrate_to_0_15_x` and the vault setup, which make all those S3 calls, and before
  `boot_base_kms`. tokio binds through `mio`, which sets `SO_REUSEADDR` before `bind` on every
  non-Windows platform. Before line 592, the only socket kms-server binds is the metrics listener
  ([telemetry.rs:194](../../../observability/src/telemetry.rs), `0.0.0.0:9646`). The MPC listener
  on 50001 is bound later, by `make_mpc_listener`.
- **The container:** the pod has one app container, `kms-core`, with no `hostNetwork`, no
  `shareProcessNamespace` and no sysctls. Its command is
  `/bin/sh -c '…; kms-server --config-file=kms-server.toml'`
  ([manifest](../../config/manifests/32-kms-core-2.yaml)). The image is
  [docker/core/service/Dockerfile](../../../docker/core/service/Dockerfile) (`prod` target, with
  `net-tools`) and has no supervisor or wrapper besides that `sh -c`.

## What's still unexplained

What socket holds local port 50100 in kms-core-2's network namespace at 1122.87, and which process,
if any, owns it.

50100 lies inside Linux's default ephemeral port range (32768–60999). It is also even, which is the
parity Linux prefers for `connect()`. So an outgoing connection from inside the pod may have been
given local port 50100: the init containers' `curl` or `kms-gen-keys`, or kms-server's own S3
client. A client socket like that has no `SO_REUSEADDR`. While it is ESTABLISHED, or in
TIME_WAIT (60 s) or FIN_WAIT after a close, Linux refuses to bind `0.0.0.0:50100`, even for a
listener that sets `SO_REUSEADDR`. The logs can't show sockets.

## Explanations still open

1. **(a) A leftover kms-server from the previous container** still holds a listener on 50100 in the
   same network namespace. Either the `sh -c` wrapper died but the server lived on, or the old
   container wasn't torn down when the new one started.
2. **(b) Another container or process in the pod** listens on 50100: an init container leftover,
   the sandbox, or an injected sidecar.
3. **(c) A kernel socket state, not a listener:** a non-listening socket with local port 50100
   in the pod's network namespace. It could be an outgoing connection that the kernel gave
   ephemeral port 50100, from kms-server's own S3 client or from an init container, either still
   ESTABLISHED or in TIME_WAIT/FIN_WAIT after a close. It could also be a server-side TIME_WAIT left
   by the previous listener.
4. **(d) The platform** (Antithesis's Kubernetes, the fault injector) doing something to the pod's
   network namespace. That would show as a socket on 50100 owned by no pod process, or as no
   conflicting socket at all when the bind fails.
5. **(e) A kms-server defect:** the new kms-server itself already holds a listener on 50100 before
   line 592, so it binds the port twice.

## Plan

Written before any probe ran. A probe whose result wouldn't change any verdict isn't run. Moments
are on Timeline A, and each one's input hash is in its script.

In `/proc/net/tcp*`, port 50100 is `C3D4` and MinIO's service `10.43.242.13:9000` is
`0DF22B0A:2328`. TCP states: `01` ESTABLISHED, `06` TIME_WAIT, `0A` LISTEN.

| # | Timeline, vtime | Container | What it reads | If 1 (a) | If 2 (b) | If 3 (c) | If 4 (d) | If 5 (e) |
|---|---|---|---|---|---|---|---|---|
| 1 | A, 1122.8280 (45 ms before the bind) | host | every process in kms-core-2's pod (found by `HOSTNAME` in its environment) and in its network namespace, with start times and namespace inodes; the namespace's full TCP table; the owner of every socket on local port 50100; `ip_local_port_range` in that namespace | a second, older kms-server in the same namespace, owning a LISTEN on `:C3D4` | a LISTEN on `:C3D4` owned by a non-kms-server process in the namespace | no LISTEN on `:C3D4`, but a non-listening socket (01/06/04/05…) with local port 50100, typically to `minio:9000`, owned by the new kms-server or by nobody (TIME_WAIT) | a socket on `:C3D4` that no pod process owns and that isn't TIME_WAIT, or nothing on `:C3D4` at all | a LISTEN on `:C3D4` owned by the new kms-server (the pid that started at about 1108) |
| 2 | A, 1047.8629 (the previous kms-server, 0.8 s before it exits) | host | the previous kms-server's pid, start time, namespace inode, and its LISTEN on `:C3D4` | the same namespace inode as in probe 1, and that pid still alive in probe 1 | — | a different namespace from probe 1 (or the same one, with the old pid gone in probe 1) | — | — |
| 3 | A, 1106.8753 (gen-keys still running, kms-server not started yet) | host | the pod namespace's TCP table and the owners of `:C3D4` | (the old listener still present) | a listener on `:C3D4` | if probe 1's port-50100 socket is already there: owned by `kms-gen-keys` or `curl`, or in TIME_WAIT (an init container's connection). If it's absent: kms-server created it later | — | — |
| 4 | A, a moment between 1108.27 and 1122.8, chosen from probes 1 and 3 | host | when the port-50100 socket appears and who owns it | — | — | pins the process that created it, and when | — | — |
| 5 | A, 1122.8280 | `kms-core` (kms-core-2) | a cross-check from inside: `netstat -tan`, `/proc/net/tcp*`, `ip_local_port_range` | only if probe 1 could not read the namespace | | | | |

Probes 4 and 5 run only if probes 1–3 leave the question open. At most 10 probes, 5 min each.

## Results

<a id="timeline-a"></a>
### Timeline A: kms-core-2 in a boot crash loop under MinIO partitions

[Timeline A in the logs explorer][a], at the failing check.

**Probe 1** (1122.8280, host): the pod's processes, its network namespace's TCP table, and the
owner of local port 50100. Script: [`01-host-1122.83.sh`](boot-panic-port-in-use/01-host-1122.83.sh).
Raw output: [`01-host-1122.83.ndjson`](boot-panic-port-in-use/01-host-1122.83.ndjson) (empty) and
[`01-host-1122.83.err`](boot-panic-port-in-use/01-host-1122.83.err).

```text
$ snouty --json runs exec --timeout 5m 5a41ff4512a62b259c30d0cf245647d8-64-4 -- -6620762927361152219 1122.8279770489316 < 01-host-1122.83.sh
Error: API error: 400 Bad Request — This run is not currently active or reachable. Unable to execute command.

Note: `runs exec` needs a run that is in progress. This run is completed
```

The run completed at 23:25:59Z, and the probe ran about 2 h later. Its session is no longer
reachable, so the script never ran and there's no identity line to check. As instructed, probing
stopped here: no debugging session was opened and probes 2–5 were not attempted. The script is kept
so that it can be rerun as is on a live run.

**Log evidence instead.** The queries are in [`logs-queries.sh`](boot-panic-port-in-use/logs-queries.sh).

- **Every bind panic in the run** ([`logs-search-could-not-bind.ndjson`](boot-panic-port-in-use/logs-search-could-not-bind.ndjson),
  [`logs-search-panicked-at.ndjson`](boot-panic-port-in-use/logs-search-panicked-at.ndjson)). Both
  searches came back under the 999-event limit, so the counts are complete.

  ```text
  contains({output_text: "Could not bind"})  -> 2 events
    {'input_hash': '-6620762927361152219', 'vtime': 1122.873636372853} kms-core-2-core-2/kms-core rc=0
    {'input_hash': '3318742107607495774',  'vtime': 1123.2398594501428} kms-core-2-core-2/kms-core rc=0
  contains({output_text: "panicked at"})     -> 704 events: 702 kms-core-client (core-client/src/lib.rs:2872), 2 kms-server (the two above)
  ```

  Every instance is on kms-core-2, at the same point of one history. The property's 3 exit
  counterexamples come from those 2 panics on branches of it.

- **The previous instance's listener was closed before it exited.** In
  `kms-server.rs`, `service_listener` is a local of `main_exec`. It is passed to `run_server` only
  after `new_real_threshold_kms(...).await?` succeeds. The previous instance failed inside
  `new_real_threshold_kms`, after line 611: it logged "KMS verifying key is …" at 1035.675, then
  the FheKeyInfo error. So the listener was dropped, and its socket closed, when `main_exec`
  returned the error. Then `main` returned, Rust printed "Error: reading failed for FheKeyInfo …"
  at 1048.669, and the process exited 1. Any connections that listener had accepted inherit its
  `SO_REUSEADDR`, so they can't block a new `SO_REUSEADDR` bind.

<a id="timeline-b"></a>
### Timeline B: the sibling branch that diverged at 1107.42

[Timeline B in the logs explorer][b], at its bind panic. Log from 1040:
[iterate-3-bindpanic-branch-3318742107607495774.ndjson](../logs/iterate-3-bindpanic-branch-3318742107607495774.ndjson).

```text
first event in B that is not in A: {'input_hash': '2230730633985657441', 'vtime': 1107.419872002909} antithesis_test_composer received new input …
B gen-keys end 1107.124 (same as A) ; B kms-core start 1108.0525 rc=0 (same as A)
B faults after the split: 1107.72 clog Stopped, 1108.62 clog Stopped, 1109.25 clog Slowed, 1109.71 clog Stopped,
  1113.07 clog Jammed/Stopped [kms-core-2-core-2, minio, …], 1114.77 clog Jammed, 1120.42 clog Slowed
A faults after the split: 1107.45 clog Jammed, 1108.02/1108.48 restore, 1118.12 clog Stopped,
  1118.71 partition Slowed [ALL], 1120.80 clog Slowed [kms-core-2-core-2, minio, …], 1121.95 restore
B: … 1122.8629 s3.rs:111 Checking … PUB-p2/VerfAddress/60b7…  -> 1123.2399 "KMS Server service socket address: 0.0.0.0:50100"
   -> panicked at kms-server.rs:594:29 … Os { code: 98, kind: AddrInUse }
```

Timelines A and B share everything up to 1107.42: the crash loop, the init containers of the last
cycle (load-env 1049.00–1062.35, gen-keys 1063.01–1107.12) and their network faults. Everything
kms-server does happens after the split, under different faults (B never has A's Slowed partition
at 1118.71) and with different S3 timing. Both binds still fail, 0.37 s apart. The likeliest reading
is that whatever held port 50100 already existed at 1107.42, before kms-server started. That points
at a socket left in the pod's network namespace by an init container. **This is inferred.** The two
branches would also both fail if the kernel happened to give kms-server's own S3 connections the same
ports in both, which can't be ruled out without a probe.

## Verdict

| Explanation | Ruled out? | By |
|---|---|---|
| 1. (a) a leftover kms-server from the previous container | **yes** (from code and logs, not a probe) | The previous instance's `service_listener` was dropped when `main_exec` returned the FheKeyInfo error, before the "Error: …" line at 1048.67. The process then exited 1, and kubelet started the init containers again at 1049.00, which it does only after stopping the pod's containers. The listener's accepted connections carry `SO_REUSEADDR`, so they can't block a `SO_REUSEADDR` bind. The previous instance's TIME_WAITs (60 s from about 1048.7) would also have expired by 1108.7 |
| 2. (b) another container or process listening on 50100 | **yes** (from the manifest; not observed) | The only other containers are the two init containers (`sh`+`curl`+`envsubst`, and `kms-gen-keys`). They run to completion before `kms-core` starts and listen on nothing. There is no sidecar and no `hostNetwork` |
| 3. (c) a non-listening socket with local port 50100 (an ephemeral-port collision) | **no: the leading explanation** | It fits everything seen. 50100 is in the default ephemeral range, and no sysctl in the manifests changes it. About 91 outgoing operations to `minio:9000` ran from this namespace in the 75 s before the bind, many of them under partitions that force reconnections. Timeline B shows the cause probably existed by 1107.42, while only the init containers had run in this cycle. Not observed: no probe could run |
| 4. (d) the platform doing something to the pod's network namespace | not tested | Nothing in the logs points to it. One unexplained platform behaviour: kubelet re-runs the init containers after every `kms-core` exit (a new sandbox each time), which the harness comment in the manifest says shouldn't happen |
| 5. (e) kms-server binding 50100 twice | **yes** (from code) | Before line 592 the only bind is the metrics listener on `0.0.0.0:9646`. The MPC listener on 50001 is bound later. In this history the same code bound 50100 without error on six earlier boots of kms-core-2 |

- **Observed:**
  - Two bind panics in the whole run, both on kms-core-2 and both in the same history, at 1122.87
    and 1123.24. That history split at 1107.42, between the end of `kms-core-init-gen-keys` and the
    start of `kms-core`.
  - The fault schedules after the split differ, and both binds fail with AddrInUse.
  - In the 75 s before the bind, the pod made about 8 `curl` calls, 40 gen-keys S3 operations and
    43 kms-server S3 operations to `minio:9000`.
  - The init containers re-run after every exit.
  - `runs exec` refused the completed run, so no socket was ever seen.
- **Inferred:**
  - The previous listener was closed before its process exited (from the code path).
  - A new sandbox, and so a new network namespace, comes with each restart (from kubelet
    behaviour).
  - Port 50100 was held by a client socket in the pod's namespace, ESTABLISHED or in
    TIME_WAIT/FIN_WAIT. Most likely it came from `kms-gen-keys` (1063–1107), less likely from
    kms-server's own S3 client. This rests on the split at 1107.42 and on Linux's bind-conflict rule,
    which refuses a wildcard bind while a socket without `SO_REUSEADDR` holds the port, even when the
    new socket sets `SO_REUSEADDR` (`inet_csk_bind_conflict`; not checked on this kernel).
- **Classification: still suspect.** The leading explanation is an ephemeral-port collision. The
  chart's service port lies inside the kernel's ephemeral range. kms-server binds it only after it,
  and the pod's init containers, have opened dozens of outgoing connections. Network faults add
  more reconnections. If that is confirmed, it isn't a harness bug, and no guarantee is breached:
  it's deployment hygiene in Zama's chart, plus a server that panics on bind instead of retrying.
  That would make it a lead, not a finding.
- **Action:** leave it to the report as suspect, and don't report it as a violation. Add the
  signature "Could not bind to 0.0.0.0:50100" to the live stream's known signatures. The next time
  it fires in a live run, rerun [`01-host-1122.83.sh`](boot-panic-port-in-use/01-host-1122.83.sh)
  at the moment just before the bind, and probe 3's moment, to see the socket and its owner.
  Optional configuration experiment, which doesn't change how the system behaves: set
  `net.ipv4.ip_local_reserved_ports=9646,50001,50100` in the core pods' `securityContext.sysctls`.
  It's a namespaced sysctl on Kubernetes' safe list since 1.27, and it takes the service ports out
  of the ephemeral range. It is rare (one history in a 30-minute run), so its absence in one run
  would prove little.

[a]: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEyMy4zMjM4NDI5NjU3NjUifV0sIm8iOiJvciJ9LHsiaCI6W3siYyI6Im1vbWVudC5pbnB1dF9oYXNoIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiLTczMjE1OTU4ODQwOTU1NjIyOTkifV0sIm8iOiJvciJ9XSwibyI6ImFuZCJ9LCJ0Ijp7ImciOmZhbHNlLCJtIjoiIn0sInkiOiJub25lIn19LCJzIjoiOGU1M2QyZjU4MjViNDNhN2FmZjZlMzY0NmVlN2RmMGQtNjQtNCJ9
[b]: https://zama.antithesis.com/search?search=v6veyJxIjp7Im4iOnsiciI6eyJoIjpbeyJoIjpbeyJjIjoibW9tZW50LnZ0aW1lIiwiZiI6ImdlbmVyYWwuY3VzdG9tIiwibyI6Im1hdGNoZXMiLCJ2IjoiMTEyMy4yMzk4NTk0NDk5MSJ9XSwibyI6Im9yIn0seyJoIjpbeyJjIjoibW9tZW50LmlucHV0X2hhc2giLCJmIjoiZ2VuZXJhbC5jdXN0b20iLCJvIjoibWF0Y2hlcyIsInYiOiIzMzE4NzQyMTA3NjA3NDk1Nzc0In1dLCJvIjoib3IifV0sIm8iOiJhbmQifSwidCI6eyJnIjpmYWxzZSwibSI6IiJ9LCJ5Ijoibm9uZSJ9fSwicyI6IjhlNTNkMmY1ODI1YjQzYTdhZmY2ZTM2NDZlZTdkZjBkLTY0LTQifQ
[report]: https://zama.antithesis.com/report/osAjr9BLYLHEbb3IXrirMKfU/qdH-RmNnyHthMKXV3T627ycFlSEFwwyqREKpQLF2ubI.html?auth=v2.public.eyJuYmYiOiIyMDI2LTEwLTE3VDIyOjI1OjU5LjI2NDI5NTMxN1oiLCJzY29wZSI6eyJSZXBvcnRTY29wZVYxIjp7ImFzc2V0IjoicWRILVJtTm55SHRoTUtYVjNUNjI3eWNGbFNFRnd3eXFSRUtwUUxGMnViSS5odG1sIiwicmVwb3J0X2lkIjoib3NBanI5QkxZTEhFYmIzSVhyaXJNS2ZVIn19fQfTp_Ex_1v8uV3QyajJ48Jw4HdyV1V3iprMM6sstjw5ZFUtGkmL2zv2RRGsRUfBLF_DjYhQu6Kd2hTVvfZU1wU
