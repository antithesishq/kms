#!/bin/sh
# Checks that once faults stop, every core accepts connections again and the cluster then
# serves a public decryption that all four cores answer.
#
# Faults. Antithesis stops all faults when an eventually_ command starts, kills the other
# running commands, and runs nothing alongside it (Test Composer reference, "Eventually
# command": "All faults stop across all containers when an eventually command starts"). This
# command also opens a quiet window with $ANTITHESIS_STOP_FAULTS that covers its whole check
# (the documented way to pause faults from a workload), so the check holds even if the
# launcher's pod-fault injector did not follow the eventually phase. A pod deleted just before
# faults stopped is recreated by its StatefulSet; nothing here restarts anything.
#
# Probe. kms-core-client -a public-decrypt with the pod's own four-core config: a fresh value
# of a random type under the workload's key and the kms-init epoch (so a failed reshare can't
# make it fail), through the async endpoint with result polling or through --sync. -a makes
# the CLI wait for all four cores' responses and check each of them, so a success means every
# core took part. Each attempt is a new request with a new random request ID; an attempt that
# fails has an unknown outcome on the cores, which does not matter because nothing depends on
# it. Attempts are bounded by 90 s (and by the time left in the window) and are 10 s apart.
#
# Windows (Guarantee 2 as written in guarantees.md). The CLI connects to every core before it
# sends anything and logs (-l) when it has, which is the client's view of "every core accepts
# connections". That must happen within 600 s of this command's start (Kubernetes' restart
# back-off cap of 300 s plus boot and readiness). From the start of the first attempt that got
# that far, a probe must succeed within 300 s (the deployment's MPC network_timeout). A core
# still down when its window ends is a failure, and so is a cluster that accepts connections
# but cannot answer. Durations use seconds since boot (/proc/uptime), which clock faults don't
# move.
#
# Checks:
# - Always (Guarantee 2): every core accepts client connections within 600 s after faults stop.
# - Always (Guarantee 2): a public decryption answered by all four cores succeeds within 300 s
#   of every core accepting connections.
# - Sometimes (Guarantee 2): a core the client could not connect to after faults stopped
#   accepted connections again.
# - Sometimes (Guarantee 2): a decryption answered by all four cores succeeded after the first
#   attempt failed.
# - Always (Guarantee 1, shared with parallel_driver_public_decrypt.sh): a decryption the CLI
#   accepts carries the encrypted plaintext.
# - Unreachable (Guarantee 1, shared): a response from a KMS party fails authentication.
. "$(dirname "$0")/helper_lib.sh"
declare_catalog

CONNECT_BOUND=600
DECRYPT_BOUND=300
ATTEMPT_LIMIT=90
PAUSE=10

if [ -n "${ANTITHESIS_STOP_FAULTS:-}" ]; then
  "$ANTITHESIS_STOP_FAULTS" $((CONNECT_BOUND + DECRYPT_BOUND + ATTEMPT_LIMIT + 30)) ||
    echo "ANTITHESIS_STOP_FAULTS failed; relying on the eventually phase"
fi

start=$(now_s)

# The key: the one first_generate_key.sh made, or one party 1 published. MinIO is never
# pod-faulted, but give its network a moment to settle.
tries=0
until key_id=$(workload_key_id); do
  tries=$((tries + 1))
  if [ "$tries" -ge 6 ]; then
    echo "no FHE key found; first_generate_key.sh did not produce one, so nothing to probe"
    exit 0
  fi
  sleep "$PAUSE"
done

enter_scratch_dir
write_client_config none

attempt=0
failed=0
ok=false
connected_at=""
refused_before_connect=false
unreached=""
wrong=false
last="\"exit_code\":null"
while true; do
  t=$(now_s)
  if [ -z "$connected_at" ]; then
    end=$((start + CONNECT_BOUND))
  else
    end=$((connected_at + DECRYPT_BOUND))
  fi
  left=$((end - t))
  [ "$left" -gt 0 ] || break
  limit=$ATTEMPT_LIMIT
  [ "$left" -lt "$limit" ] && limit=$left

  attempt=$((attempt + 1))
  data_type=$(pick ebool euint8 euint16 euint32 euint64 euint128 euint160 euint256)
  value=$(pick_value "$data_type")
  batch=$(pick 1 1 2)
  sync=$(pick false true)
  # --max-iter counts 0.5 s result polls per core.
  set -- -l -f config.toml --max-iter 60 -a public-decrypt from-args --to-encrypt "0x$value" \
    --data-type "$data_type" --key-id "$key_id" --batch-size "$batch"
  [ "$sync" = true ] && set -- "$@" --sync
  echo "attempt $attempt at +$((t - start)) s (limit $limit s): kms-core-client $*"
  timeout "$limit" kms-core-client "$@" >cli.out 2>&1
  rc=$?

  connected=false
  if cli_connected cli.out; then
    connected=true
    [ -n "$connected_at" ] || connected_at=$t
  fi
  last="\"attempt\":$attempt,\"started_after_s\":$((t - start)),\"data_type\":\"$data_type\",\"value_hex\":\"$value\",\"batch\":$batch,\"sync\":$sync,\"key_id\":\"$key_id\",\"connected\":$connected,\"exit_code\":$rc"

  if [ "$rc" -eq 0 ]; then
    ok=true
    details="{$last,\"request_id\":\"$(request_id_from cli.out)\",\"command\":\"eventually_recovers_after_faults.sh\"}"
    assert_always "$MSG_PLAINTEXT" true "$details"
    break
  fi

  if err=$(public_decrypt_wrong_result cli.out); then
    wrong=true
    assert_always "$MSG_PLAINTEXT" false "{$last,\"error\":\"$(json_str "$err")\",\"command\":\"eventually_recovers_after_faults.sh\"}"
    cat cli.out
  elif err=$(public_decrypt_unauthenticated cli.out); then
    wrong=true
    assert_unreachable "$MSG_UNAUTHENTICATED" "{$last,\"error\":\"$(json_str "$err")\",\"command\":\"eventually_recovers_after_faults.sh\"}"
    cat cli.out
  elif [ "$rc" -eq 2 ]; then
    echo "kms-core-client rejected the arguments"
    cat cli.out
    exit 1
  fi

  failed=$((failed + 1))
  last="$last,\"error\":\"$(json_str "$(tail -n 2 cli.out)")\""
  if [ "$connected" = false ] && party=$(cli_unreached_party cli.out); then
    unreached=$party
    [ -n "$connected_at" ] || refused_before_connect=true
    echo "could not connect to party $party"
  fi
  tail -n 3 cli.out | cut -c 1-400
  sleep "$PAUSE"
done

now=$(now_s)
summary="\"attempts\":$attempt,\"failed_attempts\":$failed,\"elapsed_s\":$((now - start)),\"last_unreached_party\":\"$unreached\",\"last_attempt\":{$last}"
if [ -z "$connected_at" ]; then
  assert_always "$MSG_RECOVERY_CONNECT" false "{$summary,\"connect_bound_s\":$CONNECT_BOUND}"
else
  connect_wait=$((connected_at - start))
  assert_always "$MSG_RECOVERY_CONNECT" true "{$summary,\"connect_wait_s\":$connect_wait}"
  assert_always "$MSG_RECOVERY_DECRYPT" "$ok" \
    "{$summary,\"connect_wait_s\":$connect_wait,\"decrypt_wait_s\":$((now - connected_at)),\"decrypt_bound_s\":$DECRYPT_BOUND}"
fi
# Hard cases this run met, judged by whether it got through them.
if [ "$refused_before_connect" = true ]; then
  rejoined=false
  [ -n "$connected_at" ] && rejoined=true
  assert_sometimes "$MSG_RECOVERY_REJOINED" "$rejoined" "{$summary}"
fi
if [ "$failed" -gt 0 ]; then
  assert_sometimes "$MSG_RECOVERY_RETRIED" "$ok" "{$summary}"
fi

if [ -n "$connected_at" ]; then
  echo "recovery: all cores accepted connections after $((connected_at - start)) s; decryption ok=$ok after $attempt attempt(s)"
else
  echo "recovery: not every core accepted connections within $CONNECT_BOUND s ($attempt attempts)"
fi
if [ "$ok" = false ] || [ "$wrong" = true ]; then exit 1; fi
exit 0
