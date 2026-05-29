#!/bin/bash
set -euo pipefail

echo "[pf] Arrêt des port-forwards existants..."
pkill -f "kubectl port-forward svc/argocd-server -n argocd" 2>/dev/null || true
pkill -f "kubectl port-forward svc/wil-playground -n dev" 2>/dev/null || true

echo "[pf] ArgoCD -> https://<vm-ip>:8080"
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0,:: 8080:443 >/dev/null 2>&1 &

echo "[pf] Attente de svc/wil-playground dans dev..."
for _ in $(seq 1 120); do
  if kubectl -n dev get svc wil-playground >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

echo "[pf] App -> http://<vm-ip>:8888 (et curl http://localhost:8888/)"
kubectl port-forward svc/wil-playground -n dev --address 0.0.0.0,:: 8888:8888 >/dev/null 2>&1 &

echo "[pf] Attente de l'ouverture du port 8888..."
for _ in $(seq 1 30); do
  if ss -ltn 2>/dev/null | grep -qE '(:|\])8888\b'; then
    break
  fi
  sleep 1
done

echo "[pf] OK"
