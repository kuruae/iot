#!/bin/bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="iot-cluster"
ARGOCD_PORT_FORWARD_PATTERN="kubectl port-forward svc/argocd-server -n argocd 8080:443"

# Créer le cluster K3d
if k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster k3d '$CLUSTER_NAME' déjà existant, on le réutilise."
else
  k3d cluster create "$CLUSTER_NAME"
fi

# S'assurer d'être sur le bon contexte kubectl (k3d-<cluster>)
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# Namespaces
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# Installer Argo CD
# Note: server-side apply évite l'annotation 'kubectl.kubernetes.io/last-applied-configuration'
# qui peut dépasser la limite de 256KiB sur certaines CRDs (ex: applicationsets.argoproj.io).
kubectl get crd applicationsets.argoproj.io >/dev/null 2>&1 && \
  kubectl annotate crd applicationsets.argoproj.io kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
kubectl get crd applications.argoproj.io >/dev/null 2>&1 && \
  kubectl annotate crd applications.argoproj.io kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true

ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
KUBECTL_FIELD_MANAGER="iot-p3-installer"

if ! kubectl apply --server-side --field-manager="$KUBECTL_FIELD_MANAGER" -n argocd \
  -f "$ARGOCD_INSTALL_URL"; then
  echo "Conflits détectés (Argo CD déjà présent ?) -> re-apply avec --force-conflicts"
  kubectl apply --server-side --force-conflicts --field-manager="$KUBECTL_FIELD_MANAGER" -n argocd \
    -f "$ARGOCD_INSTALL_URL"
fi

# Attendre qu'Argo CD soit prêt
kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s

# S'assurer que les CRDs Argo CD sont bien là (Application)
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=300s

# Appliquer l'application Argo CD
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"

# Exposer Argo CD
pkill -f "$ARGOCD_PORT_FORWARD_PATTERN" 2>/dev/null || true
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

echo "Argo CD dispo sur https://localhost:8080"
echo "Password admin:"
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
else
  echo "(secret 'argocd-initial-admin-secret' introuvable: déjà consommé/supprimé ?)"
fi