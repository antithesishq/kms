# Adds Python and the Antithesis Python SDK to the core-client image, so the
# Python test commands in antithesis/test/v1/main/ can run in its container.
# grpcio lets the drivers call result RPCs that kms-core-client has no command
# for. Versions are pinned so two builds of one commit get the same packages.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
RUN apk add --no-cache python3 py3-pip && \
    pip install --no-cache-dir --break-system-packages --root-user-action=ignore \
        antithesis==0.4.0 grpcio==1.84.0 && \
    python3 -c "import antithesis.assertions, antithesis.random, grpc"
USER kms
