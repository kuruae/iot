#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd -- "${BONUS_DIR}/.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-iot-bonus}"
GITLAB_NODEPORT_HTTP="${GITLAB_NODEPORT_HTTP:-30080}"
GITLAB_NODEPORT_SSH="${GITLAB_NODEPORT_SSH:-30022}"
GITLAB_IMAGE="${GITLAB_IMAGE:-gitlab/gitlab-ce:latest}"

ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
KUBECTL_FIELD_MANAGER="iot-bonus-installer"

PASS_FILE="${SCRIPT_DIR}/.gitlab_root_password"

# ─────────────────────────────────────────────
# 1) Cluster k3d
# ─────────────────────────────────────────────
if k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "[k3d] Cluster '$CLUSTER_NAME' déjà existant, on le réutilise."
else
  echo "[k3d] Création du cluster '$CLUSTER_NAME'..."
  k3d cluster create "$CLUSTER_NAME" --wait
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null

SERVER_NODE="k3d-${CLUSTER_NAME}-server-0"
SERVER_IP="$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$SERVER_NODE")"
if [[ -z "${SERVER_IP}" ]]; then
  echo "[docker] Impossible de récupérer l'IP du noeud '${SERVER_NODE}'." >&2
  exit 1
fi

GITLAB_EXTERNAL_URL="http://${SERVER_IP}:${GITLAB_NODEPORT_HTTP}"

# ─────────────────────────────────────────────
# 2) Namespaces
# ─────────────────────────────────────────────
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

# ─────────────────────────────────────────────
# 3) Argo CD
# ─────────────────────────────────────────────
for CRD in applicationsets.argoproj.io applications.argoproj.io; do
  kubectl get crd "$CRD" >/dev/null 2>&1 && \
    kubectl annotate crd "$CRD" kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
done

echo "[argocd] Installation/MAJ via manifest stable..."
if ! kubectl apply --server-side --field-manager="$KUBECTL_FIELD_MANAGER" -n argocd -f "$ARGOCD_INSTALL_URL"; then
  echo "[argocd] Conflits détectés -> re-apply avec --force-conflicts"
  kubectl apply --server-side --force-conflicts --field-manager="$KUBECTL_FIELD_MANAGER" -n argocd -f "$ARGOCD_INSTALL_URL"
fi

kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=300s

# ─────────────────────────────────────────────
# 4) GitLab (mono-pod, image officielle)
# ─────────────────────────────────────────────
if [[ -f "$PASS_FILE" ]]; then
  GITLAB_ROOT_PASSWORD="$(cat "$PASS_FILE")"
else
  # Alphanum uniquement (évite les soucis de sed/quoting)
  GITLAB_ROOT_PASSWORD="$(head -c 512 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 20)"
  echo "$GITLAB_ROOT_PASSWORD" > "$PASS_FILE"
  chmod 600 "$PASS_FILE" || true
fi

echo "[gitlab] Déploiement GitLab sur ${GITLAB_EXTERNAL_URL} ..."
RENDERED="$(mktemp)"
# shellcheck disable=SC2002
cat "${BONUS_DIR}/confs/gitlab/gitlab.yaml.tmpl" \
  | sed "s|__GITLAB_EXTERNAL_URL__|${GITLAB_EXTERNAL_URL}|g" \
  | sed "s|__GITLAB_ROOT_PASSWORD__|${GITLAB_ROOT_PASSWORD}|g" \
  | sed "s|__GITLAB_NODEPORT_HTTP__|${GITLAB_NODEPORT_HTTP}|g" \
  | sed "s|__GITLAB_NODEPORT_SSH__|${GITLAB_NODEPORT_SSH}|g" \
  | sed "s|__GITLAB_IMAGE__|${GITLAB_IMAGE}|g" \
  > "$RENDERED"

kubectl apply -f "$RENDERED"
rm -f "$RENDERED"

echo "[gitlab] Attente du pod gitlab-0 (peut prendre plusieurs minutes)..."
kubectl -n gitlab wait --for=condition=Ready pod/gitlab-0 --timeout=20m || true

echo "[gitlab] Attente HTTP /users/sign_in..."
gitlab_ready=false
for _ in $(seq 1 240); do
  if curl -fsS "${GITLAB_EXTERNAL_URL}/users/sign_in" >/dev/null 2>&1; then
    echo "[gitlab] OK"
    gitlab_ready=true
    break
  fi
  sleep 5
done

if [[ "$gitlab_ready" != "true" ]]; then
  echo "[gitlab] TIMEOUT: GitLab ne répond pas sur ${GITLAB_EXTERNAL_URL} après 20 minutes." >&2
  kubectl -n gitlab get pods -o wide >&2 || true
  kubectl -n gitlab logs gitlab-0 --tail=200 >&2 || true
  exit 1
fi

# ─────────────────────────────────────────────
# 5) Port-forward ArgoCD
# ─────────────────────────────────────────────
pkill -f "kubectl port-forward svc/argocd-server -n argocd" 2>/dev/null || true
kubectl port-forward svc/argocd-server -n argocd --address 0.0.0.0,:: 8080:443 >/dev/null 2>&1 &

VM_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)

echo ""
echo "========================================"
echo "GitLab URL : ${GITLAB_EXTERNAL_URL}"
echo "Login GitLab : root"
echo "Password GitLab : $(cat "$PASS_FILE")"
echo ""
echo "Argo CD : https://${VM_IP}:8080"
echo "Password admin Argo CD :"
if kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
else
  echo "(secret déjà consommé/supprimé)"
fi
echo "========================================"

echo ""
echo "Prochaines étapes (manuelles, 2 min) :"
echo "1) Ouvrir ${GITLAB_EXTERNAL_URL} et se connecter (root / password ci-dessus)."
echo "2) Créer un projet *public* (ex: iot-manifests)."
echo "3) Créer un Personal Access Token (scope: write_repository)."
echo "4) Pousser le repo d'exemple : ${BONUS_DIR}/repo"
echo "5) Appliquer l'Application ArgoCD :"
echo "   bash ${SCRIPT_DIR}/apply_argocd_app.sh <GITLAB_REPO_URL>"
echo "6) Démarrer les port-forwards (ArgoCD + app) :"
echo "   bash ${SCRIPT_DIR}/port_forwards.sh"
