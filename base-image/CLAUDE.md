# Devbox Context

You are running inside a **devbox** — an isolated Docker container provisioned on a home server running Docker and Tailscale.

## Host Environment

- **Host OS:** Linux (the host that manages your devboxes)
- **Host services:** Docker, Tailscale (subnet router), ufw firewall

## This Container

- **OS:** Ubuntu 24.04
- **Shell:** bash
- **Working directory:** `/workspace` (persisted)

## Networking

- **Tailscale is running** inside this container. The box is reachable by its devbox name on the tailnet (e.g., `ssh drew@clever-otter`).
- This container has its own Tailscale node — it appears independently in the tailnet admin console.
- The container may also be shared publicly via a Cloudflare Tunnel (check `devbox share` status on the host).

## Persistence

- `/workspace` is mounted from the host's devbox data directory.
- Anything written to `/workspace` survives container restarts and rebuilds.
- Data outside `/workspace` is ephemeral — it lives only for the lifetime of this container image/layer.

## Available Tools

- **`mise`** — manage Node, Python, and other runtime versions per project
  - Install Node LTS: `mise use node@lts`
  - Install Python: `mise use python@3.12`
  - Activate in current shell: `eval "$(mise activate bash)"`
- **`cloudflared`** — installed on the host, not inside this container. Public sharing is managed via `devbox share` on the host.
- **`tailscale`** — already running; use `tailscale status` to check connectivity
- **`git`, `curl`, `wget`, `build-essential`** — standard dev tools

## Installing Claude Code

Run the helper script:

```bash
install-claude-code
```

This installs the Claude Code CLI (`claude`) using the official installer.

## Docker

- The **host runs Docker** — do not attempt Docker-in-Docker unless it has been explicitly configured for this devbox.
- You cannot reach the host's Docker socket from inside this container by default.

## SSH / Remote Development

- SSH is running on port 22.
- Connect from your Mac: `ssh <you>@<devbox-name>` (via Tailscale)
- Works with **Zed Remote SSH** and **VSCode Remote - SSH** extensions.
- Your user has passwordless sudo. Root is also accessible as a fallback.

## Idle Detection

- This devbox will automatically stop after **30 minutes of inactivity** (no SSH sessions, no network traffic) unless it is pinned.
- To prevent auto-stop, pin the devbox from the management webapp.
- Idle detection logs: `/var/log/devbox-idle.log`

## Auto-starting services

If you have a process that should run every time this devbox starts (a dev server, a background worker, etc.), create `/workspace/.devbox-startup.sh`:

```bash
#!/usr/bin/env bash
# Runs automatically each time this devbox container starts.
# Output is logged to /var/log/devbox-startup.log.

cd /workspace/myapp
node server.js &
```

```bash
chmod +x /workspace/.devbox-startup.sh
```

Because this file lives in `/workspace` (the persistent volume), it survives container upgrades via `devbox upgrade`. This is the right place for anything that would otherwise need to be re-installed or re-started after a `devbox upgrade`.

**Note:** Packages installed with `apt`, global `npm install -g`, etc. live in the container layer — they are lost on upgrade. If your startup script depends on system packages, install them in the startup script itself so they re-run each time.

## Tips

- `tailscale status` — check Tailscale connectivity and your Tailscale IP
- `mise list` — show installed runtimes
- `df -h /workspace` — check persistent storage usage
