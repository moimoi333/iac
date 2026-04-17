#!/usr/bin/env bash
# install.sh — Bootstrap a Debian 12 Bookworm server with Apache2, GitHub CLI, and Claude Code
# Source: https://github.com/moimoi333/iac

set -euo pipefail

REPO_URL="https://github.com/moimoi333/iac.git"
WEB_ROOT="/var/www/iac"
APACHE_CONF="/etc/apache2/sites-available/iac.conf"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[INFO]  $*"; }
err()  { echo "[ERROR] $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || err "Ce script doit être exécuté en tant que root (sudo $0)"
[[ "$(. /etc/os-release && echo "$VERSION_CODENAME")" == "bookworm" ]] \
  || log "AVERTISSEMENT: ce script est optimisé pour Debian 12 Bookworm."

# ── 1. Mise à jour du système ─────────────────────────────────────────────────
log "Mise à jour des paquets système..."
apt-get update -qq
apt-get upgrade -y -qq

# ── 2. Dépendances de base ────────────────────────────────────────────────────
log "Installation des dépendances de base..."
apt-get install -y -qq \
  curl \
  gnupg \
  ca-certificates \
  git \
  apt-transport-https

# ── 3. Node.js 18 (requis pour Claude Code) ───────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node --version | cut -d. -f1 | tr -d v)" -lt 18 ]]; then
  log "Installation de Node.js 18 via NodeSource..."
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y -qq nodejs
else
  log "Node.js $(node --version) déjà installé."
fi

# ── 4. GitHub CLI ─────────────────────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  log "Installation de GitHub CLI..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/etc/apt/keyrings/githubcli-archive-keyring.gpg status=none
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq
  apt-get install -y -qq gh
else
  log "GitHub CLI $(gh --version | head -1) déjà installé."
fi

# ── 5. Claude Code ────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  log "Installation de Claude Code..."
  npm install -g @anthropic-ai/claude-code --quiet
  # Assurer que ~/.local/bin est dans le PATH pour root
  export PATH="$HOME/.local/bin:$PATH"
  if ! grep -q '.local/bin' /root/.bashrc 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc
  fi
else
  log "Claude Code $(claude --version 2>/dev/null || echo 'installé') déjà présent."
fi

# ── 6. Apache 2 ───────────────────────────────────────────────────────────────
log "Installation d'Apache 2..."
apt-get install -y -qq apache2

# ── 7. Clonage du dépôt iac ───────────────────────────────────────────────────
log "Déploiement du site depuis $REPO_URL..."
if [[ -d "$WEB_ROOT/.git" ]]; then
  log "Dépôt déjà présent, mise à jour (git pull)..."
  git -C "$WEB_ROOT" pull --ff-only
else
  rm -rf "$WEB_ROOT"
  git clone "$REPO_URL" "$WEB_ROOT"
fi
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"

# ── 8. Configuration Apache ───────────────────────────────────────────────────
log "Configuration du VirtualHost Apache..."
cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot $WEB_ROOT

    <Directory $WEB_ROOT>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/iac_error.log
    CustomLog \${APACHE_LOG_DIR}/iac_access.log combined
</VirtualHost>
EOF

# Désactiver le vhost par défaut, activer iac
a2dissite 000-default.conf &>/dev/null || true
a2ensite iac.conf
a2enmod rewrite &>/dev/null || true

# ── 9. Démarrage d'Apache ─────────────────────────────────────────────────────
log "Activation et démarrage d'Apache 2..."
systemctl enable apache2
systemctl restart apache2

# ── Résumé ────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================================="
echo " Installation terminée avec succès !"
echo "======================================================="
echo " Apache 2  : $(apache2 -v 2>/dev/null | head -1)"
echo " GitHub CLI: $(gh --version 2>/dev/null | head -1)"
echo " Node.js   : $(node --version 2>/dev/null)"
echo " Claude    : installé dans ~/.local/bin/claude"
echo ""
echo " Site web  : http://$SERVER_IP/"
echo " Racine web: $WEB_ROOT  (dépôt git: $REPO_URL)"
echo ""
echo " Pour authentifier GitHub CLI : gh auth login"
echo " Pour configurer Claude Code  : claude"
echo "======================================================="
