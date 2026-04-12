# Architecture

This document explains how the devbox system fits together and why it's built the way it is. For setup and daily use, see the [README](README.md).

---

## System overview

```
Your Mac
  │
  │  ssh / Tailscale
  ▼
Host server (Linux, Docker, Tailscale)
  │
  ├── /usr/local/bin/devbox             ── CLI (create, stop, destroy, share, …)
  │
  ├── /opt/devbox/web/server.js          ── Management webapp (port 4242)
  │
  ├── /data/devboxes/
  │   ├── .state.json                    ── Pin + share state
  │   ├── clever-otter/                  ── Persistent workspace (volume-mounted)
  │   └── my-project/
  │
  └── Docker
        ├── devbox-clever-otter          ─┐
        └── devbox-my-project            ─┘  Containers (devbox-base image)
              │
              ├── tailscaled             ── Own Tailscale node
              ├── sshd                   ── SSH access
              └── idle-detect            ── Stops container when idle
```

Each container is a peer on your Tailscale network — reachable by name, independently authenticated, independently revocable.

---

## Tailscale integration

### Why each devbox gets its own Tailscale node

The alternative — routing through the host's Tailscale node — would mean all devboxes share one identity, one set of ACLs, and one revocation point. With individual nodes:

- You can SSH directly to `ssh root@clever-otter` without any port-mapping or proxy
- ACLs apply per-devbox via `tag:devbox`
- Destroying a devbox removes it from the tailnet cleanly
- Tailscale's admin console shows each devbox as a distinct machine with last-seen time

### Ephemeral auth keys

`devbox create` generates a new Tailscale ephemeral auth key (TTL: 5 minutes) via the API each time a container is created. Ephemeral keys register the device but don't persist in the Tailscale key list — the device is removed from the tailnet automatically if it goes offline and doesn't reconnect. This keeps the tailnet clean without requiring explicit cleanup.

Authentication to the Tailscale API uses an **OAuth client** (`TAILSCALE_CLIENT_ID` + `TAILSCALE_CLIENT_SECRET` in `/etc/devbox/config`). The script exchanges these for a short-lived bearer token at call time. OAuth clients don't expire, unlike API access tokens which cap at 90 days. Create one under Settings → Trust Credentials in the Tailscale admin console.

For resumed containers (existing container restarted), the Tailscale state is already on disk in the container's layer, so re-authentication isn't needed.

### Userspace networking

The container uses `tailscaled --tun=userspace-networking` rather than a real TUN device. This is because:

- Real TUN requires `--privileged` or very specific capabilities
- Userspace networking works with just `--cap-add=NET_ADMIN --device=/dev/net/tun`
- The tradeoff is slightly lower throughput, which is irrelevant for interactive dev use

### `tag:devbox` ACL isolation

Devboxes are tagged `tag:devbox` on the tailnet. The recommended ACL policy lets them reach the internet (for `apt`, `npm`, `pip`) but not each other or your LAN. This means:

- A compromised or misbehaving devbox can't pivot to other devboxes
- Devboxes can't reach your NAS, router, or other home infrastructure
- You (the admin) can still reach any devbox

---

## State model

State that can't be derived from Docker lives in a single JSON file: `/data/devboxes/.state.json`.

```json
{
  "clever-otter": {
    "pinned": true,
    "share": {
      "active": true,
      "url": "https://clever-otter.trycloudflare.com",
      "port": 3000
    }
  }
}
```

### Why a flat JSON file and not a database

- The host is a personal server, not a production system — SQLite or Postgres would be overkill
- The state is small (tens of devboxes at most) and infrequently written
- It's human-readable and trivially backed up with the data directory
- Any tool (`jq`, a shell script, the webapp) can read or write it without a client library

### What state lives where

| State | Where | Why |
|-------|-------|-----|
| Running/stopped | Docker | Docker is the source of truth for container lifecycle |
| CPU / RAM | Docker stats API | Live data, not persisted |
| Pin state | `.state.json` | Docker has no concept of "pinned" |
| Share URL / tunnel | `.state.json` | Cloudflared has no persistent state API |
| SSH keys | Container's `/root/.ssh/` | Inside the container, survives restarts via volume |
| Tailscale auth | Container's `/var/lib/tailscale/` | Tailscale manages its own state |

Workspace data (code, project files) lives in `/data/devboxes/<name>/`, mounted at `/workspace` inside the container. This is the only data that truly needs to survive a full container deletion.

---

## Idle detection

The idle detection sidecar (`/usr/local/bin/idle-detect`) runs inside each container and polls every 30 seconds. It considers the container active if either:

- There are active SSH sessions (`who` returns any rows)
- Network traffic has changed since the last poll (tx+rx bytes on the primary interface)

The network check catches activity beyond SSH — a running dev server receiving requests, a long `npm install`, etc. — without needing to inspect specific processes.

When the idle counter reaches the threshold, the sidecar sends `SIGTERM` to PID 1 (the entrypoint), which shuts down sshd and tailscaled gracefully. Docker sees the container exit and marks it as stopped.

### Why stop rather than pause

`docker pause` would be simpler but freezes the container's processes, including Tailscale. A stopped container has no Tailscale presence, which is the right behavior — idle devboxes shouldn't consume tailnet slots or appear as "offline" nodes. When resumed, `devbox create <name>` gets a fresh Tailscale auth key.

### Pinned devboxes

A pinned devbox sets `DEVBOX_IDLE_TIMEOUT=0`, which causes the sidecar to exit immediately at startup. The container runs until explicitly stopped. Pin state is stored in `.state.json` and respected when the webapp calls `devbox create`.

---

## Webapp architecture

The webapp (`web/server.js`) is a thin Express server that:

1. Talks to Docker via `dockerode` to list containers and collect stats
2. Reads/writes `.state.json` for pin and share state
3. Delegates create/destroy/share operations to the CLI scripts via `execFile`

### Why delegate to scripts rather than reimplementing in Node

The CLI scripts are the primary interface on the host — people use them directly from the terminal. Keeping all the logic there means:

- The webapp stays simple and stateless
- Terminal and webapp behavior are always in sync
- Scripts can be tested independently
- No duplication of the Tailscale API calls, Docker run logic, etc.

The cost is a subprocess per action, which is acceptable for a personal tool with one user.

### Stats polling

The frontend polls `/api/devboxes` every 5 seconds. Each poll collects a single non-streaming `docker stats` snapshot per running container. This is slightly expensive (one stats call per container) but avoids the complexity of maintaining streaming connections or a server-side stats cache.

---

## Cloudflare Tunnel (sharing)

`devbox share` uses Cloudflare's quick tunnel mode (`cloudflared tunnel --url`), which requires no account, no configuration files, and no persistent tunnel state on Cloudflare's side. The tunnel URL is ephemeral — it changes each time.

The tunnel process runs on the **host**, not inside the container. It connects to the devbox via its **MagicDNS hostname** (e.g., `clever-otter.tailnet.ts.net`) rather than its Tailscale IP. This matters because Tailscale IPs can change when a devbox is destroyed and recreated, but MagicDNS hostnames are stable. The hostname is resolved from `tailscale status --json` on the host at share time.

- `cloudflared` is installed on the host, not in the container
- The host needs `tag:server` in Tailscale so its ACL allows it to reach `tag:devbox` devices
- Teardown is just killing the `cloudflared` process

The tunnel PID is stored in `/var/log/devbox/tunnel-<name>.pid` so `devbox unshare` can find and kill it.

---

## Extension points

Some things this system intentionally doesn't do, and how you'd add them:

**Multiple SSH users / team access**
Add a `DEVBOX_SSH_PUBKEYS` env var that accepts multiple newline-separated keys. The entrypoint already appends to `authorized_keys`, so supporting multiple keys is a one-line change.

**Persistent Cloudflare Tunnels with stable URLs**
Replace the quick tunnel with a named tunnel using `cloudflared tunnel create` and a Cloudflare API token. The URL would be stable across restarts. Requires a Cloudflare account and a bit more config.

**Per-devbox resource limits**
Add `--memory` and `--cpus` flags to the `docker run` call in `devbox create`. Could be configurable via `/etc/devbox/config` or per-devbox flags.

**Automatic devbox creation for git repos**
A `devbox clone <git-url>` subcommand that creates a devbox, clones the repo into `/workspace`, and installs the right runtime via `mise` based on the repo's language. Mostly a thin wrapper around `devbox create` + `docker exec`.

**Notifications when a devbox stops**
The entrypoint's `_term` handler is the right place to add a webhook call or Tailscale notification before shutting down.
