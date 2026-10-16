# syntax=docker/dockerfile:1

################################################################
# Stand-in for the chart's `socat` image.
#
# The kms-core chart uses `.Values.socat.image` for the
# kms-core-init-load-env init container, which only needs `envsubst` to render
# the kms-server.toml / kms-gen-keys.toml config files.
#
# `curl` is required as soon as kmsCore.thresholdMode.tls.enabled is true: the
# init container then also fetches each peer's CA certificate and this party's
# private key from the public S3 bucket (see the `kmsCoreInitEnvVars` helper in
# charts/kms-core/templates/_helpers.tpl). Without curl those fetches fail and
# the core starts with empty KMS_CA_PEM_* / KMS_KEY_PEM_* values.
#
# `socat` itself is only needed for Nitro enclave deployments, which this
# airgapped bundle does not use.
#
# Built by antithesis/images/build.sh.
################################################################
FROM cgr.dev/chainguard/glibc-dynamic:latest-dev

USER root

# gettext -> envsubst (always needed)
# curl    -> peer certificate fetch when TLS is enabled
# ca-certificates -> only used if the S3 endpoint is ever switched to https
RUN apk add --no-cache \
      gettext \
      curl \
      ca-certificates

# The chart runs this container under podSecurityContext
# runAsUser 10003 / runAsGroup 10002, matching the KMS images.
USER 10003
