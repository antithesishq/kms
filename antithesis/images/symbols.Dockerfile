# Adds /symbols to a KMS image: one link per instrumented kms-* binary in
# BIN_DIR. Antithesis follows the links to the unstripped binaries and reads
# their symbols from there.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
ARG BIN_DIR
USER root
RUN set -e; mkdir /symbols; \
    for f in "${BIN_DIR}"/kms-*; do test -x "$f"; ln -s "$f" /symbols/; done; \
    ls -l /symbols
USER kms
