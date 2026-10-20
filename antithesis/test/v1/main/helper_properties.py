"""The property catalog's assertions (antithesis/scratchbook/property-catalog.md), and the
classification of kms-core-client runs that they are evaluated on.

Assertions go through the SDK's assert_raw, so that each one carries the same message, ID and
location as in the shell harness this workload replaces, and so that the catalog below is
declared up front: a must-hit assertion that is never reached still shows up as failing.

Only the assertions that the active operations can reach are declared: a declared must-hit
assertion that can't be reached fails the run. All of the catalog's are active now.
decrypt-request-id-retries (Guarantee 5) is not implemented, as in the catalog.

Every evaluation carries {"guarantee": ..., "property": ...} in its details, and every
message is listed in antithesis/scratchbook/assertion-map.json.
"""
import os
import re

from helper_common import DEFAULT_EPOCH_ID, STATE_DIR, TEMPLATE_DIR, request_id_from

from antithesis.assertions import assert_raw

G1 = ("guarantee-1", "public-decrypt-returns-encrypted-plaintext")
G2 = ("guarantee-2", "recovers-after-faults")
G3 = ("guarantee-3", "reshare-preserves-key")
G4 = ("guarantee-4", "user-decrypt-returns-encrypted-plaintext")
NONE = (None, None)

MSG_PLAINTEXT = "public decryption response carries the encrypted plaintext"
MSG_UNAUTHENTICATED = "public decryption response from a KMS party fails authentication"
MSG_ALL_PARTIES = "public decryption succeeded with every party's response checked"
MSG_BATCH = "batched public decryption succeeded"
MSG_SERVER_SNS = "public decryption succeeded with SnS left to the cores"
MSG_NO_VERDICT = "public decryption attempt ended without a verdict"
MSG_THREE_CORES = "public decryption succeeded through three of the four cores"
MSG_RETRY = "public decryption succeeded on a retry after an attempt without a verdict"
MSG_FAILOVER = "public decryption succeeded after the client left out a core it could not connect to"
MSG_SYNC = "public decryption succeeded through the sync endpoint"
MSG_KEYGEN = "workload generated an FHE key"
MSG_RECOVERY_CONNECT = "every core accepts client connections within 600 s after faults stop"
MSG_RECOVERY_DECRYPT = ("public decryption answered by all four cores succeeds within 300 s of every "
                        "core accepting connections")
MSG_RECOVERY_REJOINED = "a core the client could not connect to after faults stopped accepted connections again"
MSG_RECOVERY_RETRIED = ("public decryption answered by all four cores succeeded after a failed first "
                        "attempt once faults stopped")
MSG_USER_PLAINTEXT = "user decryption reconstructs the encrypted plaintext"
MSG_USER_RETRY = "user decryption succeeded on a retry after an attempt without a verdict"
MSG_USER_BATCH = "batched user decryption succeeded"
MSG_USER_ALL_PARTIES = "user decryption succeeded with every party's response collected"
MSG_USER_SERVER_SNS = "user decryption succeeded with SnS left to the cores"
MSG_USER_NO_VERDICT = "user decryption attempt ended without a verdict"
MSG_USER_SYNC = "user decryption succeeded through the sync endpoint"
MSG_USER_RESHARED = "user decryption succeeded under a reshared epoch"
MSG_RESHARED_DECRYPT = "public decryption succeeded under a reshared epoch"
MSG_RESHARED_PLAINTEXT = "public decryption under a reshared epoch carries the encrypted plaintext"
MSG_USER_RESHARED_PLAINTEXT = "user decryption under a reshared epoch reconstructs the encrypted plaintext"
MSG_RESHARE_RESULT = "key reshare result from every KMS party matches the reshared key"
MSG_RESHARE_CHAINED = "key reshare succeeded from an epoch that a reshare created"
MSG_RESHARE_NO_VERDICT = "key reshare attempt ended without a verdict"
MSG_RESHARE_PUBLIC_KEY = "public key that every party publishes for a key is unchanged by a reshare"
MSG_RESHARE_PUBLIC_KEY_FAILED = "public key read back unchanged after a reshare that ended without a verdict"
MSG_RESHARE_SOURCE_PLAINTEXT = ("public decryption under a reshare's source epoch carries the encrypted "
                                "plaintext after the reshare")
MSG_RESHARE_SOURCE_AFTER_FAIL = ("public decryption under the source epoch succeeded after a reshare that "
                                 "ended without a verdict")

PUBDEC = "parallel_driver_pubdec_start.py"
PUBDEC_SYNC = "parallel_driver_pubdec_sync.py"
USERDEC = "parallel_driver_userdec_start.py"
USERDEC_SYNC = "parallel_driver_userdec_sync.py"
RESHARE = "parallel_driver_epoch_reshare.py"
RECOVERY = "eventually_recovers_after_faults.py"

# message: (assert_type, display_type, must_hit, command it lives in, (guarantee, property))
CATALOG = {
    MSG_PLAINTEXT: ("always", "Always", True, PUBDEC, G1),
    MSG_UNAUTHENTICATED: ("reachability", "Unreachable", False, PUBDEC, G1),
    MSG_ALL_PARTIES: ("reachability", "Reachable", True, PUBDEC, G1),
    MSG_BATCH: ("reachability", "Reachable", True, PUBDEC, G1),
    MSG_SERVER_SNS: ("reachability", "Reachable", True, PUBDEC, G1),
    MSG_NO_VERDICT: ("reachability", "Reachable", True, PUBDEC, G1),
    MSG_THREE_CORES: ("reachability", "Reachable", True, PUBDEC, G1),
    MSG_RETRY: ("sometimes", "Sometimes", True, PUBDEC, G1),
    MSG_FAILOVER: ("sometimes", "Sometimes", True, PUBDEC, G1),
    MSG_SYNC: ("reachability", "Reachable", True, PUBDEC_SYNC, G1),
    MSG_KEYGEN: ("reachability", "Reachable", True, "first_generate_key.py", NONE),
    MSG_RECOVERY_CONNECT: ("always", "Always", True, RECOVERY, G2),
    MSG_RECOVERY_DECRYPT: ("always", "Always", True, RECOVERY, G2),
    MSG_RECOVERY_REJOINED: ("sometimes", "Sometimes", True, RECOVERY, G2),
    MSG_RECOVERY_RETRIED: ("sometimes", "Sometimes", True, RECOVERY, G2),
    MSG_USER_PLAINTEXT: ("always", "Always", True, USERDEC, G4),
    MSG_USER_RETRY: ("sometimes", "Sometimes", True, USERDEC, G4),
    MSG_USER_BATCH: ("sometimes", "Sometimes", True, USERDEC, G4),
    MSG_USER_ALL_PARTIES: ("reachability", "Reachable", True, USERDEC, G4),
    MSG_USER_SERVER_SNS: ("reachability", "Reachable", True, USERDEC, G4),
    MSG_USER_NO_VERDICT: ("reachability", "Reachable", True, USERDEC, G4),
    MSG_USER_SYNC: ("reachability", "Reachable", True, USERDEC_SYNC, G4),
    MSG_USER_RESHARED: ("sometimes", "Sometimes", True, USERDEC, G4),
    MSG_RESHARED_DECRYPT: ("reachability", "Reachable", True, PUBDEC, G3),
    MSG_RESHARED_PLAINTEXT: ("always", "AlwaysOrUnreachable", False, PUBDEC, G3),
    MSG_USER_RESHARED_PLAINTEXT: ("always", "AlwaysOrUnreachable", False, USERDEC, G3),
    MSG_RESHARE_RESULT: ("always", "Always", True, RESHARE, G3),
    MSG_RESHARE_CHAINED: ("reachability", "Reachable", True, RESHARE, G3),
    MSG_RESHARE_NO_VERDICT: ("reachability", "Reachable", True, RESHARE, G3),
    MSG_RESHARE_PUBLIC_KEY: ("always", "Always", True, RESHARE, G3),
    MSG_RESHARE_PUBLIC_KEY_FAILED: ("sometimes", "Sometimes", True, RESHARE, G3),
    MSG_RESHARE_SOURCE_PLAINTEXT: ("always", "Always", True, RESHARE, G3),
    MSG_RESHARE_SOURCE_AFTER_FAIL: ("sometimes", "Sometimes", True, RESHARE, G3),
}

# Errors kms-core-client raises only when a validly signed response carries a wrong
# plaintext, a wrong plaintext count or type, or a wrong request ID. Sources: the plaintext
# check in core-client/src/decrypt.rs and validate_public_decrypt_responses in
# core/service/src/engine/validation_non_wasm.rs.
PUBLIC_WRONG_RESULT = [
    "decryption result mismatch",
    "Cannot find public decryption pivot",
    "Not enough agreeing public decryption responses",
    "The number of ciphertexts in the public decryption response is wrong",
    "Plaintext type mismatch in public decryption response",
    "The public decryption response is not linked to the correct public decryption request",
    "Request ID is not set in public decryption response",
]
# Too few responses that pass authentication. A correct party never sends a response that
# fails it; one case is a response for another request, whose signature doesn't cover this
# request's handles.
PUBLIC_UNAUTHENTICATED = ["Not enough authenticated public decryption responses"]
# The CLI's error for authenticated user-decryption shares that reconstructed a plaintext
# other than the encrypted one (reconstruct_user_decrypt in core-client/src/decrypt.rs). Too
# few responses, failed authentication and failed reconstruction are errors, not wrong results.
USER_WRONG_RESULT = ["user decryption result mismatch"]
# Errors kms-core-client new-epoch raises only after every core reported the reshare as done:
# a result names another key or preprocessing ID, or its signature does not verify over the
# published key material (do_new_epoch in core-client/src/mpc_epoch.rs). A core that fails
# or doesn't answer makes it fail earlier, with another error.
RESHARE_WRONG_RESULT = [
    "Resharing response did not contain the expected",
    "No resharing response found",
    "Signature verification failed for the reshared key",
]


def _emit(message, condition, details, hit):
    assert_type, display_type, must_hit, command, (guarantee, prop) = CATALOG[message]
    if hit:
        details = {"guarantee": guarantee, "property": prop, **details}
        print(f"[assert] {display_type} \"{message}\": {condition}", flush=True)
    assert_raw(condition, message, details if hit else None, f"{TEMPLATE_DIR}/{command}", "", "", 0, 0,
               hit, must_hit, assert_type, display_type, message)


def declare_catalog():
    """Declare every assertion once per container, so a never-reached one still shows up."""
    marker = f"{STATE_DIR}/.catalog-declared"
    if os.path.exists(marker):
        return
    for message in CATALOG:
        _emit(message, False, None, hit=False)
    os.makedirs(STATE_DIR, exist_ok=True)
    open(marker, "w").close()


def always(message, condition, details):
    _emit(message, condition, details, True)


def sometimes(message, condition, details):
    _emit(message, condition, details, True)


def always_or_unreachable(message, condition, details):
    _emit(message, condition, details, True)


def reachable(message, details):
    _emit(message, True, details, True)


def unreachable(message, details):
    _emit(message, False, details, True)


def first_match(patterns, out):
    """The first output line that contains one of patterns, or None."""
    for line in out.splitlines():
        if any(p in line for p in patterns):
            return line.strip()[:400]
    return None


def tail(out, lines=2):
    return re.sub(r"[^ -~]", " ", " ".join(out.strip().splitlines()[-lines:]))[:400]


def judge_public_decrypt(rc, out, details, markers=True):
    """Evaluate Guarantee 1 on one public-decrypt run. Returns ok, wrong (a wrong or
    unauthenticated result), args (the command line was malformed) or no_verdict (a timeout,
    a transport error, or cores that answered with errors; expected under faults).
    markers=False evaluates only the safety checks, for the recovery probe."""
    reshared = details.get("epoch_status", "default") != "default"
    if rc == 0:
        d = dict(details, request_id=request_id_from(out))
        always(MSG_PLAINTEXT, True, d)
        if reshared:
            always_or_unreachable(MSG_RESHARED_PLAINTEXT, True, d)
        if markers:
            if details.get("after_failed_call"):
                sometimes(MSG_RETRY, True, d)
            if details.get("failing_over"):
                sometimes(MSG_FAILOVER, True, d)
            if details.get("all_parties"):
                reachable(MSG_ALL_PARTIES, d)
            if details.get("left_out") is not None:
                reachable(MSG_THREE_CORES, d)
            if details.get("sync"):
                reachable(MSG_SYNC, d)
            if details.get("batch", 1) > 1:
                reachable(MSG_BATCH, d)
            if details.get("no_precompute_sns"):
                reachable(MSG_SERVER_SNS, d)
            if reshared:
                reachable(MSG_RESHARED_DECRYPT, d)
        return "ok"
    err = first_match(PUBLIC_WRONG_RESULT, out)
    if err:
        always(MSG_PLAINTEXT, False, dict(details, error=err))
        if reshared:
            always_or_unreachable(MSG_RESHARED_PLAINTEXT, False, dict(details, error=err))
        print(out)
        return "wrong"
    err = first_match(PUBLIC_UNAUTHENTICATED, out)
    if err:
        unreachable(MSG_UNAUTHENTICATED, dict(details, error=err))
        print(out)
        return "wrong"
    if rc == 2:  # the CLI's argument parser: this workload built a malformed command
        print("kms-core-client rejected the arguments\n" + out)
        return "args"
    if markers:
        d = dict(details, connected="Threshold Client setup done" in out, error=tail(out))
        reachable(MSG_NO_VERDICT, d)
        if details.get("after_failed_call"):
            sometimes(MSG_RETRY, False, d)
        if details.get("failing_over"):
            sometimes(MSG_FAILOVER, False, d)
    return "no_verdict"


def judge_user_decrypt(rc, out, details):
    """Evaluate Guarantee 4 on one user-decrypt run. Same return values as
    judge_public_decrypt. Every error other than the result mismatch is the guarantee's
    "or an error" side, and is not a violation."""
    reshared = details.get("epoch_status", "default") != "default"
    if rc == 0:
        d = dict(details, request_id=request_id_from(out))
        always(MSG_USER_PLAINTEXT, True, d)
        if reshared:
            always_or_unreachable(MSG_USER_RESHARED_PLAINTEXT, True, d)
            sometimes(MSG_USER_RESHARED, True, d)
        if details.get("after_failed_call"):
            sometimes(MSG_USER_RETRY, True, d)
        if details["batch"] > 1:
            sometimes(MSG_USER_BATCH, True, d)
        if details.get("all_parties"):
            reachable(MSG_USER_ALL_PARTIES, d)
        if details.get("sync"):
            reachable(MSG_USER_SYNC, d)
        if details.get("no_precompute_sns"):
            reachable(MSG_USER_SERVER_SNS, d)
        return "ok"
    err = first_match(USER_WRONG_RESULT, out)
    if err:
        always(MSG_USER_PLAINTEXT, False, dict(details, error=err))
        if reshared:
            always_or_unreachable(MSG_USER_RESHARED_PLAINTEXT, False, dict(details, error=err))
        print(out)
        return "wrong"
    if rc == 2:
        print("kms-core-client rejected the arguments\n" + out)
        return "args"
    d = dict(details, connected="Threshold Client setup done" in out, error=tail(out))
    reachable(MSG_USER_NO_VERDICT, d)
    if details.get("after_failed_call"):
        sometimes(MSG_USER_RETRY, False, d)
    if details["batch"] > 1:
        sometimes(MSG_USER_BATCH, False, d)
    if reshared:
        sometimes(MSG_USER_RESHARED, False, d)
    # Failed authentication or reconstruction should not come from honest cores that only
    # crash or lose messages, so it is logged for triage.
    odd = first_match(["unrecoverably invalid", "Not enough correct responses", "Too many faulty",
                       "Not enough shares to reconstruct", "Error reconstructing all blocks"], out)
    if odd:
        print(f"suspicious user decryption error: {odd}")
    return "no_verdict"


def judge_reshare(rc, out, details):
    """Evaluate one new-epoch run. Returns done (every core reported success and the CLI's
    checks passed), wrong, args, or no_verdict: a reshare that did not finish everywhere (a
    core down, slow or cut off, or one that rejected the request; the CLI reports it as an
    error or a panic). Under faults that is allowed."""
    if rc == 0 and "New epoch created" in out:
        always(MSG_RESHARE_RESULT, True, details)
        if details["source_epoch"] != DEFAULT_EPOCH_ID:
            reachable(MSG_RESHARE_CHAINED, details)
        return "done"
    err = first_match(RESHARE_WRONG_RESULT, out)
    if err:
        always(MSG_RESHARE_RESULT, False, dict(details, error=err))
        print(out)
        return "wrong"
    if rc == 2:
        print("kms-core-client rejected the arguments\n" + out)
        return "args"
    reachable(MSG_RESHARE_NO_VERDICT, dict(details, error=first_match(["panicked at"], out) or tail(out, 3)))
    return "no_verdict"


def judge_public_key(before, after, details):
    """Compare every party's public-key digest for the reshared key, read before and after the
    reshare (party -> digest, "missing" or "unread"). Public material is stored per key, not
    per epoch, so a reshare must leave it byte-identical. A party unread either time, or
    without the key before, is left out; one that had it before and is missing after counts
    as changed. Returns False when a digest changed."""
    compared = sorted(p for p, d in before.items() if d not in ("missing", "unread") and after.get(p) != "unread")
    if not compared:
        print("could not read any party's public key both before and after; no public key check", flush=True)
        return True
    changed = [p for p in compared if after[p] != before[p]]
    d = dict(details, parties_compared=compared, changed=changed, before=before, after=after)
    always(MSG_RESHARE_PUBLIC_KEY, not changed, d)
    if details["outcome"] == "no_verdict":
        sometimes(MSG_RESHARE_PUBLIC_KEY_FAILED, not changed, d)
    return not changed


def judge_source_decrypt(rc, out, details):
    """Evaluate one public decryption under a reshare's source epoch, after the reshare. Only a
    wrong plaintext fails: a reshare that ended without a verdict may have taken effect on some
    cores, but the source epoch must keep its key shares. Same return values as
    judge_public_decrypt."""
    after_fail = details["outcome"] == "no_verdict"
    if rc == 0:
        d = dict(details, request_id=request_id_from(out))
        always(MSG_RESHARE_SOURCE_PLAINTEXT, True, d)
        if after_fail:
            sometimes(MSG_RESHARE_SOURCE_AFTER_FAIL, True, d)
        return "ok"
    err = first_match(PUBLIC_WRONG_RESULT, out)
    if err:
        always(MSG_RESHARE_SOURCE_PLAINTEXT, False, dict(details, error=err))
        print(out)
        return "wrong"
    if rc == 2:
        print("kms-core-client rejected the arguments\n" + out)
        return "args"
    # A response that fails authentication never comes from a correct party; the decryption
    # drivers assert on that, here it is only logged.
    unauthenticated = first_match(PUBLIC_UNAUTHENTICATED, out)
    if unauthenticated:
        print(f"source epoch check: {unauthenticated}", flush=True)
    if after_fail:
        sometimes(MSG_RESHARE_SOURCE_AFTER_FAIL, False, dict(details, error=tail(out)))
    return "no_verdict"
