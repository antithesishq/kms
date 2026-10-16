#!/bin/sh
# Generates the FHE key that the drivers decrypt under and reshare. kms-init creates only the
# MPC context and epoch, so a fresh cluster has no key.
#
# Antithesis runs this once per timeline, before any driver and with no faults. The default
# is insecure keygen because it is fast. Set KMS_WORKLOAD_KEYGEN=secure to run the real
# distributed keygen instead.
. "$(dirname "$0")/helper_lib.sh"
declare_catalog
enter_scratch_dir

if [ "${KMS_WORKLOAD_KEYGEN:-insecure}" = secure ]; then
  preproc_cmd=preproc-key-gen
  keygen_cmd=key-gen
else
  preproc_cmd=insecure-preproc-key-gen
  keygen_cmd=insecure-key-gen
fi

# --max-iter counts 0.5 s result polls; keygen can take minutes.
attempt=1
while [ "$attempt" -le 5 ]; do
  echo "attempt $attempt: kms-core-client $preproc_cmd, then $keygen_cmd"
  if kms-core-client -f config.toml --max-iter 1200 "$preproc_cmd" >preproc.out 2>&1 &&
    preproc_id=$(request_id_from preproc.out) &&
    kms-core-client -f config.toml --max-iter 1200 "$keygen_cmd" --preproc-id "$preproc_id" >keygen.out 2>&1 &&
    key_id=$(request_id_from keygen.out); then
    echo "generated key $key_id (preproc $preproc_id)"
    record_preproc "$key_id" "$preproc_id" # anytime_reshare_key.sh needs it
    assert_reachable "$MSG_KEYGEN" "{\"key_id\":\"$key_id\",\"keygen\":\"$keygen_cmd\",\"attempt\":$attempt}"
    exit 0
  fi
  tail -n 5 preproc.out keygen.out 2>/dev/null
  attempt=$((attempt + 1))
  sleep 10
done
echo "keygen failed 5 times"
exit 1
