#!/bin/bash
set -e

echo "==> Installing K3s in controller mode..."

# Install K3s server
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address=192.168.56.110 \
  --advertise-address=192.168.56.110 \
  --node-ip=192.168.56.110 \
  --flannel-iface=eth1" sh -

# Wait for K3s to be ready
echo "==> Waiting for K3s to start..."
until kubectl get nodes 2>/dev/null | grep -q "Ready"; do
  sleep 3
done

# Share the node token so the worker can join
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
echo "==> Node token saved to /vagrant/node-token"

# Install kubectl (already bundled with K3s, just make it available for vagrant user)
mkdir -p /home/vagrant/.kube
cp /etc/rancher/k3s/k3s.yaml /home/vagrant/.kube/config
chown vagrant:vagrant /home/vagrant/.kube/config
# Fix server address in kubeconfig (uses localhost by default)
sed -i 's/127.0.0.1/192.168.56.110/' /home/vagrant/.kube/config

echo "==> Controller setup complete!"
echo "==> Cluster nodes:"
kubectl get nodes -o wide
