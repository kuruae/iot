# Bonus — GitLab local + Argo CD (k3d)

Objectif : faire fonctionner le même flux que la Part 3, mais avec un GitLab **local** (namespace `gitlab`) comme source Git pour Argo CD.

## Pré-requis
- `docker`, `k3d`, `kubectl`, `curl`.

## 1) Démarrage (cluster + ArgoCD + GitLab)
```bash
bash bonus/scripts/install.sh
```
Le script affiche :
- l’URL GitLab (sur une IP Docker + NodePort), login `root`, et le mot de passe (stocké dans `bonus/scripts/.gitlab_root_password`, ignoré par git).
- l’URL ArgoCD et le mot de passe admin.

## 2) Créer un repo GitLab pour les manifests
Dans l’UI GitLab :
1. Créez un projet **Public** (ex: `iot-manifests`).
2. Créez un **Personal Access Token** (scope minimal : `write_repository`).

## 3) Pousser le repo d’exemple (v1)
Depuis la VM (ou là où vous exécutez `k3d`) :
```bash
cd bonus/repo
git init
git add .
git commit -m "init v1"
git branch -M main

git remote add origin http://<ip>:30080/root/iot-manifests.git
# au push, Git vous demandera un password : collez votre PAT
git push -u origin main
```

## 4) Créer l’Application ArgoCD (source = GitLab)
```bash
bash bonus/scripts/apply_argocd_app.sh http://<ip>:30080/root/iot-manifests.git
```

## 5) Accès & vérification
Port-forwards (ArgoCD + app) :
```bash
bash bonus/scripts/port_forwards.sh
```
Test :
```bash
curl http://localhost:8888/
```

## 6) Passage v1 -> v2 (démonstration)
Dans le repo GitLab, modifiez `deployment.yaml` :
- `wil42/playground:v1` -> `wil42/playground:v2`

Puis commit+push :
```bash
git add deployment.yaml
git commit -m "v2"
git push
```
ArgoCD synchronise automatiquement, puis :
```bash
curl http://localhost:8888/
```

## Stop
```bash
bash bonus/scripts/stop.sh
```
