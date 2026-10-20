#!/usr/bin/env python3
"""Run Antithesis test commands locally, roughly the way Test Composer does.

Runs inside the container that holds the test templates. Picks one `first_`
command, then for --duration seconds keeps up to --concurrency drivers running:
  parallel_driver_   started whenever a slot is free
  serial_driver_     waits for all running drivers to finish, then runs alone
  singleton_driver_  runs once, alone
  anytime_           started now and then alongside other drivers
`eventually_` and `finally_` commands are skipped. There is no fault injection.

The seed fixes which commands run and when. Values chosen inside drivers still
vary between runs, because the Antithesis SDK falls back to normal randomness
outside Antithesis.

Command output goes to this process's stdout. A summary of how many times each
command ran, and how many times it exited non-zero, is printed at the end.
"""

import argparse
import os
import random
import subprocess
import sys
import time
from collections import Counter

PREFIXES = ("first_", "parallel_driver_", "serial_driver_", "singleton_driver_",
            "anytime_", "eventually_", "finally_")


def find_commands(template_dir):
    cmds = {}
    for name in sorted(os.listdir(template_dir)):
        path = os.path.join(template_dir, name)
        if name.startswith("helper_") or not os.access(path, os.X_OK) or os.path.isdir(path):
            continue
        for prefix in PREFIXES:
            if name.startswith(prefix):
                cmds.setdefault(prefix, []).append(path)
    return cmds


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default="/opt/antithesis/test/v1")
    ap.add_argument("--template", help="template folder name (default: pick one at random)")
    ap.add_argument("--duration", type=float, default=300, help="seconds of driver activity")
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--command-timeout", type=float, default=120)
    a = ap.parse_args()

    rng = random.Random(a.seed)
    templates = sorted(t for t in os.listdir(a.root) if os.path.isdir(os.path.join(a.root, t)))
    if not templates:
        sys.exit(f"no test templates in {a.root}")
    template = a.template or rng.choice(templates)
    cmds = find_commands(os.path.join(a.root, template))
    drivers = cmds.get("parallel_driver_", []) + cmds.get("serial_driver_", [])
    singletons = list(cmds.get("singleton_driver_", []))
    if not drivers and not singletons:
        sys.exit(f"no driver commands in template {template}")
    print(f"[local_composer] template={template} seed={a.seed} duration={a.duration}s "
          f"concurrency={a.concurrency}", flush=True)

    runs, failures = Counter(), Counter()
    running = {}  # Popen -> (path, start time)

    def start(path):
        runs[os.path.basename(path)] += 1
        running[subprocess.Popen([path])] = (path, time.time())

    def reap(block=False):
        while running:
            for p, (path, started) in list(running.items()):
                if p.poll() is None and time.time() - started > a.command_timeout:
                    p.kill()
                if p.poll() is not None:
                    if p.returncode != 0:
                        failures[os.path.basename(path)] += 1
                    del running[p]
            if not block:
                return
            time.sleep(0.05)

    if cmds.get("first_"):
        start(rng.choice(cmds["first_"]))
        reap(block=True)

    end = time.time() + a.duration
    while time.time() < end:
        reap()
        if singletons and rng.random() < 0.05:
            reap(block=True)
            start(singletons.pop(rng.randrange(len(singletons))))
            reap(block=True)
            continue
        if cmds.get("anytime_") and rng.random() < 0.02:
            start(rng.choice(cmds["anytime_"]))
        if drivers and len(running) < a.concurrency:
            path = rng.choice(drivers)
            if os.path.basename(path).startswith("serial_driver_"):
                reap(block=True)
                start(path)
                reap(block=True)
            else:
                start(path)
        time.sleep(0.05)

    for p in running:
        p.terminate()
    reap(block=True)

    print("\n[local_composer] command        runs  non-zero exits", flush=True)
    for name, n in sorted(runs.items()):
        print(f"[local_composer] {name:40} {n:5}  {failures[name]}", flush=True)


if __name__ == "__main__":
    main()
