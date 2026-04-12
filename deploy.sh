#!/usr/bin/env bash
# deploy.sh — Build and deploy devbox to your server
#
# Usage:
#   ./deploy.sh               # full deploy
#   ./deploy.sh --image-only  # rebuild Docker image only
#   ./deploy.sh --scripts     # install scripts only
#   ./deploy.sh --web         # restart webapp only

set -euo pipefail

DEVBOX_HOST="${DEVBOX_HOST:-}"              # SSH target — set via env or edit this line
REMOTE_DIR="${REMOTE_DIR:-/opt/devbox}"  # Where the repo lives on the server
DEPLOY_USER="${DEPLOY_USER:-$USER}"      # User to run the webapp service as

log()  { echo "▶ $*"; }
step() { echo ""; echo "── $* ──────────────────────────────"; }

usage() {
    cat <<EOF
Usage: DEVBOX_HOST=<host> ./deploy.sh [--image-only | --scripts | --web | --help]

Deploys the devbox system to your server.

Assumes:
  - DEVBOX_HOST host is reachable via SSH (required — set DEVBOX_HOST=<hostname>)
  - The repo will be synced to ${REMOTE_DIR} on the server
  - Docker is installed on the server
  - systemd is running on the server

Options:
  --image-only    Only rebuild the Docker base image
  --scripts       Only install CLI scripts to /usr/local/bin/
  --web           Only restart the webapp service
  --sync-only     Only sync files (no build/restart)
  --help          Show this message

Environment variables:
  DEVBOX_HOST=<host>          SSH target hostname or alias (required)
  REMOTE_DIR=<path>   Where to sync the repo (default: /opt/devbox)
  DEPLOY_USER=<user>  User to run the webapp service as (default: \$USER)

Example:
  DEVBOX_HOST=myserver ./deploy.sh
  DEVBOX_HOST=myserver DEPLOY_USER=alice ./deploy.sh --web
EOF
    exit 0
}

# ── Argument parsing ──────────────────────────────────────────────────────────

DO_IMAGE=true
DO_SCRIPTS=true
DO_WEB=true
SYNC_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)        usage ;;
        --image-only)  DO_SCRIPTS=false; DO_WEB=false; shift ;;
        --scripts)     DO_IMAGE=false;   DO_WEB=false; shift ;;
        --web)         DO_IMAGE=false;   DO_SCRIPTS=false; shift ;;
        --sync-only)   SYNC_ONLY=true; DO_IMAGE=false; DO_SCRIPTS=false; DO_WEB=false; shift ;;
        *) echo "Unknown flag: $1"; usage ;;
    esac
done

# ── Validate required config ─────────────────────────────────────────────────

if [[ -z "$DEVBOX_HOST" ]]; then
    echo "Error: DEVBOX_HOST is not set. Specify your server's SSH hostname:"
    echo "  DEVBOX_HOST=myserver ./deploy.sh"
    exit 1
fi

# ── Sync repo to server ───────────────────────────────────────────────────────

step "Syncing repo to ${DEVBOX_HOST}:${REMOTE_DIR}"
ssh "$DEVBOX_HOST" "mkdir -p ${REMOTE_DIR}"
rsync -av --delete \
    --exclude='.git' \
    --exclude='node_modules' \
    --exclude='*.log' \
    ./ "${DEVBOX_HOST}:${REMOTE_DIR}/"
log "Sync complete."

if $SYNC_ONLY; then
    log "Sync-only mode. Done."
    exit 0
fi

# ── Build Docker image ────────────────────────────────────────────────────────

if $DO_IMAGE; then
    step "Building devbox-base Docker image on server"
    ssh "$DEVBOX_HOST" "cd ${REMOTE_DIR}/base-image && docker build -t devbox-base ."
    log "Image built."
fi

# ── Install CLI scripts ───────────────────────────────────────────────────────

if $DO_WEB; then
    step "Installing webapp dependencies on server"
    ssh "$DEVBOX_HOST" "cd ${REMOTE_DIR}/web && npm install --omit=dev"
fi

# ── Privileged installs (single ssh -t so sudo only prompts once) ─────────────

if $DO_SCRIPTS || $DO_WEB; then
    # Build a script locally from the enabled steps, then scp + execute it.
    # All sudo calls happen in one SSH session so the credential cache applies.
    PRIV_SCRIPT=$(mktemp)
    echo "#!/usr/bin/env bash" >> "$PRIV_SCRIPT"
    echo "set -e" >> "$PRIV_SCRIPT"

    if $DO_SCRIPTS; then
        cat >> "$PRIV_SCRIPT" <<EOF
sudo install -m 0755 '${REMOTE_DIR}/scripts/devbox' /usr/local/bin/devbox
echo '  installed: /usr/local/bin/devbox'
if [[ -d /etc/bash_completion.d ]]; then
    sudo install -m 0644 '${REMOTE_DIR}/scripts/devbox.bash-completion' /etc/bash_completion.d/devbox
    echo '  installed: /etc/bash_completion.d/devbox'
fi
ZSH_SITE=/usr/local/share/zsh/site-functions
if [[ -d "\$ZSH_SITE" ]]; then
    sudo install -m 0644 '${REMOTE_DIR}/scripts/devbox.zsh-completion' "\${ZSH_SITE}/_devbox"
    echo "  installed: \${ZSH_SITE}/_devbox"
fi
EOF
    fi

    if $DO_WEB; then
        cat >> "$PRIV_SCRIPT" <<EOF
sudo tee /etc/systemd/system/devbox-web.service > /dev/null <<'UNIT'
[Unit]
Description=Devbox Management Webapp
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${DEPLOY_USER}
WorkingDirectory=${REMOTE_DIR}/web
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=4242

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable devbox-web
sudo systemctl restart devbox-web
echo '  devbox-web service started.'
EOF
    fi

    step "Running privileged install steps on server"
    scp -q "$PRIV_SCRIPT" "$DEVBOX_HOST:/tmp/devbox-deploy-priv.sh"
    rm "$PRIV_SCRIPT"
    ssh -t "$DEVBOX_HOST" "bash /tmp/devbox-deploy-priv.sh; rm /tmp/devbox-deploy-priv.sh"

    $DO_SCRIPTS && log "CLI installed."
    $DO_WEB    && log "Webapp running on ${DEVBOX_HOST}:4242"
fi

echo ""
echo "✓ Deploy complete."
echo ""
echo "  Management UI:  http://${DEVBOX_HOST}:4242  (via Tailscale)"
echo "  Create devbox:  devbox create"
echo "  List devboxes:  devbox list"
echo "  Destroy devbox: devbox destroy <name>"
echo "  Share devbox:   devbox share <name>"
