#!/bin/sh
# Runs one user decryption of a fresh value, retrying when an attempt ends without a verdict.
#
# kms-core-client does the checking. It encrypts the value under the cluster's public key,
# sends a user-decryption request with a fresh request ID and a fresh ephemeral ML-KEM key to
# the four cores, and collects 3 responses (all four with -a). It authenticates each response
# (signature, link to the request, agreement on degree and slot metadata), un-signcrypts the
# shares, reconstructs the plaintext with error correction and compares it with the encrypted
# value. Only that comparison's error, "user decryption result mismatch", means authenticated
# shares rebuilt a wrong value; this script classifies the CLI's exit on it. Every other error
# (too few responses, failed authentication or reconstruction, transport errors, timeouts) is
# an attempt without a verdict, which the guarantee allows ("the value or an error"). Its
# outcome on the cores is unknown and nothing here depends on it.
#
# Inputs: FHE type and value (zero, one, max, top bit, random), batch size, compressed or not,
# SnS precomputed by the client or left to the cores, the async endpoint with result polling
# or the sync endpoint, -a or not, and the epoch: the kms-init epoch, or after
# anytime_reshare_key.sh has run, up to 3 runs in 5 under a reshared epoch (pick_epoch). How
# often a run uses --sync and -a is drawn once per timeline (timeline_choice).
#
# Cores. Unlike public decryption, user decryption always uses the pod's four-core config. The
# client derives the threshold from the cores in its config, (n - 1) / 3, so with three it
# expects degree-0 shares and rejects the cores' degree-1 shares (UserDecTrustedValidationContext
# and the pivot check in core/service/src/engine/validation_wasm.rs). While a core does not
# accept connections, every attempt therefore fails at connect, which is an allowed error.
#
# Retries. A run makes up to 3 attempts, 10 s apart. Each attempt is a new CLI run, so a new
# request ID, a new ephemeral key and a fresh encryption of the same value.
#
# Checks (Guarantee 4; the reshared-epoch check is Guarantee 3):
# - Always: a user decryption the CLI completes reconstructs the encrypted plaintext; the CLI
#   never reports a result mismatch.
# - AlwaysOrUnreachable (Guarantee 3): the same check for decryptions under a reshared epoch.
# - Sometimes: a decryption succeeded on a retry after an attempt without a verdict (judged on
#   every retry).
# - Sometimes: a decryption under a reshared epoch succeeded (judged on every such attempt).
# - Sometimes: a batched decryption succeeded (judged on every batched attempt).
# - Reachable: a decryption succeeded with -a, with --sync, with SnS left to the cores; an
#   attempt ended without a verdict.
. "$(dirname "$0")/helper_lib.sh"
declare_catalog

if ! key_id=$(find_key_id); then
  echo "no FHE key published in MinIO yet; nothing to decrypt"
  exit 0
fi

epoch=$(pick_epoch "$key_id")
epoch_id=${epoch% *}
epoch_status=${epoch#* }
data_type=$(pick ebool euint8 euint16 euint32 euint64 euint128 euint160 euint256)
value=$(pick_value "$data_type")
batch=$(pick 1 1 1 2 3)
no_compression=$(pick false false false true)
no_sns=$(pick false false false true)
sync=false
chance "$(timeline_choice user_sync_pct 10 50 90)" && sync=true
all_parties_pct=$(timeline_choice user_all_parties_pct 0 33 90)
max_attempts=$(pick 1 2 3 3)

enter_scratch_dir

attempt=0
failed=0
ok=false
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))
  all_parties=false
  chance "$all_parties_pct" && all_parties=true

  # --max-iter counts 0.5 s result polls per core.
  set -- -l -f config.toml --max-iter 120
  [ "$all_parties" = true ] && set -- "$@" -a
  set -- "$@" user-decrypt from-args --to-encrypt "0x$value" --data-type "$data_type" \
    --key-id "$key_id" --batch-size "$batch"
  [ "$epoch_status" != default ] &&
    set -- "$@" --context-id "$DEFAULT_CONTEXT_ID" --epoch-id "$epoch_id"
  [ "$sync" = true ] && set -- "$@" --sync
  [ "$no_compression" = true ] && set -- "$@" --no-compression
  [ "$no_sns" = true ] && set -- "$@" --no-precompute-sns

  echo "attempt $attempt/$max_attempts: kms-core-client $*"
  timeout 300 kms-core-client "$@" >cli.out 2>&1
  rc=$?

  inputs="\"data_type\":\"$data_type\",\"value_hex\":\"$value\",\"batch\":$batch,\"all_parties\":$all_parties,\"sync\":$sync,\"no_compression\":$no_compression,\"no_precompute_sns\":$no_sns,\"key_id\":\"$key_id\",\"epoch_id\":\"$epoch_id\",\"epoch_status\":\"$epoch_status\",\"attempt\":$attempt,\"failed_attempts\":$failed,\"exit_code\":$rc"

  if [ "$rc" -eq 0 ]; then
    ok=true
    details="{$inputs,\"request_id\":\"$(request_id_from cli.out)\"}"
    assert_always "$MSG_USER_PLAINTEXT" true "$details"
    if [ "$epoch_status" != default ]; then
      assert_always_or_unreachable "$MSG_USER_RESHARED_PLAINTEXT" true "$details"
      assert_sometimes "$MSG_USER_RESHARED" true "$details"
    fi
    if [ "$attempt" -gt 1 ]; then assert_sometimes "$MSG_USER_RETRY" true "$details"; fi
    if [ "$batch" -gt 1 ]; then assert_sometimes "$MSG_USER_BATCH" true "$details"; fi
    if [ "$all_parties" = true ]; then assert_reachable "$MSG_USER_ALL_PARTIES" "$details"; fi
    if [ "$sync" = true ]; then assert_reachable "$MSG_USER_SYNC" "$details"; fi
    if [ "$no_sns" = true ]; then assert_reachable "$MSG_USER_SERVER_SNS" "$details"; fi
    break
  fi

  if err=$(user_decrypt_wrong_result cli.out); then
    details="{$inputs,\"error\":\"$(json_str "$err")\"}"
    assert_always "$MSG_USER_PLAINTEXT" false "$details"
    if [ "$epoch_status" != default ]; then
      assert_always_or_unreachable "$MSG_USER_RESHARED_PLAINTEXT" false "$details"
    fi
    cat cli.out
    exit 1
  fi

  # The CLI's argument parser exits with 2, so this script built a malformed command.
  if [ "$rc" -eq 2 ]; then
    echo "kms-core-client rejected the arguments"
    cat cli.out
    exit 1
  fi

  # No verdict: a timeout, a transport error, too few responses, or responses that failed
  # authentication or reconstruction. The last two should not come from honest cores that
  # only crash or lose messages, so they are logged for triage.
  failed=$((failed + 1))
  connected=true
  cli_connected cli.out || connected=false
  details="{$inputs,\"connected\":$connected,\"error\":\"$(json_str "$(tail -n 2 cli.out)")\"}"
  assert_reachable "$MSG_USER_NO_VERDICT" "$details"
  if [ "$attempt" -gt 1 ]; then assert_sometimes "$MSG_USER_RETRY" false "$details"; fi
  if [ "$epoch_status" != default ]; then assert_sometimes "$MSG_USER_RESHARED" false "$details"; fi
  if [ "$batch" -gt 1 ]; then assert_sometimes "$MSG_USER_BATCH" false "$details"; fi
  grep -m 1 -e 'unrecoverably invalid' -e 'Not enough correct responses' -e 'Too many faulty' \
    -e 'Not enough shares to reconstruct' -e 'Error reconstructing all blocks' cli.out |
    sed 's/^/suspicious user decryption error: /' | cut -c 1-400
  tail -n 5 cli.out | cut -c 1-400
  [ "$attempt" -lt "$max_attempts" ] && sleep 10
done

echo "user decryption: ok=$ok after $attempt attempt(s), $failed without a verdict"
exit 0
