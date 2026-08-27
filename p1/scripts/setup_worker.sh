#!/bin/sh
set -e

echo "==> Installing K3s in agent mode..."

# Replace your current 'apk add' with this:
apk add --no-cache curl iptables ip6tables cgroups


export INSTALL_K3S_VERSION="v1.31.4+k3s1"
export K3S_TOKEN="secrettoken"
export K3S_URL="https://192.168.56.110:6443"

rc-update add cgroups boot
rc-service cgroups start

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --node-ip=192.168.56.111 \
  --flannel-iface=eth1" sh -

echo "==> Agent setup complete! Worker joined the cluster."
