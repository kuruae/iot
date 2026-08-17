#!/bin/bash

echo "[stop] Arrêt des port-forwards..."
pkill -f "port-forward svc/argocd-server" 2>/dev/null || true
pkill -f "port-forward svc/wil-playground" 2>/dev/null || true

echo "[stop] Suppression du cluster K3d..."
k3d cluster delete iot-cluster 2>/dev/null || echo "(cluster déjà supprimé)"

echo ""
echo "P3 stoppé proprement."
