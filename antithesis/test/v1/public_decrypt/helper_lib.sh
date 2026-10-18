#!/bin/sh
# Shared helpers for the public_decrypt test template: assertions, client configs, randomness.
#
# Sourced by the test commands; the helper_ prefix makes Antithesis skip this file when it
# picks commands to run.
#
# Assertions use the Antithesis fallback SDK: one JSON line per message, appended to
# $ANTITHESIS_OUTPUT_DIR/sdk.jsonl. Outside Antithesis (hand-driving with kubectl exec) they
# go to /tmp/antithesis-sdk.jsonl instead, and every evaluation is also echoed to stdout.
# Format: https://antithesis.com/docs/reference/sdk/fallback/assert/
# Every evaluation carries the guarantee and property it belongs to in its details
# ({"guarantee": "guarantee-<n>", "property": "<slug>"}, see designation_of), and every
# message is listed in antithesis/scratchbook/assertion-map.json.
#
# Checks: none of its own. The assertions are listed in the docstrings of the commands that
# evaluate them.

TEMPLATE_DIR=/opt/antithesis/test/v1/public_decrypt
CLIENT_DIR=/app/kms-core-client # config.toml is written here when the pod starts
S3_PUBLIC=http://minio:9000/kms-public

# State that the test commands share. All of them run in the kms-core-client container, so a
# directory in its /tmp is enough. The state is lost when the container restarts.
#   preproc/<key_id>  the preprocessing ID of the key (written by first_generate_key.sh)
#   epochs            one line per reshare: <epoch_id> <key_id> confirmed|unconfirmed
#   profile/<name>    this timeline's draw of a workload knob (timeline_choice)
# Losing it is harmless: the commands fall back to MinIO for the key, to the kms-init epoch,
# and to fresh draws for the knobs.
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
MSG_THREE_CORES="public decryption succeeded through three of the four cores"
MSG_RETRY="public decryption succeeded on a retry after an attempt without a verdict"
MSG_FAILOVER="public decryption succeeded after the client left out a core it could not connect to"
MSG_RECOVERY_CONNECT="every core accepts client connections within 600 s after faults stop"
MSG_RECOVERY_DECRYPT="public decryption answered by all four cores succeeds within 300 s of every core accepting connections"
MSG_RECOVERY_REJOINED="a core the client could not connect to after faults stopped accepted connections again"
MSG_RECOVERY_RETRIED="public decryption answered by all four cores succeeded after a failed first attempt once faults stopped"
MSG_RESHARED_PLAINTEXT="public decryption under a reshared epoch carries the encrypted plaintext"
MSG_RESHARE_PUBLIC_KEY="public key that every party publishes for a key is unchanged by a reshare"
MSG_RESHARE_PUBLIC_KEY_FAILED="public key read back unchanged after a reshare that ended without a verdict"
MSG_RESHARE_SOURCE_PLAINTEXT="public decryption under a reshare's source epoch carries the encrypted plaintext after the reshare"
MSG_RESHARE_SOURCE_AFTER_FAIL="public decryption under the source epoch succeeded after a reshare that ended without a verdict"
MSG_USER_PLAINTEXT="user decryption reconstructs the encrypted plaintext"
MSG_USER_RESHARED_PLAINTEXT="user decryption under a reshared epoch reconstructs the encrypted plaintext"
MSG_USER_RETRY="user decryption succeeded on a retry after an attempt without a verdict"
MSG_USER_RESHARED="user decryption succeeded under a reshared epoch"
MSG_USER_BATCH="batched user decryption succeeded"
MSG_USER_SYNC="user decryption succeeded through the sync endpoint"
MSG_USER_ALL_PARTIES="user decryption succeeded with every party's response collected"
MSG_USER_SERVER_SNS="user decryption succeeded with SnS left to the cores"
MSG_USER_NO_VERDICT="user decryption attempt ended without a verdict"

# The command an assertion lives in. Declaration and evaluation must carry the same location.
location_of() {
  case "$1" in
    "$MSG_KEYGEN") echo "$TEMPLATE_DIR/first_generate_key.sh" ;;
    "$MSG_RESHARE_RESULT" | "$MSG_RESHARE_CHAINED" | "$MSG_RESHARE_NO_VERDICT" | \
      "$MSG_RESHARE_PUBLIC_KEY" | "$MSG_RESHARE_PUBLIC_KEY_FAILED" | \
      "$MSG_RESHARE_SOURCE_PLAINTEXT" | "$MSG_RESHARE_SOURCE_AFTER_FAIL")
      echo "$TEMPLATE_DIR/anytime_reshare_key.sh" ;;
    "$MSG_USER_PLAINTEXT" | "$MSG_USER_RESHARED_PLAINTEXT" | "$MSG_USER_RETRY" | "$MSG_USER_RESHARED" | \
      "$MSG_USER_BATCH" | "$MSG_USER_SYNC" | "$MSG_USER_ALL_PARTIES" | "$MSG_USER_SERVER_SNS" | \
      "$MSG_USER_NO_VERDICT")
      echo "$TEMPLATE_DIR/parallel_driver_user_decrypt.sh" ;;
    "$MSG_RECOVERY_CONNECT" | "$MSG_RECOVERY_DECRYPT" | "$MSG_RECOVERY_REJOINED" | "$MSG_RECOVERY_RETRIED")
      echo "$TEMPLATE_DIR/eventually_recovers_after_faults.sh" ;;
    *) echo "$TEMPLATE_DIR/parallel_driver_public_decrypt.sh" ;;
  esac
}

# The guarantee and property an assertion checks, as JSON members for its details. A message
# missing here gets nulls, which assertion-map.json then has to explain.
designation_of() {
  case "$1" in
    "$MSG_PLAINTEXT" | "$MSG_UNAUTHENTICATED" | "$MSG_ALL_PARTIES" | "$MSG_SYNC" | "$MSG_BATCH" | \
      "$MSG_SERVER_SNS" | "$MSG_NO_VERDICT" | "$MSG_THREE_CORES" | "$MSG_RETRY" | "$MSG_FAILOVER")
      echo '"guarantee":"guarantee-1","property":"public-decrypt-returns-encrypted-plaintext"' ;;
    "$MSG_RECOVERY_CONNECT" | "$MSG_RECOVERY_DECRYPT" | "$MSG_RECOVERY_REJOINED" | "$MSG_RECOVERY_RETRIED")
      echo '"guarantee":"guarantee-2","property":"recovers-after-faults"' ;;
    "$MSG_RESHARED_DECRYPT" | "$MSG_RESHARE_RESULT" | "$MSG_RESHARE_CHAINED" | "$MSG_RESHARE_NO_VERDICT" | \
      "$MSG_RESHARED_PLAINTEXT" | "$MSG_RESHARE_PUBLIC_KEY" | "$MSG_RESHARE_PUBLIC_KEY_FAILED" | \
      "$MSG_RESHARE_SOURCE_PLAINTEXT" | "$MSG_RESHARE_SOURCE_AFTER_FAIL" | "$MSG_USER_RESHARED_PLAINTEXT")
      echo '"guarantee":"guarantee-3","property":"reshare-preserves-key"' ;;
    "$MSG_USER_PLAINTEXT" | "$MSG_USER_RETRY" | "$MSG_USER_RESHARED" | "$MSG_USER_BATCH" | "$MSG_USER_SYNC" | \
      "$MSG_USER_ALL_PARTIES" | "$MSG_USER_SERVER_SNS" | "$MSG_USER_NO_VERDICT")
      echo '"guarantee":"guarantee-4","property":"user-decrypt-returns-encrypted-plaintext"' ;;
    *) echo '"guarantee":null,"property":null' ;;
  esac
}

# sdk_emit HIT MUST_HIT ASSERT_TYPE DISPLAY_TYPE MESSAGE CONDITION [DETAILS_JSON]
# Declarations (HIT false) carry no details. Evaluations get the message's designation added
# at the front of DETAILS_JSON, which must be a JSON object if given.
sdk_emit() {
  local details="" rest
  if [ "$1" = true ]; then
    # DETAILS_JSON without its opening brace, or nothing for no details or {}.
    rest=${7#\{}
    [ "$rest" = "}" ] && rest=""
    if [ -n "$rest" ]; then
      details=",\"details\":{$(designation_of "$5"),$rest"
    else
      details=",\"details\":{$(designation_of "$5")}"
    fi
  fi
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
  sdk_emit false true reachability Reachable "$MSG_THREE_CORES" false
  sdk_emit false true sometimes Sometimes "$MSG_RETRY" false
  sdk_emit false true sometimes Sometimes "$MSG_FAILOVER" false
  sdk_emit false true always Always "$MSG_RECOVERY_CONNECT" false
  sdk_emit false true always Always "$MSG_RECOVERY_DECRYPT" false
  sdk_emit false true sometimes Sometimes "$MSG_RECOVERY_REJOINED" false
  sdk_emit false true sometimes Sometimes "$MSG_RECOVERY_RETRIED" false
  sdk_emit false false always AlwaysOrUnreachable "$MSG_RESHARED_PLAINTEXT" false
  sdk_emit false true always Always "$MSG_RESHARE_PUBLIC_KEY" false
  sdk_emit false true sometimes Sometimes "$MSG_RESHARE_PUBLIC_KEY_FAILED" false
  sdk_emit false true always Always "$MSG_RESHARE_SOURCE_PLAINTEXT" false
  sdk_emit false true sometimes Sometimes "$MSG_RESHARE_SOURCE_AFTER_FAIL" false
  sdk_emit false true always Always "$MSG_USER_PLAINTEXT" false
  sdk_emit false false always AlwaysOrUnreachable "$MSG_USER_RESHARED_PLAINTEXT" false
  sdk_emit false true sometimes Sometimes "$MSG_USER_RETRY" false
  sdk_emit false true sometimes Sometimes "$MSG_USER_RESHARED" false
  sdk_emit false true sometimes Sometimes "$MSG_USER_BATCH" false
  sdk_emit false true reachability Reachable "$MSG_USER_SYNC" false
  sdk_emit false true reachability Reachable "$MSG_USER_ALL_PARTIES" false
  sdk_emit false true reachability Reachable "$MSG_USER_SERVER_SNS" false
  sdk_emit false true reachability Reachable "$MSG_USER_NO_VERDICT" false
  touch "$marker"
}

# assert_always MESSAGE true|false DETAILS_JSON
assert_always() {
  echo "[assert] Always \"$1\": $2"
  sdk_emit true true always Always "$1" "$2" "$3"
}

# assert_always_or_unreachable MESSAGE true|false DETAILS_JSON: an Always that does not fail
# when it is never evaluated. Used where a Reachable already demands that the case happens.
assert_always_or_unreachable() {
  echo "[assert] AlwaysOrUnreachable \"$1\": $2"
  sdk_emit true false always AlwaysOrUnreachable "$1" "$2" "$3"
}

# assert_sometimes MESSAGE true|false DETAILS_JSON
assert_sometimes() {
  echo "[assert] Sometimes \"$1\": $2"
  sdk_emit true true sometimes Sometimes "$1" "$2" "$3"
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

# now_s: whole seconds since boot. Durations are measured with it rather than the wall clock,
# which clock faults move.
now_s() {
  cut -d. -f1 /proc/uptime
}

# chance PERCENT: succeeds with probability PERCENT/100.
chance() {
  [ "$(rand_below 100)" -lt "$1" ]
}

# timeline_choice NAME OPTION...: one of the OPTIONs, drawn on the first call in a timeline
# and then kept, so that each timeline leans its own way (swarm testing). Concurrent first
# calls can draw different values; the first one stored wins.
timeline_choice() {
  local name=$1 file
  shift
  file="$STATE_DIR/profile/$name"
  if [ ! -s "$file" ]; then
    mkdir -p "$STATE_DIR/profile"
    pick "$@" >"$file.$$"
    mv -n "$file.$$" "$file"
    rm -f "$file.$$"
  fi
  cat "$file"
}

# write_client_config LEFT_OUT: write ./config.toml for kms-core-client. LEFT_OUT is none for
# the pod's own config (all four cores), or a party ID to leave that core out. The CLI
# connects to every core in its config before it sends a request, so a three-core config is
# how a client keeps decrypting while one core does not accept connections. num_parties = 4
# keeps the party IDs and the threshold those of the four-party deployment.
write_client_config() {
  if [ "$1" = none ]; then
    cp "$CLIENT_DIR/config.toml" config.toml
    return
  fi
  awk -v skip="$1" '
    function flush() {
      if (block != "" && !drop) printf "%s", block
      block = ""
      drop = 0
    }
    /^\[\[cores\]\]/ {
      flush()
      if (!added) { print "num_parties = 4"; added = 1 }
      in_cores = 1
    }
    in_cores {
      block = block $0 "\n"
      if ($0 ~ "^party_id *= *" skip " *$") drop = 1
      next
    }
    { print }
    END { flush() }
  ' "$CLIENT_DIR/config.toml" >config.toml
}

# cli_connected FILE: whether the kms-core-client run logged in FILE (run with -l) connected
# to every core in its config. It connects to them one by one before sending anything.
cli_connected() {
  grep -q 'Threshold Client setup done' "$1"
}

# cli_unreached_party FILE: the party ID of the core that a run which did not get past
# connecting was connecting to when it failed or was stopped. Fails when it never started
# connecting (e.g. it could not read the verification keys from MinIO).
cli_unreached_party() {
  local party
  party=$(sed -n 's/.*Connecting to party \([0-9]*\) via URL.*/\1/p' "$1" | tail -n 1)
  [ -n "$party" ] || return 1
  echo "$party"
}

# public_decrypt_wrong_result FILE: print the first error in FILE that the CLI raises only
# when a validly signed response carries a wrong plaintext, a wrong plaintext count or type,
# or a wrong request ID. Fails when there is none. Sources: the plaintext check in
# core-client/src/decrypt.rs and validate_public_decrypt_responses in
# core/service/src/engine/validation_non_wasm.rs.
public_decrypt_wrong_result() {
  grep -m 1 \
    -e 'decryption result mismatch' \
    -e 'Cannot find public decryption pivot' \
    -e 'Not enough agreeing public decryption responses' \
    -e 'The number of ciphertexts in the public decryption response is wrong' \
    -e 'Plaintext type mismatch in public decryption response' \
    -e 'The public decryption response is not linked to the correct public decryption request' \
    -e 'Request ID is not set in public decryption response' \
    "$1"
}

# public_decrypt_unauthenticated FILE: print the CLI's error for too few responses that pass
# authentication. A response that fails authentication never comes from a correct party; one
# case is a response for another request, whose signature does not cover this request's
# handles.
public_decrypt_unauthenticated() {
  grep -m 1 'Not enough authenticated public decryption responses' "$1"
}

# workload_key_id: the key that first_generate_key.sh generated in this timeline, or, when
# that record is lost, a key that party 1 has published.
workload_key_id() {
  local keys
  keys=$(ls "$STATE_DIR/preproc" 2>/dev/null)
  if [ -n "$keys" ]; then
    pick $keys
    return
  fi
  find_key_id
}

# fetch_public OBJECT OUT: download OBJECT (a path in the kms-public bucket) to OUT and print
# ok, missing (MinIO answered 404) or unread (anything else, e.g. a network fault). Bounded,
# so a partition from MinIO costs at most about a minute.
fetch_public() {
  if wget -S -q -O "$2" --timeout=20 --tries=3 "$S3_PUBLIC/$1" 2>"$2.hdr"; then
    echo ok
  elif grep -q 'HTTP/[0-9.]* 404' "$2.hdr"; then
    echo missing
  else
    echo unread
  fi
}

# public_key_digests KEY_ID TAG: one word per party, p<i>=<digest>, p<i>=missing or
# p<i>=unread, for the PublicKey object that party i publishes for KEY_ID. TAG names the
# downloaded files, so two reads in one directory do not clash.
public_key_digests() {
  local p out
  for p in 1 2 3 4; do
    out=pk-$2-p$p.bin
    case $(fetch_public "PUB-p$p/PublicKey/$1" "$out") in
      ok) printf 'p%s=%s ' "$p" "$(key_digest "$out")" ;;
      missing) printf 'p%s=missing ' "$p" ;;
      *) printf 'p%s=unread ' "$p" ;;
    esac
  done
}

# user_decrypt_wrong_result FILE: print the CLI's error for authenticated user-decryption
# shares that reconstructed a plaintext other than the encrypted one (reconstruct_user_decrypt
# in core-client/src/decrypt.rs). Fails when there is none. Too few responses, failed
# authentication and failed reconstruction are errors, not wrong results.
user_decrypt_wrong_result() {
  grep -m 1 'user decryption result mismatch' "$1"
}
