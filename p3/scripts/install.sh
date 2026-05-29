#!/bin/bash
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="iot-cluster"
ARGOCD_PORT_FORWARD_PATTERN="kubectl port-forward svc/argocd-server -n argocd"

# ─────────────────────────────────────────────
# 1. Cluster K3d
# ─────────────────────────────────────────────
if k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "[k3d] Cluster '$CLUSTER_NAME' déjà existant, on le réutilise."
else
  k3d cluster create "$CLUSTER_NAME"
fi

if ! kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1; then
  echo "[kubectl] Impossible de sélectionner le contexte 'k3d-${CLUSTER_NAME}'." >&2
  echo "Vérifie que le cluster k3d est bien créé et que kubeconfig est accessible." >&2
  exit 1
fi

# ─────────────────────────────────────────────
# 2. Namespaces
# ─────────────────────────────────────────────
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -

# ─────────────────────────────────────────────
# 3. Argo CD
# ─────────────────────────────────────────────
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
KUBECTL_FIELD_MANAGER="iot-p3-installer"

for CRD in applicationsets.argoproj.io applications.argoproj.io; do
  kubectl get crd "$CRD" >/dev/null 2>&1 && \
    kubectl annotate crd "$CRD" kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
done

if ! kubectl apply --server-side --field-manager="$KUBECTL_FIELD_MANAGER" \
  -n argocd -f "$ARGOCD_INSTALL_URL"; then
  echo "Conflits détectés -> re-apply avec --force-conflicts"
  kubectl apply --server-side --force-conflicts --field-manager="$KUBECTL_FIELD_MANAGER" \
    -n argocd -f "$ARGOCD_INSTALL_URL"
fi

kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=300s
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=300s

# ─────────────────────────────────────────────
# 4. Application Argo CD
# ─────────────────────────────────────────────
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"

# ─────────────────────────────────────────────
# 5. Port-forward ArgoCD (accessible depuis PC principal)
# ─────────────────────────────────────────────
pkill -f "$ARGOCD_PORT_FORWARD_PATTERN" 2>/dev/null || true
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0 8080:443 &

# ─────────────────────────────────────────────
# Résumé
# ─────────────────────────────────────────────
VM_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)

echo ""
echo "========================================"
echo " Argo CD : https://${VM_IP}:8080"
echo " Password admin Argo CD :"
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
else
  echo "(secret déjà consommé/supprimé)"
fi
echo "========================================"
