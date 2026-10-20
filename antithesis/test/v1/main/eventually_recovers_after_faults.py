#!/usr/bin/env python3
"""Checks that once faults stop, every core accepts connections again and the cluster then
serves a public decryption that all four cores answer (Guarantee 2).

Faults. Antithesis stops all faults when an eventually_ command starts and runs nothing
alongside it. This command also opens a quiet window with $ANTITHESIS_STOP_FAULTS covering
its whole check, so the check holds even if the pod-fault injector didn't follow the
eventually phase. A pod deleted just before faults stopped is recreated by its StatefulSet.

Probe. kms-core-client -a public-decrypt with the four-core config: a fresh value under the
workload's key and the kms-init epoch, async or --sync. -a waits for all four cores and checks
each response, so a success means every core took part. Attempts are bounded by 90 s (and the
time left) and are 10 s apart; each is a new request with a new random ID.

Windows. The CLI logs (-l) when it has connected to every core: the client's view of "every
core accepts connections". That must happen within 600 s of this command's start (Kubernetes'
300 s restart back-off cap plus boot and readiness). From the start of the first attempt that
got that far, a probe must succeed within 300 s (the MPC network_timeout). Durations use
seconds since boot, which clock faults don't move.

Checks: the two Guarantee 2 Always and two Sometimes in helper_properties, and Guarantee 1's
plaintext checks on every attempt (judge_public_decrypt without its coverage markers).
"""
import os
import subprocess
import sys

from helper_common import (cli_connected, cli_unreached_party, decrypt_args, enter_scratch_dir, now_s,
                           pick, pick_decrypt_inputs, probe_key, request_id_from, run_cli, sleep,
                           write_client_config)
from helper_properties import (MSG_RECOVERY_CONNECT, MSG_RECOVERY_DECRYPT, MSG_RECOVERY_REJOINED,
                               MSG_RECOVERY_RETRIED, always, declare_catalog, judge_public_decrypt,
                               sometimes, tail)

CONNECT_BOUND, DECRYPT_BOUND, ATTEMPT_LIMIT, PAUSE = 600, 300, 90, 10

declare_catalog()
if os.environ.get("ANTITHESIS_STOP_FAULTS"):
    seconds = CONNECT_BOUND + DECRYPT_BOUND + ATTEMPT_LIMIT + 30
    try:
        stopped = subprocess.run([os.environ["ANTITHESIS_STOP_FAULTS"], str(seconds)]).returncode == 0
    except OSError:
        stopped = False
    if not stopped:
        print("ANTITHESIS_STOP_FAULTS failed; relying on the eventually phase", flush=True)
start = now_s()

# The key: one that all four cores hold (probe_key), preferring first_generate_key.py's.
# MinIO is never pod-faulted, but give its network a moment to settle.
key_id = None
for _ in range(6):
    key_id = probe_key()
    if key_id:
        break
    sleep(PAUSE)
if key_id is None:
    print("no FHE key found; nothing to probe", flush=True)
    sys.exit(0)

enter_scratch_dir()
write_client_config()
attempt = failed = 0
ok = wrong = refused_before_connect = False
connected_at = unreached = None
last = {"exit_code": None}
while True:
    t = now_s()
    left = (start + CONNECT_BOUND if connected_at is None else connected_at + DECRYPT_BOUND) - t
    if left <= 0:
        break
    attempt += 1
    inputs = pick_decrypt_inputs()
    inputs.update(batch=pick([1, 1, 2]), no_compression=False, no_precompute_sns=False)
    sync = pick([False, True])
    args = decrypt_args("public-decrypt", key_id, inputs, all_parties=True, max_iter=60, sync=sync)
    rc, out = run_cli(args, timeout=min(ATTEMPT_LIMIT, left))
    connected = cli_connected(out)
    if connected and connected_at is None:
        connected_at = t
    last = dict(inputs, attempt=attempt, started_after_s=t - start, sync=sync, key_id=key_id,
                connected=connected, exit_code=rc, command="eventually_recovers_after_faults.py")
    verdict = judge_public_decrypt(rc, out, last, markers=False)
    if verdict == "ok":
        ok = True
        break
    if verdict == "args":
        sys.exit(1)
    wrong = wrong or verdict == "wrong"
    failed += 1
    last["error"] = tail(out)
    if not connected and cli_unreached_party(out):
        unreached = cli_unreached_party(out)
        refused_before_connect = refused_before_connect or connected_at is None
        print(f"could not connect to party {unreached}", flush=True)
    sleep(PAUSE)

now = now_s()
summary = {"attempts": attempt, "failed_attempts": failed, "elapsed_s": now - start,
           "last_unreached_party": unreached, "last_attempt": last}
if connected_at is None:
    always(MSG_RECOVERY_CONNECT, False, dict(summary, connect_bound_s=CONNECT_BOUND))
else:
    always(MSG_RECOVERY_CONNECT, True, dict(summary, connect_wait_s=connected_at - start))
    always(MSG_RECOVERY_DECRYPT, ok, dict(summary, connect_wait_s=connected_at - start,
                                          decrypt_wait_s=now - connected_at, decrypt_bound_s=DECRYPT_BOUND))
# Hard cases this run met, judged by whether it got through them.
if refused_before_connect:
    sometimes(MSG_RECOVERY_REJOINED, connected_at is not None, summary)
if failed > 0:
    sometimes(MSG_RECOVERY_RETRIED, ok, summary)
print(f"recovery: connected_at={connected_at}, ok={ok} after {attempt} attempt(s)", flush=True)
sys.exit(0 if ok and not wrong else 1)
