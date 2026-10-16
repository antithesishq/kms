# Run from this directory (make <target>) or from the repo root (make -C antithesis <target>).
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: build push driver k3s load up down test

# Build the four KMS images into the local image store.
build:
	$(HERE)images/build.sh

# Push them to the Antithesis registry as :local.
push:
	$(HERE)images/push.sh --push

# Regenerate config/manifests/41-kms-workload-tests.yaml from test/v1/.
driver:
	$(HERE)test/render-configmap.sh

# Start the local k3s node and wait until it is Ready.
k3s:
	$(HERE)local/k3s.sh

# Import every image the manifests reference into the local k3s node.
load:
	$(HERE)local/load.sh

# Deploy the manifests to local k3s the way Antithesis does: with kapp, which
# follows their change-group ordering and waits until everything is ready.
# export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
up:
	kapp deploy -a kms -f $(HERE)config/manifests --yes

# Delete everything up deployed, MinIO's volume included.
down:
	kapp delete -a kms --yes

# Run the test commands in the client pod: keygen, driver, reshare, driver.
test:
	$(HERE)local/test.sh
