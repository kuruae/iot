#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-iot-bonus}"

echo "[stop] Arrêt des port-forwards..."
pkill -f "kubectl port-forward svc/argocd-server -n argocd" 2>/dev/null || true
pkill -f "kubectl port-forward svc/wil-playground -n dev" 2>/dev/null || true

echo "[stop] Suppression du cluster k3d: ${CLUSTER_NAME}"
k3d cluster delete "${CLUSTER_NAME}" 2>/dev/null || echo "(cluster déjà supprimé)"

echo "Bonus stoppé proprement."
