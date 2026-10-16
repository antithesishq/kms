# Shared by build.sh and push.sh. Override any of these from the environment.

ENGINE="${ENGINE:-podman}"
REG="${REG:-us-central1-docker.pkg.dev/molten-verve-216720/zama-repository}"
TAG="${TAG:-local}"

# The images the manifests reference, as ${REG}/kms/<name>:${TAG}.
IMAGES=(core-service core-service-probe core-client init-envsubst)
