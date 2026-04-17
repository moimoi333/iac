# IAC — Infrastructure as Code

Application de roadmap Gantt hébergée sur k3s, gérée via GitLab CI/CD.

---

## Architecture

```
GitLab repo
  ├── Dockerfile          → image buildée par CI → GitLab Container Registry
  ├── .gitlab-ci.yml      → build auto sur chaque push sur main
  ├── deploy.yaml         → manifest k3s (Namespace + PVC + Deployment + Service)
  ├── install.sh          → bootstrap du nœud k3s (Debian 12 Bookworm)
  ├── server.js           → API Express (GET/POST /api/config et /api/projets)
  ├── public/
  │   ├── index.html      → redirige vers roadmap.html
  │   └── roadmap.html    → UI Gantt (chargement auto depuis /api/*)
  └── data/               → données initiales (copiées au 1er démarrage si PVC vide)
      ├── config.json     → pilotes, catégories, couleurs
      └── projets.csv     → projets, jalons, priorités
```

**Flux de déploiement :**
```
push sur main → GitLab CI build image → registry.gitlab.com/NAMESPACE/iac:latest
                                               ↓
                              k3s pull l'image → Pod → PVC iac-data (/app/data)
```

**Données persistantes :** le PVC `iac-data` monte `/app/data` dans le pod.
Au premier démarrage, `server.js` copie automatiquement `defaults/` → `data/` si vide.

---

## Déploiement initial (nouveau serveur Bookworm)

```bash
# 1. Bootstrap du nœud k3s
curl -fsSL https://raw.githubusercontent.com/moimoi333/iac/main/install.sh | bash

# 2. Créer le secret pour tirer l'image depuis GitLab Registry
kubectl create secret docker-registry gitlab-registry \
  -n iac \
  --docker-server=registry.gitlab.com \
  --docker-username=<gitlab_user> \
  --docker-password=<gitlab_token_read_registry>

# 3. Adapter l'image dans deploy.yaml : remplacer VOTRE_NAMESPACE
# 4. Appliquer le manifest
kubectl apply -f deploy.yaml

# 5. Suivre le démarrage
kubectl -n iac get pod -w
kubectl -n iac get svc iac-roadmap   # → EXTERNAL-IP sur port 80
```

---

## Mise à jour de l'application

```bash
# Pusher sur main → CI rebuild l'image automatiquement
git push origin main

# Forcer k3s à tirer la nouvelle image
kubectl -n iac rollout restart deployment/iac-roadmap
kubectl -n iac rollout status deployment/iac-roadmap
```

---

## Commandes utiles k3s

```bash
# État général
kubectl -n iac get all

# Logs du pod
kubectl -n iac logs -f deployment/iac-roadmap

# Accès aux données persistées
kubectl -n iac exec -it deployment/iac-roadmap -- ls /app/data

# IP externe du service
kubectl -n iac get svc iac-roadmap -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Supprimer et réinstaller proprement (⚠ supprime les données)
kubectl delete namespace iac
kubectl apply -f deploy.yaml
```

---

## Format des données

**`data/config.json`** — pilotes, catégories, couleurs, congés

**`data/projets.csv`** — format :
```
name,cat,pilot,start,end,progress,priority,milestones
Mon projet,infra,alice,2026-01-01,2026-06-30,45,1,"2026-03-01|Jalon|livraison"
```
- `priority` : 1=haute · 2=normale · 3=basse
- `milestones` : `"AAAA-MM-JJ|Libellé|type"` séparés par ` ; ` (type: `livraison` ou `critique`)

---

## Mémo — Contexte pour les prochaines sessions Claude

### Ce qui existe
- **Repo GitHub** : `moimoi333/iac` (dépôt de travail actuel, à migrer sur GitLab)
- **App locale** : `/root/board/` — version de développement avec `roadmap.html` standalone (drag-and-drop) et `public/roadmap.html` (version serveur, chargement auto via API)
- **Serveur actuel** : Debian 12 Bookworm, Apache 2.4 + Node.js 18 installés sur le host, app sur port 3000 via reverse proxy Apache

### Décisions d'architecture prises
1. **Pas d'Apache dans k3s** — le Service Kubernetes `LoadBalancer` expose directement le port 80 → pod 3000
2. **Pas d'init container pour le code** — l'image Docker contient tout (buildée par GitLab CI)
3. **1 seul PVC** (`iac-data`, 256Mi) pour `/app/data` — le code est dans l'image
4. **Données initiales** : `data/` est baked dans l'image sous `defaults/`, `server.js` les copie au 1er démarrage si PVC vide
5. **GitLab CI** : `.gitlab-ci.yml` build et push sur `registry.gitlab.com` à chaque push sur `main`

### Ce qu'il reste à faire
- Migrer le repo de GitHub (`moimoi333/iac`) vers GitLab
- Remplacer `VOTRE_NAMESPACE` dans `deploy.yaml` par le namespace GitLab réel
- Créer le secret `gitlab-registry` sur le cluster k3s avant `kubectl apply`
- Optionnel : Ingress Traefik + cert-manager pour un domaine avec TLS

### Fichiers clés
| Fichier | Rôle |
|---|---|
| `server.js` | API Express, lit `PORT` depuis env, auto-init données depuis `defaults/` |
| `public/roadmap.html` | UI Gantt — chargement auto depuis `/api/config` et `/api/projets` |
| `Dockerfile` | `FROM node:18-bookworm-slim`, bake `data/` → `defaults/` |
| `.gitlab-ci.yml` | Build et push image sur GitLab Container Registry |
| `deploy.yaml` | Manifest k3s complet (Namespace + PVC + Deployment + Service LoadBalancer) |
| `install.sh` | Bootstrap Bookworm : k3s + Claude Code + gh CLI |
