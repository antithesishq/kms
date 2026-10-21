"""The decryption drivers' loop: 1–3 kms-core-client runs with fresh inputs, each judged by
helper_properties. A decryption's async driver and its sync driver differ only in --sync,
so they share it. Each call decrypts under the kms-init epoch or, once the reshare driver
has made some, under a reshared epoch (pick_epoch), so the plaintext checks cover reshared
key shares too. Not a command; Test Composer skips helper_ files.
"""
import sys

from helper_common import (DEFAULT_EPOCH_ID, chance, cli_connected, cli_outcome, cli_unreached_party,
                           decrypt_args, enter_scratch_dir, epoch_in_use, log_outcome, pick, pick_count,
                           pick_decrypt_inputs, pick_epoch, pick_key, record, request_id_from, run_cli, sleep,
                           timeline_choice, write_client_config)
from helper_properties import declare_catalog, judge_public_decrypt, judge_user_decrypt


def public_decrypts(op, sync):
    """Public decryptions of fresh values. kms-core-client sends PublicDecrypt and polls
    GetPublicDecryptionResult, or with sync sends PublicDecryptSync, then checks signatures,
    agreement and the plaintext, which judge_public_decrypt turns into Guarantee 1's
    assertions. Four cores, or three with one left out (num_parties = 4) so it can decrypt
    while a core is down; -a only with four. A call that couldn't connect makes the next one
    leave that core out."""
    declare_catalog()
    key_id = pick_key()
    if key_id is None:
        log_outcome(op, "skipped=no_key")
        sys.exit(0)
    enter_scratch_dir()
    left_out = pick([1, 2, 3, 4]) if chance(timeline_choice("three_core_pct", [0, 25, 50, 90])) else None
    all_parties_pct = timeline_choice("all_parties_pct", [0, 33, 90])
    after_failed_call = failing_over = False
    for call in range(1, pick_count(1, 3) + 1):
        write_client_config(left_out)
        all_parties = left_out is None and chance(all_parties_pct)
        inputs = pick_decrypt_inputs()
        epoch_id, epoch_status = pick_epoch(key_id)
        with epoch_in_use(epoch_id) as usable:
            if not usable:
                epoch_id, epoch_status = DEFAULT_EPOCH_ID, "default"
            rc, out = run_cli(decrypt_args("public-decrypt", key_id, inputs, all_parties, sync=sync,
                                           epoch_id=epoch_id), timeout=300)
        log_outcome(op, cli_outcome(rc, out))
        details = dict(inputs, key_id=key_id, epoch_id=epoch_id, epoch_status=epoch_status, all_parties=all_parties,
                       left_out=left_out, sync=sync, call=call, after_failed_call=after_failed_call,
                       failing_over=failing_over, exit_code=rc)
        verdict = judge_public_decrypt(rc, out, details)
        if verdict in ("wrong", "args"):
            sys.exit(1)
        if verdict == "ok" and request_id_from(out):
            record("pubdec", request_id_from(out))
        after_failed_call, failing_over = verdict != "ok", False
        if after_failed_call and not cli_connected(out) and cli_unreached_party(out):
            left_out, failing_over = cli_unreached_party(out), True
            print(f"could not connect to party {left_out}; the next call leaves it out", flush=True)
        if after_failed_call:
            sleep(10)


def user_decrypts(op, sync):
    """User decryptions of fresh values. kms-core-client sends UserDecrypt with a fresh
    ML-KEM key and polls GetUserDecryptionResult, or with sync sends UserDecryptSync, then
    authenticates the shares, reconstructs and compares, which judge_user_decrypt turns into
    Guarantee 4's assertions. Always the four-core config: the client derives the threshold
    from the configured cores, so with three it would reject the cores' degree-1 shares."""
    declare_catalog()
    key_id = pick_key()
    if key_id is None:
        log_outcome(op, "skipped=no_key")
        sys.exit(0)
    enter_scratch_dir()
    write_client_config()
    all_parties_pct = timeline_choice("user_all_parties_pct", [0, 33, 90])
    after_failed_call = False
    for call in range(1, pick_count(1, 3) + 1):
        all_parties = chance(all_parties_pct)
        inputs = pick_decrypt_inputs()
        epoch_id, epoch_status = pick_epoch(key_id)
        with epoch_in_use(epoch_id) as usable:
            if not usable:
                epoch_id, epoch_status = DEFAULT_EPOCH_ID, "default"
            rc, out = run_cli(decrypt_args("user-decrypt", key_id, inputs, all_parties, sync=sync,
                                           epoch_id=epoch_id), timeout=300)
        log_outcome(op, cli_outcome(rc, out))
        details = dict(inputs, key_id=key_id, epoch_id=epoch_id, epoch_status=epoch_status, all_parties=all_parties,
                       sync=sync, call=call, after_failed_call=after_failed_call, exit_code=rc)
        verdict = judge_user_decrypt(rc, out, details)
        if verdict in ("wrong", "args"):
            sys.exit(1)
        if verdict == "ok" and request_id_from(out):
            record("userdec", request_id_from(out))
        after_failed_call = verdict != "ok"
        if after_failed_call:
            sleep(10)
