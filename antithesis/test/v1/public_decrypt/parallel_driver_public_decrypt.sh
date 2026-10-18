#!/bin/sh
# Runs one public decryption of a fresh value, retrying when an attempt ends without a verdict.
#
# kms-core-client does the checking. It encrypts the value under the cluster's public key and
# sends the request to the cores in its config. It collects 2 responses (every configured
# core's with -a) and checks their signatures, their agreement and their request link. It then
# compares every collected plaintext with the encrypted value. This script picks the inputs at
# random and classifies the exit of the CLI. A wrong result is a property failure. Any other
# error is an attempt without a verdict, which is expected under faults: the request may or
# may not still complete on the cores, and nothing here depends on which.
#
# Inputs: FHE type and value (zero, one, max, top bit, random), batch size, compressed or not,
# SnS precomputed by the client or left to the cores, the async endpoint with result polling
# or the sync endpoint, and the epoch. Until anytime_reshare_key.sh reshares the key, every
# run decrypts under the kms-init epoch. After that, up to 3 runs in 5 decrypt under a
# reshared epoch instead (see pick_epoch), so the same check covers the shares that a reshare
# produced.
#
# Cores. The CLI connects to every core in its config before it sends anything, so while one
# core does not accept connections a four-core config fails before reaching the cluster. A run
# therefore starts either with all four cores or with three (a random one left out, still
# num_parties = 4). -a is used only with four cores: with three it would wait for a fourth
# response that never comes. How often a run uses three cores, -a and --sync is drawn once per
# timeline (timeline_choice), so some timelines lean one way and some the other.
#
# Retries. A run makes up to 3 attempts. Each attempt is a new CLI run, so a new random request
# ID and a fresh encryption of the same value; a request ID is never reused here (that is
# Guarantee 5). An attempt without a verdict is retried after 10 s. If it did not get past
# connecting, the CLI's log (-l) names the core it was connecting to, and the next attempt
# leaves that core out, as a client would fail over to the cores it can reach.
#
# Checks (Guarantee 1; the reshared-epoch checks are Guarantee 3):
# - Always: a public decryption the CLI accepts carries the encrypted plaintext, and the CLI
#   never fails with an error that only a validly signed wrong result causes.
# - AlwaysOrUnreachable (Guarantee 3): the same check for decryptions under a reshared epoch,
#   confirmed or not, so a wrong plaintext there also counts against the reshare.
# - Unreachable: a response from a KMS party fails authentication.
# - Sometimes: a decryption succeeded on a retry after an attempt without a verdict (judged on
#   every retry).
# - Sometimes: a decryption succeeded after the client left out a core it could not connect to
#   (judged on every attempt that fails over).
# - Reachable: a decryption succeeded with -a, with --sync, with a batch, with SnS left to the
#   cores, through three cores, and under a reshared epoch; an attempt ended without a verdict.
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
chance "$(timeline_choice sync_pct 10 50 90)" && sync=true
all_parties_pct=$(timeline_choice all_parties_pct 0 33 90)
left_out=none
chance "$(timeline_choice three_core_pct 0 25 50 90)" && left_out=$(pick 1 2 3 4)
max_attempts=$(pick 1 2 3 3)

enter_scratch_dir

attempt=0
failed=0
ok=false
fail_over=false # the next attempt leaves out a core that the last one could not connect to
while [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))
  failing_over=$fail_over
  fail_over=false
  write_client_config "$left_out"
  all_parties=false
  if [ "$left_out" = none ] && chance "$all_parties_pct"; then all_parties=true; fi

  # --max-iter counts 0.5 s result polls per core.
  set -- -l -f config.toml --max-iter 120
  [ "$all_parties" = true ] && set -- "$@" -a
  set -- "$@" public-decrypt from-args --to-encrypt "0x$value" --data-type "$data_type" \
    --key-id "$key_id" --batch-size "$batch"
  [ "$epoch_status" != default ] &&
    set -- "$@" --context-id "$DEFAULT_CONTEXT_ID" --epoch-id "$epoch_id"
  [ "$sync" = true ] && set -- "$@" --sync
  [ "$no_compression" = true ] && set -- "$@" --no-compression
  [ "$no_sns" = true ] && set -- "$@" --no-precompute-sns

  echo "attempt $attempt/$max_attempts: kms-core-client $*"
  timeout 300 kms-core-client "$@" >cli.out 2>&1
  rc=$?

  inputs="\"data_type\":\"$data_type\",\"value_hex\":\"$value\",\"batch\":$batch,\"all_parties\":$all_parties,\"left_out\":\"$left_out\",\"sync\":$sync,\"no_compression\":$no_compression,\"no_precompute_sns\":$no_sns,\"key_id\":\"$key_id\",\"epoch_id\":\"$epoch_id\",\"epoch_status\":\"$epoch_status\",\"attempt\":$attempt,\"failed_attempts\":$failed,\"exit_code\":$rc"

  if [ "$rc" -eq 0 ]; then
    ok=true
    details="{$inputs,\"request_id\":\"$(request_id_from cli.out)\"}"
    if [ "$attempt" -gt 1 ]; then assert_sometimes "$MSG_RETRY" true "$details"; fi
    if [ "$failing_over" = true ]; then assert_sometimes "$MSG_FAILOVER" true "$details"; fi
    assert_always "$MSG_PLAINTEXT" true "$details"
    if [ "$all_parties" = true ]; then assert_reachable "$MSG_ALL_PARTIES" "$details"; fi
    if [ "$left_out" != none ]; then assert_reachable "$MSG_THREE_CORES" "$details"; fi
    if [ "$sync" = true ]; then assert_reachable "$MSG_SYNC" "$details"; fi
    if [ "$batch" -gt 1 ]; then assert_reachable "$MSG_BATCH" "$details"; fi
    if [ "$no_sns" = true ]; then assert_reachable "$MSG_SERVER_SNS" "$details"; fi
    if [ "$epoch_status" != default ]; then
      assert_always_or_unreachable "$MSG_RESHARED_PLAINTEXT" true "$details"
      assert_reachable "$MSG_RESHARED_DECRYPT" "$details"
    fi
    break
  fi

  if err=$(public_decrypt_wrong_result cli.out); then
    assert_always "$MSG_PLAINTEXT" false "{$inputs,\"error\":\"$(json_str "$err")\"}"
    if [ "$epoch_status" != default ]; then
      assert_always_or_unreachable "$MSG_RESHARED_PLAINTEXT" false "{$inputs,\"error\":\"$(json_str "$err")\"}"
    fi
    cat cli.out
    exit 1
  fi

  if err=$(public_decrypt_unauthenticated cli.out); then
    assert_unreachable "$MSG_UNAUTHENTICATED" "{$inputs,\"error\":\"$(json_str "$err")\"}"
    cat cli.out
    exit 1
  fi

  # The CLI's argument parser exits with 2, so this script built a malformed command.
  if [ "$rc" -eq 2 ]; then
    echo "kms-core-client rejected the arguments"
    cat cli.out
    exit 1
  fi

  # No verdict: a timeout, a transport error, or cores that answered with errors.
  failed=$((failed + 1))
  connected=true
  cli_connected cli.out || connected=false
  details="{$inputs,\"connected\":$connected,\"error\":\"$(json_str "$(tail -n 2 cli.out)")\"}"
  assert_reachable "$MSG_NO_VERDICT" "$details"
  if [ "$attempt" -gt 1 ]; then assert_sometimes "$MSG_RETRY" false "$details"; fi
  if [ "$failing_over" = true ]; then assert_sometimes "$MSG_FAILOVER" false "$details"; fi
  tail -n 5 cli.out | cut -c 1-400
  if [ "$connected" = false ] && unreached=$(cli_unreached_party cli.out); then
    echo "could not connect to party $unreached; the next attempt leaves it out"
    left_out=$unreached
    fail_over=true
  fi
  [ "$attempt" -lt "$max_attempts" ] && sleep 10
done

echo "public decryption: ok=$ok after $attempt attempt(s), $failed without a verdict"
exit 0
