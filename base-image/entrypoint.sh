#!/usr/bin/env bash
# Devbox container entrypoint
# Starts Tailscale, SSH, and the idle detection sidecar.

set -euo pipefail

log() {
    echo "[entrypoint] $*"
}

# ── Dotfiles ──────────────────────────────────────────────────────────────────

# Clone the user's dotfiles repo and run their devbox init script.
# Runs as DEVBOX_USER so stow creates symlinks with the right ownership.
# Skipped if DEVBOX_DOTFILES_REPO is not set.
_setup_dotfiles() {
    local user="$1" home_dir="$2"
    if [[ -z "${DEVBOX_DOTFILES_REPO:-}" ]]; then return; fi

    local dotfiles_dir="${home_dir}/.dotfiles"
    if [[ -d "$dotfiles_dir" ]]; then
        log "Dotfiles already present for ${user}, skipping clone."
    else
        log "Cloning dotfiles for ${user}..."
        local clone_url="${DEVBOX_DOTFILES_REPO}"
        # Inject GH_TOKEN for private repos
        if [[ -n "${GH_TOKEN:-}" && "$clone_url" == https://github.com/* ]]; then
            clone_url="https://${GH_TOKEN}@${clone_url#https://}"
        fi
        if ! runuser -u "$user" -- git clone --quiet "$clone_url" "$dotfiles_dir" 2>&1; then
            log "Warning: Failed to clone dotfiles from ${DEVBOX_DOTFILES_REPO}"
            return
        fi
    fi

    if [[ -n "${DEVBOX_DOTFILES_INIT:-}" ]]; then
        log "Running dotfiles init for ${user}: ${DEVBOX_DOTFILES_INIT}"
        runuser -u "$user" -- bash -c "cd '${dotfiles_dir}' && ${DEVBOX_DOTFILES_INIT}" 2>&1 || \
            log "Warning: Dotfiles init failed for ${user}"
    fi
}

# ── Atuin ─────────────────────────────────────────────────────────────────────

# Log into atuin on first boot so sync works without manual intervention.
# Skipped on container restarts (meta.db already exists). The atuin config
# comes from dotfiles; server URL is overridden via ATUIN_SYNC_ADDRESS env var.
_setup_atuin() {
    local user="$1" home_dir="$2"
    if [[ -z "${ATUIN_USERNAME:-}" || -z "${ATUIN_PASSWORD:-}" || -z "${ATUIN_KEY:-}" ]]; then return; fi

    local data_dir="${home_dir}/.local/share/atuin"

    # meta.db present means atuin is already configured (restart, not fresh create)
    if [[ -f "${data_dir}/meta.db" ]]; then
        log "Atuin already configured for ${user}, skipping login."
        return
    fi

    local server_url="${ATUIN_SYNC_ADDRESS:-http://ds9:8888}"
    log "Logging into atuin for ${user} (server: ${server_url})..."
    runuser -u "$user" -- bash -c "
        ATUIN_SYNC_ADDRESS='${server_url}' \
        atuin login -u '${ATUIN_USERNAME}' -p '${ATUIN_PASSWORD}' --key '${ATUIN_KEY}'
    " 2>&1 || log "Warning: Atuin login failed for ${user}. Run 'atuin login' manually inside the devbox."
}

# ── SSH key helper ────────────────────────────────────────────────────────────

_install_ssh_keys() {
    local ssh_dir="$1" owner="$2"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    echo "${DEVBOX_SSH_PUBKEY}" >> "${ssh_dir}/authorized_keys"
    chmod 600 "${ssh_dir}/authorized_keys"
    [[ "$owner" != "root" ]] && chown -R "${owner}:${owner}" "$ssh_dir"
}

# ── Tailscale ────────────────────────────────────────────────────────────────

log "Starting tailscaled..."
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
TAILSCALED_PID=$!
sleep 2

if [[ -n "${TAILSCALE_AUTH_KEY:-}" ]]; then
    log "Authenticating with Tailscale..."
    tailscale up \
        --authkey="${TAILSCALE_AUTH_KEY}" \
        --hostname="${HOSTNAME}" \
        --advertise-tags="tag:devbox" \
        --accept-routes=false \
        --ssh=false 2>&1 || log "Warning: tailscale up returned non-zero (may already be up)"
else
    log "Warning: TAILSCALE_AUTH_KEY not set. Tailscale will not authenticate."
fi

# ── User setup ───────────────────────────────────────────────────────────────

# Create a named user if DEVBOX_USER is set, so you can SSH in as yourself
# rather than root. The user gets passwordless sudo for full dev access.
if [[ -n "${DEVBOX_USER:-}" ]]; then
    if ! id "$DEVBOX_USER" &>/dev/null; then
        log "Creating user '${DEVBOX_USER}'..."
        useradd -m -s /bin/bash "$DEVBOX_USER"
        echo "${DEVBOX_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${DEVBOX_USER}"
        chmod 440 "/etc/sudoers.d/${DEVBOX_USER}"
    fi
    chown "${DEVBOX_USER}:${DEVBOX_USER}" /workspace
    log "User '${DEVBOX_USER}' ready."

    _setup_dotfiles "$DEVBOX_USER" "/home/${DEVBOX_USER}"
    _setup_atuin    "$DEVBOX_USER" "/home/${DEVBOX_USER}"
fi

# ── SSH keys ─────────────────────────────────────────────────────────────────

# Install SSH public key(s) for both root (fallback) and DEVBOX_USER if set.
if [[ -n "${DEVBOX_SSH_PUBKEY:-}" ]]; then
    _install_ssh_keys /root/.ssh root
    if [[ -n "${DEVBOX_USER:-}" ]]; then
        _install_ssh_keys "/home/${DEVBOX_USER}/.ssh" "$DEVBOX_USER"
    fi
    log "SSH public key(s) installed."
elif [[ ! -s /root/.ssh/authorized_keys ]]; then
    log "Warning: No SSH public key provided. Set DEVBOX_SSH_PUBKEY to enable SSH access."
fi

# ── SSH ──────────────────────────────────────────────────────────────────────

log "Starting SSH server..."
/usr/sbin/sshd -D &
SSHD_PID=$!

# ── Idle Detection ───────────────────────────────────────────────────────────

log "Starting idle detection sidecar (timeout: ${DEVBOX_IDLE_TIMEOUT:-30}m)..."
/usr/local/bin/idle-detect &
IDLE_PID=$!

# ── Startup script ───────────────────────────────────────────────────────────

# Run /workspace/.devbox-startup.sh if it exists.
# This is the right place for services that should auto-start with the devbox
# (e.g., a dev server, a background worker). Since /workspace is the persistent
# volume, this script survives container upgrades.
STARTUP_SCRIPT="/workspace/.devbox-startup.sh"
if [[ -f "$STARTUP_SCRIPT" && -x "$STARTUP_SCRIPT" ]]; then
    log "Running startup script: ${STARTUP_SCRIPT}"
    bash "$STARTUP_SCRIPT" >> /var/log/devbox-startup.log 2>&1 &
    log "Startup script launched (PID $!). Logs: /var/log/devbox-startup.log"
elif [[ -f "$STARTUP_SCRIPT" ]]; then
    log "Warning: ${STARTUP_SCRIPT} exists but is not executable. Run: chmod +x ${STARTUP_SCRIPT}"
fi

# ── Wait ─────────────────────────────────────────────────────────────────────

log "Devbox is ready. Hostname: ${HOSTNAME}"

# Forward signals to children
_term() {
    log "Caught SIGTERM, shutting down..."
    kill "$SSHD_PID" "$IDLE_PID" "$TAILSCALED_PID" 2>/dev/null || true
}
trap _term SIGTERM SIGINT

# Wait on sshd as the main process; if it exits, the container stops
wait "$SSHD_PID"
