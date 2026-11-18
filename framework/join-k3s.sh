#!/usr/bin/env bash
# Joins framework (the laptop) to the homelab k3s cluster as an agent.
#
# framework leaves the network. It joins untainted, so anything can be
# scheduled there, smelt sandboxes included (a sandbox's local-path volume
# pins it to the laptop, so it's unavailable while the laptop is away).
# Longhorn runs here so pods can attach Longhorn volumes, but the node gets no
# Longhorn disk and holds no replicas (longhorn-storage/nodes.tf).
#
# Run on framework:
#   ./join-k3s.sh
# It asks for the cluster join token, which only homelab has:
#   sudo cat /var/lib/rancher/k3s/server/node-token     (on homelab)
# or pass it as K3S_TOKEN=... in the environment. It isn't stored in this repo.
#
# Optional environment:
#   NODE_IP=192.168.8.x   the LAN address to register with, if the laptop has
#                         more than one interface (wifi + a dock).
#
# The installer enables k3s-agent at boot; away from home it just retries,
# and rejoins when it's back. Before leaving, from any machine with kubectl:
#   kubectl drain framework --ignore-daemonsets --delete-emptydir-data
# and when back:
#   kubectl uncordon framework

set -euo pipefail

SERVER_URL="https://192.168.8.130:6443" # homelab, as the other agents use
K3S_VERSION="v1.34.6+k3s1"              # match the cluster
NODE_NAME="framework"

if ! curl -sk --max-time 5 "${SERVER_URL}/ping" >/dev/null; then
  echo "Can't reach the k3s server at ${SERVER_URL}: is this machine on the home network?" >&2
  exit 1
fi

if [[ -z "${K3S_TOKEN:-}" ]]; then
  read -rsp "k3s join token (from homelab: sudo cat /var/lib/rancher/k3s/server/node-token): " K3S_TOKEN
  echo
fi
if [[ -z "${K3S_TOKEN}" ]]; then
  echo "No token given." >&2
  exit 1
fi

agent_args=(agent --node-name "${NODE_NAME}")
if [[ -n "${NODE_IP:-}" ]]; then
  agent_args+=(--node-ip "${NODE_IP}")
fi

curl -sfL https://get.k3s.io |
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
    K3S_URL="${SERVER_URL}" \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -s - "${agent_args[@]}"

cat <<EOF

k3s-agent installed. Check from a machine with kubectl:
  kubectl get node ${NODE_NAME} -o wide
EOF
