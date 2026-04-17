#!/usr/bin/env bash
# install.sh — Bootstrap d'un nœud k3s sur Debian 12 Bookworm
# Installe k3s + outils admin (Claude Code, GitHub/GitLab CLI)
# Le déploiement de l'app se fait ensuite via : kubectl apply -f deploy.yaml
#
# Usage : curl -fsSL https://raw.githubusercontent.com/moimoi333/iac/main/install.sh | bash

set -euo pipefail

log() { echo "[INFO]  $*"; }
err() { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Exécuter en tant que root"
[[ "$(. /etc/os-release && echo "$VERSION_CODENAME")" == "bookworm" ]] \
  || log "AVERTISSEMENT: optimisé pour Debian 12 Bookworm"

# ── 1. Dépendances système ────────────────────────────────────────────────────
log "Mise à jour et dépendances..."
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl gnupg ca-certificates git apt-transport-https

# ── 2. k3s ───────────────────────────────────────────────────────────────────
if ! command -v k3s &>/dev/null; then
  log "Installation de k3s..."
  curl -sfL https://get.k3s.io | sh -
  # Rendre kubectl accessible sans sudo
  mkdir -p ~/.kube
  cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  chmod 600 ~/.kube/config
  export KUBECONFIG=~/.kube/config
  grep -q 'KUBECONFIG' ~/.bashrc || echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
else
  log "k3s $(k3s --version | head -1) déjà installé."
fi

# ── 3. Node.js 18 (requis pour Claude Code) ───────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d v)" -lt 18 ]]; then
  log "Installation de Node.js 18..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y -qq nodejs
fi

# ── 4. Claude Code ────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null && [[ ! -f /root/.local/bin/claude ]]; then
  log "Installation de Claude Code..."
  npm install -g @anthropic-ai/claude-code --quiet
  grep -q '.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
  export PATH="$HOME/.local/bin:$PATH"
fi

# ── 5. GitHub CLI ─────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  log "Installation de GitHub CLI..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq && apt-get install -y -qq gh
fi

# ── Résumé ────────────────────────────────────────────────────────────────────
echo ""
echo "======================================================="
echo " Nœud k3s prêt !"
echo "======================================================="
echo " k3s     : $(k3s --version | head -1)"
echo " kubectl : $(kubectl version --client --short 2>/dev/null | head -1)"
echo " Node.js : $(node --version)"
echo " Claude  : ~/.local/bin/claude"
echo " gh CLI  : $(gh --version 2>/dev/null | head -1)"
echo ""
echo " Étapes suivantes :"
echo "  1. Créer le secret registry GitLab :"
echo "     kubectl create secret docker-registry gitlab-registry \\"
echo "       -n iac --docker-server=registry.gitlab.com \\"
echo "       --docker-username=<user> --docker-password=<token>"
echo ""
echo "  2. Adapter l'image dans deploy.yaml (VOTRE_NAMESPACE)"
echo "     puis : kubectl apply -f deploy.yaml"
echo ""
echo "  3. Suivre le déploiement :"
echo "     kubectl -n iac get pod -w"
echo "     kubectl -n iac get svc iac-roadmap"
echo "======================================================="
