#!/bin/bash
set -euo pipefail

echo "[pf] Arrêt des port-forwards existants..."
pkill -f "kubectl port-forward" 2>/dev/null || true

# 1. Forward ArgoCD
echo "[pf] ArgoCD -> https://<vm-ip>:8080"
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0,:: 8080:443 >/dev/null 2>&1 &

# 2. Forward GitLab (Added this so you can log in!)
echo "[pf] GitLab -> http://<vm-ip>:30080"
kubectl port-forward svc/gitlab-web -n gitlab --address 0.0.0.0,:: 30080:80 >/dev/null 2>&1 &

# 3. Check if App exists; if not, forward it anyway in the background without blocking
echo "[pf] Configuration du port-forward pour l'application..."
kubectl port-forward svc/wil-playground -n dev --address 0.0.0.0,:: 8888:8888 >/dev/null 2>&1 &

echo "[pf] OK ! Tunnels initialisés."
