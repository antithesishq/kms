#!/bin/sh
# Runs one public decryption of a fresh value and turns the outcome into assertions.
#
# kms-core-client does the checking. It encrypts the value under the cluster's public key and
# sends the request to all four cores. It collects 2 responses (all 4 with -a) and checks their
# signatures, their agreement and their request link. It then compares every collected
# plaintext with the encrypted value. This script picks the inputs at random and classifies
# the exit of the CLI. A wrong result is a property failure. Any other error is a transient
# failure, which is expected under faults.
#
# Until anytime_reshare_key.sh reshares the key, every run decrypts under the kms-init epoch.
# After that, up to 3 runs in 5 decrypt under a reshared epoch instead (see pick_epoch), so
# the same check covers the shares that a reshare produced.
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
all_parties=$(pick false false true)
sync=$(pick false true)
no_compression=$(pick false false false true)
no_sns=$(pick false false false true)

# --max-iter counts 0.5 s result polls per party.
set -- -f config.toml --max-iter 120
[ "$all_parties" = true ] && set -- "$@" -a
set -- "$@" public-decrypt from-args --to-encrypt "0x$value" --data-type "$data_type" \
  --key-id "$key_id" --batch-size "$batch"
[ "$epoch_status" != default ] &&
  set -- "$@" --context-id "$DEFAULT_CONTEXT_ID" --epoch-id "$epoch_id"
[ "$sync" = true ] && set -- "$@" --sync
[ "$no_compression" = true ] && set -- "$@" --no-compression
[ "$no_sns" = true ] && set -- "$@" --no-precompute-sns

enter_scratch_dir
echo "kms-core-client $*"
timeout 300 kms-core-client "$@" >cli.out 2>&1
rc=$?

inputs="\"data_type\":\"$data_type\",\"value_hex\":\"$value\",\"batch\":$batch,\"all_parties\":$all_parties,\"sync\":$sync,\"no_compression\":$no_compression,\"no_precompute_sns\":$no_sns,\"key_id\":\"$key_id\",\"epoch_id\":\"$epoch_id\",\"epoch_status\":\"$epoch_status\",\"exit_code\":$rc"

# Errors that the CLI raises only when a validly signed response carries a wrong plaintext,
# a wrong plaintext count or type, or a wrong request ID. Sources: the plaintext check in
# core-client/src/decrypt.rs and validate_public_decrypt_responses in
# core/service/src/engine/validation_non_wasm.rs.
wrong_result() {
  grep -m 1 \
    -e 'decryption result mismatch' \
    -e 'Cannot find public decryption pivot' \
    -e 'Not enough agreeing public decryption responses' \
    -e 'The number of ciphertexts in the public decryption response is wrong' \
    -e 'Plaintext type mismatch in public decryption response' \
    -e 'The public decryption response is not linked to the correct public decryption request' \
    -e 'Request ID is not set in public decryption response' \
    cli.out
}

if [ "$rc" -eq 0 ]; then
  details="{$inputs,\"request_id\":\"$(request_id_from cli.out)\"}"
  assert_always "$MSG_PLAINTEXT" true "$details"
  if [ "$all_parties" = true ]; then assert_reachable "$MSG_ALL_PARTIES" "$details"; fi
  if [ "$sync" = true ]; then assert_reachable "$MSG_SYNC" "$details"; fi
  if [ "$batch" -gt 1 ]; then assert_reachable "$MSG_BATCH" "$details"; fi
  if [ "$no_sns" = true ]; then assert_reachable "$MSG_SERVER_SNS" "$details"; fi
  if [ "$epoch_status" != default ]; then assert_reachable "$MSG_RESHARED_DECRYPT" "$details"; fi
  exit 0
fi

if err=$(wrong_result); then
  assert_always "$MSG_PLAINTEXT" false "{$inputs,\"error\":\"$(json_str "$err")\"}"
  cat cli.out
  exit 1
fi

# A response that fails authentication never comes from a correct party. One case is a
# response for another request, whose signature does not cover this request's handles.
if err=$(grep -m 1 'Not enough authenticated public decryption responses' cli.out); then
  assert_unreachable "$MSG_UNAUTHENTICATED" "{$inputs,\"error\":\"$(json_str "$err")\"}"
  cat cli.out
  exit 1
fi

assert_reachable "$MSG_NO_VERDICT" "{$inputs,\"error\":\"$(json_str "$(tail -n 3 cli.out)")\"}"
tail -n 20 cli.out
exit 0
