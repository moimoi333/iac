#!/usr/bin/env bash
# install.sh — Bootstrap Debian 12 Bookworm : Apache2 (reverse proxy) + Node.js + GitHub CLI + Claude Code
# Héberge l'application Roadmap IAC depuis https://github.com/moimoi333/iac
#
# Usage : curl -fsSL https://raw.githubusercontent.com/moimoi333/iac/main/install.sh | bash

set -euo pipefail

REPO_URL="https://github.com/moimoi333/iac.git"
APP_DIR="/opt/iac"
APP_PORT=3000
APP_USER="iac"
APACHE_CONF="/etc/apache2/sites-available/iac.conf"
SERVICE_FILE="/etc/systemd/system/iac-roadmap.service"

# ── Helpers ───────────────────────────────────────────────────────────────────
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

# ── 3. Node.js 18 ────────────────────────────────────────────────────────────
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
if ! command -v claude &>/dev/null && [[ ! -f /root/.local/bin/claude ]]; then
  log "Installation de Claude Code..."
  npm install -g @anthropic-ai/claude-code --quiet
  export PATH="$HOME/.local/bin:$PATH"
  grep -q '.local/bin' /root/.bashrc 2>/dev/null \
    || echo 'export PATH="$HOME/.local/bin:$PATH"' >> /root/.bashrc
else
  log "Claude Code déjà présent."
fi

# ── 6. Apache 2 ───────────────────────────────────────────────────────────────
log "Installation d'Apache 2..."
apt-get install -y -qq apache2

# ── 7. Clonage / mise à jour du dépôt iac ────────────────────────────────────
log "Déploiement de l'application depuis $REPO_URL..."
if [[ -d "$APP_DIR/.git" ]]; then
  log "Dépôt déjà présent, mise à jour (git pull)..."
  git -C "$APP_DIR" pull --ff-only
else
  rm -rf "$APP_DIR"
  git clone "$REPO_URL" "$APP_DIR"
fi

# ── 8. Utilisateur système dédié ─────────────────────────────────────────────
if ! id "$APP_USER" &>/dev/null; then
  log "Création de l'utilisateur système '$APP_USER'..."
  useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USER"
fi
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

# ── 9. Dépendances Node.js ───────────────────────────────────────────────────
log "Installation des dépendances Node.js..."
cd "$APP_DIR"
npm install --omit=dev --quiet

# ── 10. Service systemd ──────────────────────────────────────────────────────
log "Configuration du service systemd iac-roadmap..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=IAC Roadmap — serveur Node.js
After=network.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production PORT=$APP_PORT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iac-roadmap
systemctl restart iac-roadmap

# Attendre que le serveur Node soit prêt
log "Démarrage du serveur Node.js (port $APP_PORT)..."
for i in $(seq 1 10); do
  curl -sf "http://localhost:$APP_PORT/" &>/dev/null && break
  sleep 1
done

# ── 11. Apache — reverse proxy vers Node.js ──────────────────────────────────
log "Configuration d'Apache en reverse proxy..."
a2enmod proxy proxy_http &>/dev/null

cat > "$APACHE_CONF" <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost

    # Reverse proxy vers l'application Node.js
    ProxyPreserveHost On
    ProxyPass        / http://127.0.0.1:$APP_PORT/
    ProxyPassReverse / http://127.0.0.1:$APP_PORT/

    ErrorLog  \${APACHE_LOG_DIR}/iac_error.log
    CustomLog \${APACHE_LOG_DIR}/iac_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf &>/dev/null || true
a2ensite iac.conf
systemctl enable apache2
systemctl restart apache2

# ── Résumé ────────────────────────────────────────────────────────────────────
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "======================================================="
echo " Installation terminée avec succès !"
echo "======================================================="
echo " Apache 2  : $(apache2 -v 2>/dev/null | head -1)"
echo " Node.js   : $(node --version 2>/dev/null)"
echo " GitHub CLI: $(gh --version 2>/dev/null | head -1)"
echo " Claude    : installé dans ~/.local/bin/claude"
echo ""
echo " Roadmap   : http://$SERVER_IP/"
echo " App dir   : $APP_DIR  (dépôt git: $REPO_URL)"
echo " Service   : systemctl status iac-roadmap"
echo ""
echo " Pour authentifier GitHub CLI : gh auth login"
echo " Pour configurer Claude Code  : claude"
echo "======================================================="
