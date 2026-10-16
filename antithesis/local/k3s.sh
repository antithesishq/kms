#!/usr/bin/env bash
#=============================================================================
# Starts the local k3s node and waits until it is Ready.
#
#   antithesis/local/k3s.sh
#
# Uses the k3s systemd service if there is one (the get.k3s.io installer
# creates it). Otherwise runs the k3s binary as a transient systemd unit,
# k3s-antithesis, so nothing gets installed:
#   logs:  journalctl -u k3s-antithesis
#   stop:  sudo systemctl stop k3s-antithesis
# Either way the kubeconfig is /etc/rancher/k3s/k3s.yaml.
#=============================================================================
set -euo pipefail

UNIT=k3s-antithesis

if systemctl cat k3s.service >/dev/null 2>&1; then
    echo "Starting the k3s service"
    sudo systemctl start k3s
elif systemctl is-active --quiet "${UNIT}"; then
    echo "${UNIT} is already running"
else
    k3s_bin="$(command -v k3s)" || { echo "ERROR: k3s not found in PATH" >&2; exit 1; }
    echo "Starting ${k3s_bin} as the transient unit ${UNIT}"
    # Antithesis' cluster runs without Traefik, ServiceLB and metrics-server.
    sudo systemd-run --unit="${UNIT}" --collect \
        "${k3s_bin}" server \
        --disable traefik --disable servicelb --disable metrics-server \
        --write-kubeconfig-mode 644
fi

echo "Waiting for the node to be Ready"
for _ in $(seq 60); do
    if sudo k3s kubectl wait --for=condition=Ready node --all --timeout=5s >/dev/null 2>&1; then
        sudo k3s kubectl get nodes
        exit 0
    fi
    sleep 5
done
echo "ERROR: k3s did not become Ready within 5 minutes." >&2
exit 1
