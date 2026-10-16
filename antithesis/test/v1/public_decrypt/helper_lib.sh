#!/bin/sh
# Shared helpers for the public_decrypt test template. Sourced by the test commands; the
# helper_ prefix makes Antithesis skip this file when it picks commands to run.
#
# Assertions use the Antithesis fallback SDK: one JSON line per message, appended to
# $ANTITHESIS_OUTPUT_DIR/sdk.jsonl. Outside Antithesis (hand-driving with kubectl exec) they
# go to /tmp/antithesis-sdk.jsonl instead, and every evaluation is also echoed to stdout.
# Format: https://antithesis.com/docs/reference/sdk/fallback/assert/

TEMPLATE_DIR=/opt/antithesis/test/v1/public_decrypt
CLIENT_DIR=/app/kms-core-client # config.toml is written here when the pod starts
S3_PUBLIC=http://minio:9000/kms-public

# State that the test commands share. All of them run in the kms-core-client container, so a
# directory in its /tmp is enough. The state is lost when the container restarts.
#   preproc/<key_id>  the preprocessing ID of the key (written by first_generate_key.sh)
#   epochs            one line per reshare: <epoch_id> <key_id> confirmed|unconfirmed
STATE_DIR=/tmp/kms-workload-state
EPOCHS_FILE="$STATE_DIR/epochs"

# The context and epoch that kms-init creates (DEFAULT_MPC_CONTEXT and DEFAULT_EPOCH_ID in
# core/service/src/consts.rs). A request with no epoch ID goes to this epoch.
DEFAULT_CONTEXT_ID=0700000000000000000000000000000000000000000000000000000000000001
DEFAULT_EPOCH_ID=0800000000000000000000000000000000000000000000000000000000000001

if [ -n "$ANTITHESIS_OUTPUT_DIR" ]; then
  SDK_FILE="$ANTITHESIS_OUTPUT_DIR/sdk.jsonl"
else
  SDK_FILE=/tmp/antithesis-sdk.jsonl
fi

# Property names. Each one is declared in the catalog and evaluated under exactly this text.
MSG_PLAINTEXT="public decryption response carries the encrypted plaintext"
MSG_UNAUTHENTICATED="public decryption response from a KMS party fails authentication"
MSG_ALL_PARTIES="public decryption succeeded with every party's response checked"
MSG_SYNC="public decryption succeeded through the sync endpoint"
MSG_BATCH="batched public decryption succeeded"
MSG_SERVER_SNS="public decryption succeeded with SnS left to the cores"
MSG_NO_VERDICT="public decryption attempt ended without a verdict"
MSG_RESHARED_DECRYPT="public decryption succeeded under a reshared epoch"
MSG_KEYGEN="workload generated an FHE key"
MSG_RESHARE_RESULT="key reshare result from every KMS party matches the reshared key"
MSG_RESHARE_CHAINED="key reshare succeeded from an epoch that a reshare created"
MSG_RESHARE_NO_VERDICT="key reshare attempt ended without a verdict"

# The command an assertion lives in. Declaration and evaluation must carry the same location.
location_of() {
  case "$1" in
    "$MSG_KEYGEN") echo "$TEMPLATE_DIR/first_generate_key.sh" ;;
    "$MSG_RESHARE_RESULT" | "$MSG_RESHARE_CHAINED" | "$MSG_RESHARE_NO_VERDICT")
      echo "$TEMPLATE_DIR/anytime_reshare_key.sh" ;;
    *) echo "$TEMPLATE_DIR/parallel_driver_public_decrypt.sh" ;;
  esac
}

# sdk_emit HIT MUST_HIT ASSERT_TYPE DISPLAY_TYPE MESSAGE CONDITION [DETAILS_JSON]
sdk_emit() {
  local details=""
  [ -n "$7" ] && details=",\"details\":$7"
  printf '{"antithesis_assert":{"hit":%s,"must_hit":%s,"assert_type":"%s","display_type":"%s","message":"%s","condition":%s,"id":"%s","location":{"class":"","function":"","file":"%s","begin_line":0,"begin_column":0}%s}}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$5" "$(location_of "$5")" "$details" >>"$SDK_FILE"
}

# Write the assertion catalog once per container, so that a never-reached Always or Reachable
# still shows up as failing. Concurrent first calls both write it, which is harmless.
declare_catalog() {
  local marker=/tmp/.antithesis-catalog-declared
  [ -e "$marker" ] && return 0
  sdk_emit false true always Always "$MSG_PLAINTEXT" false
  sdk_emit false false reachability Unreachable "$MSG_UNAUTHENTICATED" false
  sdk_emit false true reachability Reachable "$MSG_ALL_PARTIES" false
  sdk_emit false true reachability Reachable "$MSG_SYNC" false
  sdk_emit false true reachability Reachable "$MSG_BATCH" false
  sdk_emit false true reachability Reachable "$MSG_SERVER_SNS" false
  sdk_emit false true reachability Reachable "$MSG_NO_VERDICT" false
  sdk_emit false true reachability Reachable "$MSG_RESHARED_DECRYPT" false
  sdk_emit false true reachability Reachable "$MSG_KEYGEN" false
  sdk_emit false true always Always "$MSG_RESHARE_RESULT" false
  sdk_emit false true reachability Reachable "$MSG_RESHARE_CHAINED" false
  sdk_emit false true reachability Reachable "$MSG_RESHARE_NO_VERDICT" false
  touch "$marker"
}

# assert_always MESSAGE true|false DETAILS_JSON
assert_always() {
  echo "[assert] Always \"$1\": $2"
  sdk_emit true true always Always "$1" "$2" "$3"
}

# assert_reachable MESSAGE DETAILS_JSON
assert_reachable() {
  echo "[assert] Reachable \"$1\""
  sdk_emit true true reachability Reachable "$1" true "$2"
}

# assert_unreachable MESSAGE DETAILS_JSON
assert_unreachable() {
  echo "[assert] Unreachable \"$1\" was reached"
  sdk_emit true false reachability Unreachable "$1" false "$2"
}

# json_str TEXT: TEXT made safe to embed in a JSON string. Keeps printable ASCII only and
# caps the length, since error output is just context for triage.
json_str() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | tr -cd ' -~' | head -c 400 | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# rand_below N: an integer in [0, N). Reads /dev/urandom, which is the fallback-SDK way to
# take randomness from Antithesis.
rand_below() {
  local r
  r=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
  echo $((r % $1))
}

# pick ARG...: one argument chosen at random. Repeat an argument to weight it.
pick() {
  shift "$(rand_below $#)"
  echo "$1"
}

# repeat_byte HEXBYTE COUNT
repeat_byte() {
  local i=0 out=""
  while [ "$i" -lt "$2" ]; do
    out="$out$1"
    i=$((i + 1))
  done
  echo "$out"
}

# pick_value TYPE: a little-endian hex value for TYPE (as kms-core-client --to-encrypt reads
# it), drawn from the type's value menu: zero, one, the maximum, only the top bit set, or
# uniformly random bits. Random values keep requests distinguishable from each other.
pick_value() {
  if [ "$1" = ebool ]; then
    pick 00 01
    return
  fi
  local n=$((${1#euint} / 8))
  case $(pick zero one max top random random) in
    zero) repeat_byte 00 "$n" ;;
    one) echo "01$(repeat_byte 00 $((n - 1)))" ;;
    max) repeat_byte ff "$n" ;;
    top) echo "$(repeat_byte 00 $((n - 1)))80" ;;
    random) echo "$(head -c "$n" /dev/urandom | od -An -v -tx1 | tr -d ' \n')" ;;
  esac
}

# find_key_id: print the ID of an FHE key that party 1 has published, at random if there
# are several. Keys are looked up in MinIO rather than a local file, so a key generated by
# hand is found too. Fails when there is none (or MinIO is unreachable).
find_key_id() {
  local ids n
  ids=$(wget -qO- "$S3_PUBLIC?list-type=2&prefix=PUB-p1/PublicKey/" 2>/dev/null |
    grep -o '<Key>PUB-p1/PublicKey/[^<]*</Key>' |
    sed 's#<Key>PUB-p1/PublicKey/##; s#</Key>##')
  [ -n "$ids" ] || return 1
  n=$(printf '%s\n' "$ids" | wc -l)
  printf '%s\n' "$ids" | sed -n "$(($(rand_below "$n") + 1))p"
}

# request_id_from FILE: the request ID from kms-core-client's success line,
#   <msg> - "request_id": "<id>"
request_id_from() {
  local id
  id=$(sed -n 's/.*"request_id": "\([0-9a-fA-F]*\)".*/\1/p' "$1" | tail -n 1)
  [ -n "$id" ] || return 1
  echo "$id"
}

# enter_scratch_dir: cd into a fresh directory holding a copy of config.toml. The CLI
# downloads key material into ./keys on every run, so concurrent runs sharing a directory
# would overwrite each other's files.
enter_scratch_dir() {
  SCRATCH=$(mktemp -d /tmp/kms-workload.XXXXXX) || exit 1
  trap 'rm -rf "$SCRATCH"' EXIT
  cp "$CLIENT_DIR/config.toml" "$SCRATCH/" || exit 1
  cd "$SCRATCH" || exit 1
}

# record_preproc KEY_ID PREPROC_ID: remember the preprocessing ID of a key. A reshare request
# must carry the ID that the key was generated from, and no public object records it.
record_preproc() {
  mkdir -p "$STATE_DIR/preproc" && echo "$2" >"$STATE_DIR/preproc/$1"
}

# find_reshare_key: print "KEY_ID PREPROC_ID" for a key with a recorded preprocessing ID, at
# random if there are several. Fails when there is none.
find_reshare_key() {
  local keys key
  keys=$(ls "$STATE_DIR/preproc" 2>/dev/null)
  [ -n "$keys" ] || return 1
  key=$(pick $keys)
  echo "$key $(cat "$STATE_DIR/preproc/$key")"
}

# record_epoch EPOCH_ID KEY_ID confirmed|unconfirmed: one short line, appended with a single
# write, so lines from concurrent commands do not mix.
record_epoch() {
  mkdir -p "$STATE_DIR" && printf '%s %s %s\n' "$1" "$2" "$3" >>"$EPOCHS_FILE"
}

# epochs_of KEY_ID STATUS: the recorded epochs with STATUS that KEY_ID was reshared into.
epochs_of() {
  grep " $1 $2\$" "$EPOCHS_FILE" 2>/dev/null | cut -d ' ' -f 1
}

# pick_epoch KEY_ID: print "EPOCH_ID STATUS" for a public decryption under KEY_ID. STATUS is
# default (the kms-init epoch), confirmed (every core reported the reshare as done) or
# unconfirmed (the reshare CLI failed, so some cores can hold the epoch and others not).
# Falls back to the default epoch when no reshared epoch of the chosen kind exists.
pick_epoch() {
  local status epochs
  status=$(pick default default confirmed confirmed unconfirmed)
  if [ "$status" != default ]; then
    epochs=$(epochs_of "$1" "$status")
    if [ -n "$epochs" ]; then
      echo "$(pick $epochs) $status"
      return
    fi
  fi
  echo "$DEFAULT_EPOCH_ID default"
}

# new_epoch_id: a random epoch ID. It starts with 0x08 like DEFAULT_EPOCH_ID, which is the
# prefix that fhevm expects.
new_epoch_id() {
  echo "08$(head -c 31 /dev/urandom | od -An -v -tx1 | tr -d ' \n')"
}

# key_digest FILE: the digest that the KMS takes of a public key object. It is the 32-byte
# SHAKE-256 of the PDAT_KEY domain separator followed by the object's bytes as stored in
# MinIO (hash_versioned in core/threshold-hashing/src/lib.rs, DSEP_PUBDATA_KEY).
key_digest() {
  { printf PDAT_KEY; cat "$1"; } | openssl dgst -shake256 -xoflen 32 -r | cut -d ' ' -f 1
}
