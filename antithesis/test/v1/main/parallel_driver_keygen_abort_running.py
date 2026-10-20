#!/usr/bin/env python3
"""Short sequence for keygen.abort: start an insecure keygen in the background, then send
AbortKeyGen with its preprocessing ID while it runs, to every core or to one; compressed, or
uncompressed (-u) 1 time in 4. An abort on its own rarely meets a running keygen (the DKG
takes ~0.3 s, and the drivers stop making keys at MAX_KEYS), so this targets the cancel
path: inner_abort_key_gen finding the keygen and key_gen_background recording "Key generation
was aborted". The delay spans the CLI's connect plus the DKG and the key writes.

It has its own budget, since the keygen driver fills MAX_KEYS within a minute: at most
MAX_RUNS keygens per container (abort-runs/), and none once MAX_KEYS + 6 keys exist, because
an abort that comes too late, or reaches only some cores, leaves a key on some or all of
them. Nothing here runs while a reshare does (helper_common.lifecycle)."""
import sys

from helper_common import (MAX_KEYS, chance, cli_outcome, enter_scratch_dir, key_count, lifecycle, log_outcome,
                           pick, pool, record, request_id_from, sleep, start_cli, take, wait_cli)
from helper_grpc import call_with_request_id, core_addresses

MAX_RUNS = 12

with lifecycle("generate", wait=120) as held:
    room = held and len(pool("abort-runs")) < MAX_RUNS and key_count() < MAX_KEYS + 6
    preproc_id = take("preproc") if room else None
    if preproc_id is None:
        log_outcome("keygen.abort", "skipped=no_preproc_or_budget_or_epoch_change")
        sys.exit(0)
    record("abort-runs", preproc_id)
    enter_scratch_dir()
    try:
        keygen = start_cli(["--max-iter", 600, "insecure-key-gen", "--preproc-id", preproc_id]
                           + (["-u"] if chance(25) else []))
    except OSError as e:
        log_outcome("keygen.start_insecure", f"error=exit126 ({e})")
        sys.exit(0)
    sleep(pick([0.2, 0.3, 0.4, 0.5, 0.6, 0.8, 1, 1.5]))
    cores = core_addresses()
    for _, address in cores if chance(70) else [pick(cores)]:
        log_outcome("keygen.abort", call_with_request_id(address, "AbortKeyGen", preproc_id, timeout=30))
    rc, out = wait_cli(keygen, timeout=600)
    log_outcome("keygen.start_insecure", cli_outcome(rc, out))
    if rc == 0 and request_id_from(out):
        record("keys", request_id_from(out), preproc_id)
