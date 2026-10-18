# Advanced Kubernetes test (`advanced_k8s_test`)

Runs your Kubernetes deployment under Antithesis while injecting faults — network
disruption, pod deletion, clock skew, CPU pressure, thread pausing — and reports what broke.

Everything is configured through launch parameters. You supply your images and a
`manifests/` directory in your config image; nothing else is required. The defaults are a
sensible general-purpose run, so **you can launch with no parameters at all** and tune
from there.

Standard `antithesis.*` parameters behave as usual. `antithesis.duration` is clamped to
between 15 minutes and 40 hours.

## Launching

The notebook is called `advanced_k8s_test`; that is the webhook name you launch. Point
`--config` at a directory containing a `manifests/` subdirectory, with your images
already built locally:

```sh
snouty validate ./config
snouty launch --webhook advanced_k8s_test --config ./config --duration 60
```

For Kubernetes, `snouty validate` checks your manifests statically; it does not deploy
them. snouty builds `./config` into a config image and pushes it along with your images.
If you already publish a config image, pass `--config-image <image-ref>` instead.
`--duration` is `antithesis.duration`, in minutes.

Set any parameter below with `--param`:

```sh
snouty launch --webhook advanced_k8s_test --config ./config --duration 60 \
  --param custom.enabled_faults=network,pod_kill,clock_jitter \
  --param custom.container_faults_stop_exclusion_patterns=load-generator \
  --param custom.container_faults_kill_exclusion_patterns=load-generator
```

Images referenced only inside a CRD field are invisible to snouty; list them with
`--param 'antithesis.images=app@sha256:...;db:latest'`.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `custom.enabled_faults` | `network,pod_stop,pod_kill,clock_jitter` | Which kinds of faults to run. Empty means **thread pausing only** (see below). |
| `custom.pause_fault_injector` | `false` | Switch the fault injector off for the whole run: no faults at all, **thread pausing included**. Overrides `custom.enabled_faults`. |
| `custom.network_fault_exclusion_patterns` | _empty_ | **Regex** patterns for pods to spare from network faults. |
| `custom.container_faults_stop_exclusion_patterns` | _empty_ | **Regex** patterns for pods to spare from stop (graceful delete) faults. |
| `custom.container_faults_kill_exclusion_patterns` | _empty_ | **Regex** patterns for pods to spare from kill (immediate delete) faults. |
| `custom.pod_fault_interval_seconds` | `300` | Median seconds between pod fault attempts, separately for stop and for kill. |
| `custom.strobe_quiet_max_seconds` | `0` | Longest quiet window. **`0` turns strobing off.** |
| `custom.strobe_quiet_min_seconds` | `20` | Shortest quiet window. |
| `custom.strobe_chaos_seconds` | `60` | Median seconds of faults between quiet windows. |
| `custom.manifests_path` | `/opt/config/manifests` | Path to your manifests directory inside the config image. |
| `custom.vm_memory_mb` | `0` | Memory for the test VM, in MiB. `0` uses the platform default. |
| `custom.post_setup_settle_seconds` | `100` | Seconds to let your cluster settle before faults start. |
| `custom.smoke_test_seconds` | `100` | Seconds to run fault-free first, as a sanity check. `0` skips it. |
| `custom.timing_fuzzing` | `false` | Also fuzz the platform's virtual-time scheduling. See below. |
| `custom.callback.run_start.url` | _empty_ | URL to POST to when faults are about to start. Empty sends nothing. See [Run callbacks](#run-callbacks). |
| `custom.callback.run_start.token` | _empty_ | Optional bearer token for the run-start callback. |
| `custom.callback.run_end.url` | _empty_ | URL to POST to when testing has finished. Empty sends nothing. |
| `custom.callback.run_end.token` | _empty_ | Optional bearer token for the run-end callback. |

## Choosing which faults run

`custom.enabled_faults` takes a comma-separated list. Unrecognised names are ignored with
a warning in the report.

| Value | What it does |
|---|---|
| `network` | Latency, packet loss, degraded links, network partitions, and flaky nodes. |
| `pod_stop` | Deletes pods gracefully (SIGTERM, then the pod's termination grace period). |
| `pod_kill` | Deletes pods immediately (`--grace-period=0`). |
| `clock_jitter` | Moves the system clock forwards and backwards. |
| `cpu_pressure` | Starves pods of CPU. |

`cpu_pressure` is off by default. It interacts badly with software that enforces its own
timeouts, so turn it on deliberately once you know your system tolerates it.

**Leaving this empty runs thread pausing only.** Thread pausing is not a value in this list:
it runs whenever the fault injector runs (see [Thread pausing](#thread-pausing)), so an empty
list gives you a run where thread scheduling is the only thing being perturbed — useful for
hunting races with no infrastructure faults in the way.

**For a genuine no-fault run, also set `custom.pause_fault_injector` to `true`.** That
switches the fault injector off for the whole run, thread pausing included — useful as a
baseline to confirm your deployment is healthy before you trust any fault findings. It takes
precedence over `custom.enabled_faults`: anything still listed there is ignored, and your
report warns you, since a paused injector could never run it.

### Network `FAULT` events appear even when network faults are off

Disabling `network` (or excluding a pod from network faults) does not stop the platform
from *generating* network fault events: the run's event log still shows
`FAULT network/partition` and `FAULT network/clog` lines throughout. These events are
inert for protected pods — the exclusion is enforced on every individual packet, so
traffic to or from an excluded pod is delivered untouched regardless of what the event
log says.

Two things make the raw lines misleading: partition events always report
`affected_nodes: ALL`, even when every pod is excluded and the partition touched nothing,
and clog events still appear when all of their targets are excluded (with an empty
`affected_nodes` list). Judge what actually ran from the **Fault Configuration** section
of your report, not from `FAULT` lines in the event log.

**A graceful stop takes as long as your process ignores SIGTERM.** `pod_stop` sends
SIGTERM and waits out the pod's termination grace period (30s unless you set
`terminationGracePeriodSeconds`) before killing it. A process running as PID 1 with no
SIGTERM handler ignores the signal entirely, so every stop takes the full grace period.
Handle SIGTERM, or run under an init such as `tini`, if you want stops to behave like
real shutdowns.

**Deleted pods only come back if something reschedules them.** Stop and kill faults
delete the pod and leave recovery to your controllers — a pod managed by a Deployment or
StatefulSet is rescheduled, but a bare pod with no controller stays gone for the rest of
the run. If your manifests contain bare pods, either put them under a controller or add
them to both exclusion lists.

## Protecting specific pods

All three exclusion lists take **regex patterns matched against pod names**, unanchored —
`echo-server` matches `echo-server-0` and `echo-server-7d9fb56c9-xk2vp`. An empty list
excludes nothing.

Deployment pods carry generated hash suffixes that change every reschedule, so write
patterns against the stable prefix rather than a full name. **Run once and read the
Cluster Status section of your report** — it lists the real pod names — before relying on
an exclusion list.

You never need to protect `kube-system`: its pods (including cluster DNS) are never
targeted by network or pod faults, regardless of what you set here.

All lists are **empty by default** — every pod outside `kube-system` is eligible. That is
deliberate: faulting the client side is often where the interesting bugs are. The usual
reason to add an exclusion is a load generator or test driver, where deleting it
mid-command produces findings about the harness rather than about your system.

Stop and kill are separate lists so you can spare a pod's graceful-shutdown path while
still testing crashes, or vice versa.

### Summary

| To protect a pod from | Set | Syntax |
|---|---|---|
| network faults | `network_fault_exclusion_patterns` | regex on pod name |
| graceful deletion | `container_faults_stop_exclusion_patterns` | regex on pod name |
| immediate deletion | `container_faults_kill_exclusion_patterns` | regex on pod name |
| thread pausing | `ANT_ENABLE_PAUSE_INJECTION=0` in the pod spec's `env:` | n/a (see [Thread pausing](#thread-pausing)) |

These do not overlap. Sparing a pod from network faults does not stop it being deleted,
and sparing it from deletion does not stop it being CPU-throttled.

## Tuning how hard faults hit

`custom.pod_fault_interval_seconds` applies **separately** to stop and to kill — with
both enabled, the total pod fault rate is roughly twice `1 / interval`. Each attempt
picks one running pod at random from the eligible set. It's a median, and faults are
randomised each round, so the observed rate runs somewhat below that.

How long a deleted pod stays down is not a parameter — it's your cluster's rescheduling
and startup time, which is exactly what these faults measure.

`custom.post_setup_settle_seconds` is how long your deployment gets after `kapp deploy`
returns before anything is captured or broken. Raise it if your operators need time to
reconcile, elect leaders, or finish migrations.

## Alternating chaos and quiet

Off by default. Set `custom.strobe_quiet_max_seconds` above `0` to turn it on.

Strobing alternates periods of faults with periods of calm. This is very effective at
finding **recovery** bugs — stuck retry loops, deadlocks that only clear under load, state
that never re-converges — because your system is still being exercised during the quiet
window, so anything that fails to recover shows up there rather than being buried under
fresh faults.

- `custom.strobe_chaos_seconds` — roughly how long faults run before each quiet window.
- `custom.strobe_quiet_min_seconds` / `_max_seconds` — each quiet window is a random
  length between these two.

Entering a quiet window clears faults already in flight and restores the network, so it's
a genuine calm rather than just "stop adding new problems". Quiet windows end on their
own; you don't need to do anything. (A pod deleted just before the window opened may
still be mid-reschedule as it begins — give your liveness checks a short grace period. A
graceful stop that started just before the window can even land inside it, up to the
pod's termination grace period later; see the SIGTERM note above.)

**Windows never overlap or stack**, whatever you set the two durations to. While faults
are stopped no new fault can be triggered — including another strobe — so the cycle is
strictly chaos → quiet → chaos. A long quiet window can't run into the next one, and
`custom.strobe_chaos_seconds` is effectively measured over the fault-active periods only.

Both timings are approximate — faults are randomised each round, so treat them as averages
rather than a schedule.

Strobing is ignored when `custom.pause_fault_injector` is set, and your report says so. A
thread-pausing-only run strobes normally.

## Quiet windows from your workload

Your workload can open its own quiet window by running `$ANTITHESIS_STOP_FAULTS <seconds>`.
Faults stop for that many seconds and then resume on their own.

## Thread pausing

Thread pausing perturbs thread scheduling inside instrumented containers. It is **not a
value of `custom.enabled_faults`**: it runs whenever the fault injector runs, and the
platform randomises how often it is switched on and off throughout a run, so it cannot be
held on or off independently of the other faults. Your report's Fault Configuration
section has a Thread pausing entry saying whether it ran.

You can still get it on its own, or get rid of it:

- **Thread pausing only:** leave `custom.enabled_faults` empty.
- **No thread pausing at all:** set `custom.pause_fault_injector` to `true`. This pauses the
  fault injector, so every other fault is off too.
- **Exempt one container:** see below.

To switch it off for a workload, set `ANT_ENABLE_PAUSE_INJECTION=0` in the pod spec's
`env:`. The instrumentation reads it once at process start, so a process launched with it
set is never paused. This is per container, so containers sharing an image can be treated
differently.

## Timing fuzzing

Off by default. Set `custom.timing_fuzzing` to `true` to have exploration also perturb
the platform's own virtual-time scheduling, so your system is exercised under many
different timing regimes rather than one. This is good at surfacing bugs that depend on
thread and message interleavings — races that a single timing regime would rarely hit.

It applies to the exploration phase only; startup and the fault-free smoke test run
under normal timing. It combines freely with every other parameter.

## Run callbacks

Off by default. The run can notify your own HTTP endpoint twice:

| Event | Sent when | Parameters |
|---|---|---|
| `run_start` | Your deployment is up, has settled, and testing is about to begin. | `custom.callback.run_start.url`, `custom.callback.run_start.token` |
| `run_end` | Testing has finished and the report is about to be generated. | `custom.callback.run_end.url`, `custom.callback.run_end.token` |

Each is a `POST` with a JSON body:

```json
{"event": "run_start", "run_id": "...", "title": "..."}
```

If you set a token, it is sent as `Authorization: Bearer <token>`. The token is optional,
but setting a token without its URL is an error, as is a URL that doesn't start with
`http://` or `https://`. Either mistake fails the launch straight away, so a callback is
never silently dropped.

```sh
snouty launch --webhook advanced_k8s_test --config ./config --duration 60 \
  --param custom.callback.run_end.url=https://ci.example.com/antithesis \
  --param custom.callback.run_end.token=$CI_TOKEN
```

Things to know:

- **Callbacks are delivered at least once.** Failed deliveries are retried, so the same
  event can occasionally arrive twice. Use `run_id` plus `event` to ignore duplicates.
- **They are not a substitute for the built-in integrations.** Neither callback is sent if
  your deployment fails to start, and `run_end` is not sent if the run times out or stops
  with an error. `run_end` also carries no report link and no pass/fail result. For those,
  use the built-in Slack, Discord or GitHub integrations.
- **Treat the token as visible to anyone who can see the run's launch parameters.** It is
  kept out of your report, but it is stored with the run's parameters like any other value
  you pass.

## Reading your report

Your report includes:

- **Fault Configuration** — exactly which faults ran and which pods were spared. This is
  generated from the settings that were actually applied, so trust it over your
  parameters if they ever seem to disagree — and over raw `FAULT network/*` lines in the
  event log, which appear even in runs with network faults disabled (see
  [above](#network-fault-events-appear-even-when-network-faults-are-off)).
- **Cluster Status** — your services and pods shortly after startup, with their real
  names. Use this to build exclusion lists.
- **Manifests** — the manifests the run actually deployed, downloadable as an archive.
- **Smoke Test Logs** — the fault-free period, if you kept it enabled.

If a run finds nothing, the usual first checks are whether your exclusion lists are wider
than you intended, and whether `custom.pod_fault_interval_seconds` is short enough that
faults actually landed during the run.
