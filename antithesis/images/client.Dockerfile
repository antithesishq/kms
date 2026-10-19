# Adds Python and the Antithesis Python SDK to the core-client image. The test commands in
# ../test/v1/ are Python scripts, and they reach the pod from a ConfigMap rather than this image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}
USER root
# python3 is a virtual package in Wolfi with one provider per Python version, so name one.
RUN apk add --no-cache python-3.13 py3.13-pip && \
    python3 -m pip install --no-cache-dir --break-system-packages antithesis==0.4.0 && \
    python3 -c 'import antithesis.assertions, antithesis.catalog, antithesis.random'
# The test commands import helper_lib.py from the template directory, where Antithesis looks
# for test commands. Keep __pycache__ out of it.
ENV PYTHONDONTWRITEBYTECODE=1
USER kms
