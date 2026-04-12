#!/usr/bin/env bash
# Devbox idle detection sidecar
# Monitors SSH sessions and network activity; stops the container when idle.
# Controlled by DEVBOX_IDLE_TIMEOUT (minutes). 0 = disabled.

set -euo pipefail

LOG="/var/log/devbox-idle.log"
mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

# Respect the idle timeout env var
TIMEOUT_MINUTES="${DEVBOX_IDLE_TIMEOUT:-30}"

if [[ "$TIMEOUT_MINUTES" -eq 0 ]]; then
    log "Idle detection disabled (DEVBOX_IDLE_TIMEOUT=0). Exiting sidecar."
    exit 0
fi

TIMEOUT_SECONDS=$(( TIMEOUT_MINUTES * 60 ))
POLL_INTERVAL=30   # seconds between checks
IDLE_COUNT=0
IDLE_THRESHOLD=$(( TIMEOUT_SECONDS / POLL_INTERVAL ))

log "Idle detection started. Timeout: ${TIMEOUT_MINUTES}m (${TIMEOUT_SECONDS}s), polling every ${POLL_INTERVAL}s."

# Detect the primary network interface (first non-lo interface)
get_primary_iface() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | head -1
}

# Read TX+RX bytes for a given interface
get_net_bytes() {
    local iface="$1"
    local rx tx
    rx=$(cat "/sys/class/net/${iface}/statistics/rx_bytes" 2>/dev/null || echo 0)
    tx=$(cat "/sys/class/net/${iface}/statistics/tx_bytes" 2>/dev/null || echo 0)
    echo $(( rx + tx ))
}

# Count active SSH sessions
get_ssh_sessions() {
    who 2>/dev/null | wc -l
}

IFACE=""
PREV_BYTES=""

while true; do
    sleep "$POLL_INTERVAL"

    # Lazily discover interface (it may not exist immediately at startup)
    if [[ -z "$IFACE" ]]; then
        IFACE=$(get_primary_iface)
    fi

    SSH_SESSIONS=$(get_ssh_sessions)
    CURRENT_BYTES=$(get_net_bytes "${IFACE:-eth0}")

    if [[ -z "$PREV_BYTES" ]]; then
        PREV_BYTES="$CURRENT_BYTES"
    fi

    NET_ACTIVE=0
    if [[ "$CURRENT_BYTES" -ne "$PREV_BYTES" ]]; then
        NET_ACTIVE=1
    fi

    PREV_BYTES="$CURRENT_BYTES"

    if [[ "$SSH_SESSIONS" -gt 0 || "$NET_ACTIVE" -eq 1 ]]; then
        if [[ "$IDLE_COUNT" -gt 0 ]]; then
            log "Activity detected (SSH sessions: ${SSH_SESSIONS}, net active: ${NET_ACTIVE}). Resetting idle counter."
        fi
        IDLE_COUNT=0
    else
        IDLE_COUNT=$(( IDLE_COUNT + 1 ))
        REMAINING=$(( (IDLE_THRESHOLD - IDLE_COUNT) * POLL_INTERVAL ))
        log "Idle tick ${IDLE_COUNT}/${IDLE_THRESHOLD} (SSH: 0, net: static). Shutdown in ${REMAINING}s if no activity."
    fi

    if [[ "$IDLE_COUNT" -ge "$IDLE_THRESHOLD" ]]; then
        log "Idle threshold reached (${TIMEOUT_MINUTES}m). Shutting down container."
        # Give a moment for the log to flush
        sleep 2
        # Stop the container gracefully by halting init (PID 1 sees SIGTERM and exits)
        kill -SIGTERM 1 2>/dev/null || shutdown -h now
    fi
done
