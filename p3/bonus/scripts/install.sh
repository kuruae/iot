#!/bin/bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Créer le cluster K3d
k3d cluster create iot-cluster

# Namespaces
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

# Installer Argo CD
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=300s

# Installer Gitlab via Helm
helm repo add gitlab https://charts.gitlab.io
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  -n gitlab \
  -f "$SCRIPT_DIR/../confs/gitlab.yaml" \
  --timeout 600s

# Attendre Gitlab
kubectl wait --for=condition=available deployment/gitlab-webservice-default \
  -n gitlab --timeout=600s

# Exposer Gitlab
kubectl port-forward svc/gitlab-webservice-default -n gitlab 8929:8181 &

echo "Gitlab dispo sur http://localhost:8929"
echo "Password root Gitlab:"
kubectl -n gitlab get secret gitlab-gitlab-initial-root-password \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Appliquer l'application Argo CD (pointe vers Gitlab local)
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"