#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BONUS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

REPO_URL="${1:-${GITLAB_REPO_URL:-}}"
if [[ -z "${REPO_URL}" ]]; then
  echo "Usage: bash ${SCRIPT_DIR}/apply_argocd_app.sh <GITLAB_REPO_URL>" >&2
  echo "Ex:   bash ${SCRIPT_DIR}/apply_argocd_app.sh http://<ip>:30080/root/iot-manifests.git" >&2
  exit 1
fi

RENDERED="$(mktemp)"
cat "${BONUS_DIR}/confs/argocd/application-gitlab.yaml.tmpl" \
  | sed "s|__GITLAB_REPO_URL__|${REPO_URL}|g" \
  > "$RENDERED"

kubectl apply -f "$RENDERED"
rm -f "$RENDERED"

echo "[argocd] Application créée/MAJ : wil-playground-gitlab"
kubectl -n argocd get applications | sed -n '1,120p'
