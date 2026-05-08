#!/bin/bash
set -e

echo "==> Waiting for node-token from controller..."
until [ -f /vagrant/node-token ]; do
  sleep 3
done

NODE_TOKEN=$(cat /vagrant/node-token)
SERVER_IP="192.168.56.110"

echo "==> Installing K3s in agent mode..."

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent \
  --server=https://${SERVER_IP}:6443 \
  --token=${NODE_TOKEN} \
  --node-ip=192.168.56.111 \
  --flannel-iface=eth1" sh -

echo "==> Agent setup complete! Worker joined the cluster."
