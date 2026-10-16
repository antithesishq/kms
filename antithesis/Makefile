# Run from this directory (make <target>) or from the repo root (make -C antithesis <target>).
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: build push driver

# Build the four KMS images into the local image store.
build:
	$(HERE)images/build.sh

# Push them to the Antithesis registry as :local.
push:
	$(HERE)images/push.sh --push

# Regenerate config/manifests/41-kms-workload-tests.yaml from test/v1/.
driver:
	$(HERE)test/render-configmap.sh
