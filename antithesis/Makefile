# Run from this directory (make <target>) or from the repo root (make -C antithesis <target>).
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

.PHONY: build push config driver k3s load up down test build-coverage

# Build the four KMS images into the local image store, tagged with the git
# commit (see images/build.sh).
build:
	$(HERE)images/build.sh

# Build the local-only coverage variant of core-service on top of the last build
# (images/build-coverage.sh), for local/run-local.sh. Never pushed.
build-coverage:
	$(HERE)images/build-coverage.sh

# Push the last build to the Antithesis registry.
push:
	$(HERE)images/push.sh --push

# Render config/ into build/config/ with the tag of the last build. Antithesis
# launches and local k3s deploys from there.
config:
	$(HERE)config/render.sh

# Regenerate config/manifests/41-kms-workload-tests.yaml and the client pod's test mounts from test/v1/main/.
driver:
	$(HERE)test/render-configmap.sh

# Start the local k3s node and wait until it is Ready.
k3s:
	$(HERE)local/k3s.sh

# Import every image the manifests reference into the local k3s node.
load: config
	$(HERE)local/load.sh

# Deploy the manifests to local k3s the way Antithesis does: with kapp, which
# follows their change-group ordering and waits until everything is ready.
# export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
up: config
	kapp deploy -a kms -f $(HERE)build/config/manifests --yes

# Delete everything up deployed, MinIO's volume included.
down:
	kapp delete -a kms --yes

# Run the test commands in the client pod: first keygen, every driver, recovery check.
test:
	$(HERE)local/test.sh
