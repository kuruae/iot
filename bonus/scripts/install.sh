#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

CLUSTER_NAME="iot-cluster"
GITLAB_NAMESPACE="gitlab"
ARGOCD_NAMESPACE="argocd"
DEV_NAMESPACE="dev"
GITLAB_PORT="8929"
ARGOCD_PORT="8080"
GITLAB_REPO_NAME="habouda_iot"

wait_for_port() {
  local host="$1" port="$2" timeout_s="$3"
  local start
  start=$(date +%s)
  while true; do
    if (echo >/dev/tcp/${host}/${port}) >/dev/null 2>&1; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout_s" ]; then
      return 1
    fi
    sleep 2
  done
}

wait_for_secret() {
  local ns="$1" name="$2" key="$3" timeout_s="$4"
  local start
  start=$(date +%s)
  while true; do
    if kubectl -n "$ns" get secret "$name" -o jsonpath="{.data.${key}}" >/dev/null 2>&1; then
      return 0
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout_s" ]; then
      return 1
    fi
    sleep 5
  done
}

wait_for_job_complete() {
  local ns="$1" selector="$2" timeout_s="$3"
  local start
  start=$(date +%s)
  while true; do
    out=$(kubectl -n "$ns" get jobs -l "$selector" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.succeeded}{"\t"}{.status.failed}{"\n"}{end}' 2>/dev/null || true)

    if [ -n "$out" ]; then
      rc=0
      echo "$out" | awk -F'\t' 'NF>=2 && $2+0 >= 1 {ok=1} NF>=3 && $3+0 >= 1 {fail=1} END{ if (fail) exit 2; if (ok) exit 0; exit 1 }' || rc=$?
      if [ "$rc" -eq 0 ]; then
        return 0
      fi
      if [ "$rc" -eq 2 ]; then
        echo "[ERREUR] Un job ($selector) a echoue."
        kubectl -n "$ns" get jobs -l "$selector" || true
        return 1
      fi
    fi

    if [ $(( $(date +%s) - start )) -ge "$timeout_s" ]; then
      return 1
    fi
    sleep 10
  done
}

wait_for_pods_ready() {
  local ns="$1" selector="$2" timeout_s="$3"
  local start
  start=$(date +%s)
  while true; do
    # Fails fast on image pulls to avoid waiting 30min for nothing.
    if kubectl -n "$ns" get pods -l "$selector" --no-headers 2>/dev/null \
      | awk '{print $3}' | grep -Eq 'ImagePullBackOff|ErrImagePull'; then
      echo "[ERREUR] ImagePullBackOff detecte sur pods ($selector)."
      kubectl -n "$ns" get pods -l "$selector" || true
      kubectl -n "$ns" describe pod -l "$selector" | sed -n '1,220p' || true
      return 1
    fi

    if kubectl -n "$ns" get pods -l "$selector" --no-headers 2>/dev/null | grep -q .; then
      if kubectl wait --for=condition=ready pod -l "$selector" -n "$ns" --timeout=60s >/dev/null 2>&1; then
        return 0
      fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout_s" ]; then
      return 1
    fi
    sleep 10
  done
}

fail_on_image_pull_errors() {
  local ns="$1"
  if kubectl -n "$ns" get pods --no-headers 2>/dev/null | awk '{print $3}' | grep -Eq 'ImagePullBackOff|ErrImagePull'; then
    echo "[ERREUR] ImagePullBackOff/ErrImagePull detecte dans le namespace '$ns'."
    kubectl -n "$ns" get pods || true
    echo "Pour debug: kubectl -n $ns describe pod <pod>"
    exit 1
  fi
}

# ─────────────────────────────────────────────
# 1. Cluster K3d
# ─────────────────────────────────────────────
if k3d cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "[k3d] Cluster '$CLUSTER_NAME' déjà existant, on le réutilise."
else
  k3d cluster create "$CLUSTER_NAME"
fi

kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true

# ─────────────────────────────────────────────
# 2. Namespaces
# ─────────────────────────────────────────────
for NS in "$ARGOCD_NAMESPACE" "$DEV_NAMESPACE" "$GITLAB_NAMESPACE"; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
done

# ─────────────────────────────────────────────
# 3. Argo CD
# ─────────────────────────────────────────────
echo "[argocd] Installation d'Argo CD..."
ARGOCD_INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
KUBECTL_FIELD_MANAGER="iot-bonus-installer"

for CRD in applicationsets.argoproj.io applications.argoproj.io; do
  kubectl get crd "$CRD" >/dev/null 2>&1 && \
    kubectl annotate crd "$CRD" kubectl.kubernetes.io/last-applied-configuration- >/dev/null 2>&1 || true
done

if ! kubectl apply --server-side --field-manager="$KUBECTL_FIELD_MANAGER" \
  -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_URL"; then
  kubectl apply --server-side --force-conflicts --field-manager="$KUBECTL_FIELD_MANAGER" \
    -n "$ARGOCD_NAMESPACE" -f "$ARGOCD_INSTALL_URL"
fi

kubectl wait --for=condition=available deployment/argocd-server \
  -n "$ARGOCD_NAMESPACE" --timeout=300s
kubectl wait --for=condition=established crd/applications.argoproj.io --timeout=300s
echo "[argocd] Argo CD prêt."

# ─────────────────────────────────────────────
# 4. GitLab via Helm (version 7.x, bundled PostgreSQL/Redis)
# ─────────────────────────────────────────────
echo "[gitlab] Installation de GitLab via Helm (5-10 min)..."
helm repo add gitlab https://charts.gitlab.io 2>/dev/null || true
helm repo update

helm upgrade --install gitlab gitlab/gitlab \
  -n "$GITLAB_NAMESPACE" \
  -f "$SCRIPT_DIR/../confs/gitlab.yaml" \
  --version "7.11.10" \
  --timeout 1800s

echo "[gitlab] Attente que GitLab demarre (peut prendre 15-30 min sur une petite VM)..."
# Si une image ne peut pas etre telechargee (souvent docker.io bloque), inutile d'attendre.
fail_on_image_pull_errors "$GITLAB_NAMESPACE"
# 'Available' sur le webservice est souvent un faux-negatif tant que migrations/sidekiq tournent.
wait_for_pods_ready "$GITLAB_NAMESPACE" "app=webservice" 1800 || {
  echo "[ERREUR] Timeout pods webservice GitLab."
  kubectl -n "$GITLAB_NAMESPACE" get pods || true
  exit 1
}
wait_for_job_complete "$GITLAB_NAMESPACE" "app=migrations" 1800 || {
  echo "[ERREUR] Timeout migrations GitLab."
  echo "Debug: kubectl -n gitlab get pods,job && kubectl -n gitlab logs job/<gitlab-migrations-...>"
  exit 1
}
echo "[gitlab] Pods webservice prets + migrations terminees."

# ─────────────────────────────────────────────
# 5. Récupérer le mot de passe root généré par GitLab
# ─────────────────────────────────────────────
echo "[gitlab] Récupération du mot de passe root..."
if ! wait_for_secret "$GITLAB_NAMESPACE" "gitlab-gitlab-initial-root-password" "password" 300; then
  echo "[ERREUR] Secret du mot de passe root introuvable (gitlab-gitlab-initial-root-password)."
  kubectl -n "$GITLAB_NAMESPACE" get secrets | sed -n '1,50p' || true
  exit 1
fi
GITLAB_ROOT_PASSWORD=$(kubectl -n "$GITLAB_NAMESPACE" \
  get secret gitlab-gitlab-initial-root-password \
  -o jsonpath="{.data.password}" | base64 -d)
echo "[gitlab] Mot de passe root récupéré."

# ─────────────────────────────────────────────
# 6. Port-forward GitLab
# ─────────────────────────────────────────────
pkill -f "port-forward svc/gitlab-webservice-default" 2>/dev/null || true
kubectl port-forward svc/gitlab-webservice-default \
  -n "$GITLAB_NAMESPACE" --address 0.0.0.0 "${GITLAB_PORT}:8181" &

echo "[gitlab] Attente que le port-forward soit actif..."
if ! wait_for_port 127.0.0.1 "$GITLAB_PORT" 60; then
  echo "[ERREUR] Port-forward GitLab non actif."
  exit 1
fi

# ─────────────────────────────────────────────
# 7. Obtenir un token GitLab via OAuth
# ─────────────────────────────────────────────
echo "[gitlab] Récupération du token API..."
GITLAB_TOKEN=""
for i in $(seq 1 60); do
  curl -sf "http://localhost:${GITLAB_PORT}/-/readiness" -H "Host: localhost" >/dev/null 2>&1 || true
  GITLAB_TOKEN=$(curl -sf \
    "http://localhost:${GITLAB_PORT}/oauth/token" \
    -H "Host: localhost" \
    --data "grant_type=password&username=root&password=${GITLAB_ROOT_PASSWORD}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")
  if [ -n "$GITLAB_TOKEN" ]; then
    echo "[gitlab] Token obtenu."
    break
  fi
  echo "[gitlab] API pas encore prete ($i/60), attente 15s..."
  sleep 15
done

if [ -z "$GITLAB_TOKEN" ]; then
  echo "[ERREUR] Impossible d'obtenir un token GitLab."
  exit 1
fi

# ─────────────────────────────────────────────
# 8. Créer le repo sur GitLab
# ─────────────────────────────────────────────
echo "[gitlab] Création du repo '$GITLAB_REPO_NAME'..."
curl -sf \
  "http://localhost:${GITLAB_PORT}/api/v4/projects" \
  -H "Host: localhost" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  --data "name=${GITLAB_REPO_NAME}&visibility=public&initialize_with_readme=true" \
  -o /dev/null || true

sleep 5

DEFAULT_BRANCH=$(curl -sf \
  "http://localhost:${GITLAB_PORT}/api/v4/projects/root%2F${GITLAB_REPO_NAME}" \
  -H "Host: localhost" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('default_branch','main'))" 2>/dev/null || echo "main")

# ─────────────────────────────────────────────
# 9. Push deployment.yaml (v1) sur GitLab
# ─────────────────────────────────────────────
echo "[gitlab] Push du deployment.yaml (v1)..."

DEPLOYMENT_CONTENT='apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
spec:
  replicas: 2
  selector:
    matchLabels:
      app: wil-playground
  template:
    metadata:
      labels:
        app: wil-playground
    spec:
      containers:
        - name: wil-playground
          image: wil42/playground:v1
          ports:
            - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  selector:
    app: wil-playground
  ports:
    - port: 8888
      targetPort: 8888'

curl -sf \
  "http://localhost:${GITLAB_PORT}/api/v4/projects/root%2F${GITLAB_REPO_NAME}/repository/files/deployment.yaml" \
  -H "Host: localhost" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"branch\": \"${DEFAULT_BRANCH}\",
    \"content\": \"$(echo "$DEPLOYMENT_CONTENT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')\",
    \"commit_message\": \"Initial deployment v1\"
  }" \
  -X POST \
  -o /dev/null || echo "[gitlab] Fichier existe déjà, on continue."

echo "[gitlab] deployment.yaml pushé."

# ─────────────────────────────────────────────
# 10. Enregistrer GitLab dans Argo CD
# ─────────────────────────────────────────────
echo "[argocd] Enregistrement du repo GitLab dans Argo CD..."

GITLAB_INTERNAL_URL="http://gitlab-webservice-default.${GITLAB_NAMESPACE}.svc.cluster.local:8181/root/${GITLAB_REPO_NAME}.git"

kubectl apply -n "$ARGOCD_NAMESPACE" -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: gitlab-repo-secret
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: ${GITLAB_INTERNAL_URL}
  username: root
  password: ${GITLAB_ROOT_PASSWORD}
YAML

# ─────────────────────────────────────────────
# 11. Appliquer l'Application Argo CD
# ─────────────────────────────────────────────
kubectl apply -f "$SCRIPT_DIR/../confs/application.yaml"
echo "[argocd] Application déployée."

# ─────────────────────────────────────────────
# 12. Quick checks (best effort)
# ─────────────────────────────────────────────
echo "[test] Attente du deploiement wil-playground (best effort)..."
kubectl wait --for=condition=available deployment/wil-playground -n "$DEV_NAMESPACE" --timeout=300s 2>/dev/null || true
kubectl -n "$DEV_NAMESPACE" get pods -l app=wil-playground 2>/dev/null || true

# ─────────────────────────────────────────────
# 12. Port-forward Argo CD
# ─────────────────────────────────────────────
pkill -f "port-forward svc/argocd-server -n argocd" 2>/dev/null || true
kubectl port-forward svc/argocd-server \
  -n "$ARGOCD_NAMESPACE" --address 0.0.0.0 "${ARGOCD_PORT}:443" &

# ─────────────────────────────────────────────
# Résumé
# ─────────────────────────────────────────────
VM_IP=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -1)

ARGOCD_PASSWORD=""
if kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)
else
  ARGOCD_PASSWORD="(secret déjà consommé/supprimé)"
fi

echo ""
echo "========================================"
echo " GitLab  : http://${VM_IP}:${GITLAB_PORT}"
echo " Login   : root / ${GITLAB_ROOT_PASSWORD}"
echo ""
echo " Argo CD : https://${VM_IP}:${ARGOCD_PORT}"
echo " Login   : admin / ${ARGOCD_PASSWORD}"
echo ""
echo " Pour changer v1 -> v2 (démo soutenance) :"
echo "   ./update_version.sh v2"
echo "========================================"

# Facilite update_version.sh (sans hardcode)
umask 077
echo "${GITLAB_ROOT_PASSWORD}" > "${SCRIPT_DIR}/.gitlab_root_password"
