#!/bin/bash
# Usage: ./update_version.sh v2   (ou v1 pour revenir)

set -euo pipefail

VERSION="${1:-v2}"
GITLAB_PORT="8929"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GITLAB_ROOT_PASSWORD_FILE="${SCRIPT_DIR}/.gitlab_root_password"
GITLAB_ROOT_PASSWORD=""
GITLAB_REPO_NAME="habouda_iot"
DEFAULT_BRANCH="main"

if [[ "$VERSION" != "v1" && "$VERSION" != "v2" ]]; then
  echo "Usage: $0 v1|v2"
  exit 1
fi

echo "[update] Récupération du token GitLab..."
if [ -f "$GITLAB_ROOT_PASSWORD_FILE" ]; then
  GITLAB_ROOT_PASSWORD=$(cat "$GITLAB_ROOT_PASSWORD_FILE")
else
  echo "[ERREUR] Mot de passe root GitLab introuvable: $GITLAB_ROOT_PASSWORD_FILE"
  echo "Relance: ./install.sh (ou recupere le secret gitlab-gitlab-initial-root-password)"
  exit 1
fi

GITLAB_TOKEN=$(curl -sf \
  "http://localhost:${GITLAB_PORT}/oauth/token" \
  -H "Host: localhost" \
  --data "grant_type=password&username=root&password=${GITLAB_ROOT_PASSWORD}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

# main/master selon la config GitLab
DEFAULT_BRANCH=$(curl -sf \
  "http://localhost:${GITLAB_PORT}/api/v4/projects/root%2F${GITLAB_REPO_NAME}" \
  -H "Host: localhost" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  | python3 -c "import sys,json; print(json.load(sys.stdin).get('default_branch','main'))" 2>/dev/null || echo "main")

DEPLOYMENT_CONTENT="apiVersion: apps/v1
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
          image: wil42/playground:${VERSION}
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
      targetPort: 8888"

echo "[update] Push deployment.yaml avec image:${VERSION} sur GitLab..."
curl -sf \
  "http://localhost:${GITLAB_PORT}/api/v4/projects/root%2F${GITLAB_REPO_NAME}/repository/files/deployment.yaml" \
  -H "Host: localhost" \
  --header "Authorization: Bearer $GITLAB_TOKEN" \
  --header "Content-Type: application/json" \
  --data "{
    \"branch\": \"${DEFAULT_BRANCH}\",
    \"content\": \"$(echo \"$DEPLOYMENT_CONTENT\" | sed 's/\"/\\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')\",
    \"commit_message\": \"update to ${VERSION}\"
  }" \
  -X PUT \
  -o /dev/null

echo "[update] Done. ArgoCD va détecter le changement et redéployer (attendre ~3 min)."
echo ""
echo "Pour vérifier :"
echo "  kubectl get pods -n dev"
echo "  kubectl port-forward svc/wil-playground -n dev --address 0.0.0.0 8888:8888 &"
echo "  curl http://localhost:8888/"
