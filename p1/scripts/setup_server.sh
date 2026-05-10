#!/bin/sh
set -e

echo "==> Installing K3s in controller mode..."

apk add --no-cache curl

export INSTALL_K3S_VERSION="v1.31.4+k3s1"
export K3S_TOKEN="secrettoken"

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

mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
sed -i 's/127.0.0.1/192.168.56.110/' /home/vagrant/.kube/config

echo "==> Controller setup complete!"
k3s kubectl get nodes -o wide
