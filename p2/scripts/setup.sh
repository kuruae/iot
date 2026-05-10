#!/bin/sh
set -e

echo "==> Installing K3s in server mode..."

apk add --no-cache curl

export INSTALL_K3S_VERSION="v1.31.4+k3s1"
export K3S_TOKEN="IoT42SecretToken"

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=192.168.56.110 \
  --advertise-address=192.168.56.110 \
  --node-ip=192.168.56.110 \
  --flannel-iface=eth1 \
  --write-kubeconfig-mode=644" sh -

echo "==> Waiting for node to be Ready..."
until k3s kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

echo "==> K3s ready! Apply manifests with:"
echo "    vagrant ssh haboudaS -- sudo kubectl apply -f /tmp/confs/"
