# Zama's rust-golden-image utilizes the AWS-LC crypto library. AWS-LC seeds its random generator 
# from CPU timing jitter by default. Under the Antithesis deterministic clock, the jitter 
# self-tests fail and AWS-LC aborts, crashing the test. Setting the following flag forces a build
# without jitter entropy and AWS-LC seeds from the OS instead.
ARG ZAMA_GOLDEN_IMAGE=localhost/kms-antithesis/zama-golden:local
FROM ${ZAMA_GOLDEN_IMAGE}
ENV AWS_LC_SYS_NO_JITTER_ENTROPY=1
