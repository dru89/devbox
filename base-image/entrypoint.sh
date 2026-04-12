#!/usr/bin/env bash
# Devbox container entrypoint
# Starts Tailscale, SSH, and the idle detection sidecar.

set -euo pipefail

log() {
    echo "[entrypoint] $*"
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

# ── SSH keys ─────────────────────────────────────────────────────────────────

# Inject SSH public key(s) if provided via environment variable.
# DEVBOX_SSH_PUBKEY can contain one or more public keys (newline-separated).
if [[ -n "${DEVBOX_SSH_PUBKEY:-}" ]]; then
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "${DEVBOX_SSH_PUBKEY}" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
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
