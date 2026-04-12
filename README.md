# devbox

A devbox provisioning system for a home server running Docker and Tailscale. Each devbox is an isolated Docker container with its own Tailscale node, persistent data volume, and optional Cloudflare Tunnel for public sharing.

Designed to run on a headless Linux server.

---

## What's in here

```
devbox/
├── base-image/
│   ├── Dockerfile                  # Ubuntu 24.04 + Tailscale + SSH + mise
│   ├── CLAUDE.md                   # Context file baked into the image for Claude Code
│   ├── entrypoint.sh               # Starts Tailscale, sshd, and idle detection
│   ├── idle-detect.sh              # Stops the container after N minutes of inactivity
│   └── install-claude-code.sh      # One-liner helper to install Claude Code inside a devbox
├── scripts/
│   ├── devbox                      # CLI — see 'devbox help'
│   ├── devbox.bash-completion      # bash tab completion
│   └── devbox.zsh-completion       # zsh tab completion
├── web/
│   ├── server.js                   # Express API + Docker integration
│   ├── package.json
│   └── public/
│       └── index.html              # Management UI (vanilla JS, dark mode, mobile-friendly)
├── deploy.sh                       # Build image, install CLI, restart webapp on the server
└── README.md
```

---

## Prerequisites

On your server:
- Docker
- Tailscale (already joined to your tailnet, MagicDNS enabled)
- systemd
- Node.js ≥ 18 (for the management webapp)
- `cloudflared` (for `devbox share`; install via your package manager or [Cloudflare docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/))
- `jq`, `curl`

From your development machine (for deploying):
- SSH access to the server
- `rsync`

---

## First-time setup on your server

### 1. Config file

Create `/etc/devbox/config` (readable by root and your user):

```bash
sudo mkdir -p /etc/devbox
sudo tee /etc/devbox/config <<'EOF'
# Tailscale OAuth client credentials — create at:
#   Tailscale admin → Settings → Trust Credentials → OAuth Clients
# Grant: Auth Keys (write) and Devices (read + write)
# OAuth clients don't expire, unlike API access tokens.
TAILSCALE_CLIENT_ID="..."
TAILSCALE_CLIENT_SECRET="tskey-client-..."

# Your tailnet name — shown in the Tailscale admin console top-left
# Usually "yourname.ts.net" or "yourorg.com"
TAILSCALE_TAILNET="yourname.ts.net"

# (Optional) Override where SSH keys are sourced when creating devboxes
# Defaults to $HOME/.ssh/authorized_keys of the user running devbox create
# ssh_pubkey_file="/home/youruser/.ssh/authorized_keys"
EOF
sudo chmod 640 /etc/devbox/config
sudo chown root:$(whoami) /etc/devbox/config
```

### 2. Data and log directories

```bash
sudo mkdir -p /data/devboxes /var/log/devbox
sudo chown $(whoami):$(whoami) /data/devboxes /var/log/devbox
```

### 3. Docker access

Make sure your user is in the `docker` group:

```bash
sudo usermod -aG docker $(whoami)
# Log out and back in for it to take effect
```

### 4. Tailscale ACL tags

In the [Tailscale admin console](https://login.tailscale.com/admin/acls), add `tag:devbox` and `tag:server` tags. Devboxes get `tag:devbox`. Your server gets `tag:server` — this is what allows it to reach devboxes for Cloudflare Tunnel proxying.

**Manually tag your server** in the Tailscale admin console: go to the Machines tab, find your server, and apply `tag:server`.

Make sure your access controls include at minimum these rules:

```json
"tagOwners": {
  "tag:devbox": ["autogroup:admin"],
  "tag:server": ["autogroup:admin"]
},

// You can reach all devboxes and your server
{"action": "accept", "src": ["autogroup:admin"], "dst": ["tag:devbox:*", "tag:server:*"]},

// Your server can reach devboxes (needed for cloudflared tunnel proxying)
{"action": "accept", "src": ["tag:server"], "dst": ["tag:devbox:*"]},

// Devboxes can reach the internet (for apt, npm, pip, etc.)
{"action": "accept", "src": ["tag:devbox"], "dst": ["*:80,443"]},
```

**Note:** Tailscale ACLs are default-deny. Make sure you also have a rule covering `autogroup:self` so you can always reach your own devices. If you lose SSH access to a machine after editing ACLs, that's usually the culprit.

**What these rules do:**
- You can reach devboxes and your server directly
- Your server can proxy cloudflared tunnels into devboxes via Tailscale
- Devboxes can reach the internet but not each other or your LAN
- You SSH into any devbox by name: `ssh root@clever-otter`

### 5. Lock down the management webapp to Tailscale only

The webapp binds to all interfaces (`0.0.0.0:4242`) so it's reachable via Tailscale. Without a firewall rule it's also reachable from your LAN. Since the webapp can start, stop, and destroy containers, restrict it to the Tailscale interface only:

```bash
sudo ufw deny 4242
sudo ufw allow in on tailscale0 to any port 4242
```

This blocks all access to port 4242 except traffic arriving via the Tailscale interface.

---

## Deploy

From your development machine (in the repo root):

```bash
DEVBOX_SERVER=yourserver ./deploy.sh
```

Replace `yourserver` with the SSH hostname or alias for your server (whatever works with `ssh yourserver`).

This will:
1. Sync the repo to `/opt/devbox` on the server via rsync
2. Build the `devbox-base` Docker image on the server
3. Install `devbox` to `/usr/local/bin/` and set up shell completions
4. Install and start the `devbox-web` systemd service on port `4242`

### Deploy options

```bash
DEVBOX_SERVER=yourserver ./deploy.sh --image-only   # rebuild Docker image only
DEVBOX_SERVER=yourserver ./deploy.sh --scripts      # reinstall CLI scripts only
DEVBOX_SERVER=yourserver ./deploy.sh --web          # restart webapp only
DEVBOX_SERVER=yourserver DEPLOY_USER=alice ./deploy.sh  # run webapp as a specific user
```

---

## Using devbox from your local machine

You can run `devbox` commands from your laptop — not just from the server — by setting `DEVBOX_HOST`.

### 1. Install locally

From the repo root:

```bash
make install
```

This installs `devbox` to `/usr/local/bin/` and the zsh completion function to `/usr/local/share/zsh/site-functions/`. Override `PREFIX` to install elsewhere:

```bash
make install PREFIX=~/.local
```

### 2. Set DEVBOX_HOST

Add to your `~/.bashrc` (or `~/.zshrc`):

```bash
export DEVBOX_HOST=yourserver
```

Then `source ~/.bashrc` (or open a new terminal).

With `DEVBOX_HOST` set, every `devbox` invocation is transparently forwarded via SSH:

```bash
devbox list           # lists devboxes on yourserver
devbox create myapp   # creates devbox on yourserver
devbox stop myapp     # stops it
```

### 3. Set up tab completion locally

**bash** — add to `~/.bashrc`:

```bash
source /path/to/devbox/scripts/devbox.bash-completion
```

**zsh** — copy to your site-functions directory:

```bash
cp scripts/devbox.zsh-completion /usr/local/share/zsh/site-functions/_devbox
autoload -U compinit && compinit
```

Tab completion is `DEVBOX_HOST`-aware: it SSHes to the server to fetch devbox names.

---

## Daily use

```bash
devbox help            # show all commands
devbox help <command>  # show help for a specific command
```

### Creating a devbox

```bash
devbox create                        # random name, e.g. "clever-otter"
devbox create myproject              # specific name
devbox create --pin myserver         # pinned — never auto-stops
devbox create --timeout 60 myproject # custom idle timeout
```

Output:
```
devbox 'clever-otter' is ready
  ssh root@clever-otter
  Tailscale IP: 100.x.x.x
  Data: /data/devboxes/clever-otter
```

### Listing devboxes

```bash
devbox list
```

### Starting and stopping

```bash
devbox start clever-otter   # resume a stopped devbox
devbox stop clever-otter    # stop a running devbox
```

`devbox create <name>` also resumes a stopped devbox if it already exists.

### Destroying a devbox

```bash
devbox destroy clever-otter
```

Stops the container, removes it from Docker, and removes the Tailscale node. **Data in `/data/devboxes/clever-otter/` is never deleted.**

To also delete data:

```bash
rm -rf /data/devboxes/clever-otter
```

### Sharing a devbox publicly

```bash
devbox share clever-otter               # expose port 3000 (default)
devbox share clever-otter --port 8080   # expose a specific port
devbox unshare clever-otter             # tear it down
```

Uses Cloudflare's quick tunnel (no account required). Prints a public `trycloudflare.com` URL.

### Tab completion

The installer sets up tab completion for bash and zsh automatically. After deploying:

```bash
devbox <tab>          # shows subcommands
devbox stop <tab>     # shows running devbox names
devbox destroy <tab>  # shows all devbox names
```

If completion isn't working after a fresh install, start a new shell session or run `source /etc/bash_completion.d/devbox` (bash) or `autoload -U compinit && compinit` (zsh).

---

## Management webapp

After deploying, open the management UI in a browser (must be on Tailscale):

```
http://yourserver:4242
```

The UI shows all devboxes with live CPU/RAM stats, pin state, share URLs, and action buttons (Start, Stop, Destroy, Pin, Share). Has a "New Devbox" button. Works on iPhone.

---

## Inside a devbox

Once SSHed in (`ssh root@<name>`):

### Upgrading a devbox

```bash
devbox upgrade clever-otter   # recreate from current devbox-base image
devbox upgrade --all          # upgrade all devboxes (prompts first)
```

Data in `/workspace` is always preserved. Everything installed outside `/workspace` (apt packages, global npm packages, etc.) lives in the container layer and is lost on upgrade — put that setup in `/workspace/.devbox-startup.sh` so it re-runs automatically.

### Auto-starting services

Create `/workspace/.devbox-startup.sh` for any process that should start with the devbox:

```bash
#!/usr/bin/env bash
# Runs each time this devbox starts. Output → /var/log/devbox-startup.log
cd /workspace/myapp
node server.js &
```

```bash
chmod +x /workspace/.devbox-startup.sh
```

Because it's in `/workspace`, it survives upgrades automatically.

```bash
# Check Tailscale connectivity
tailscale status

# Install Node.js via mise
mise use node@lts
eval "$(~/.local/bin/mise activate bash)"
node --version

# Install Python
mise use python@3.12

# Install Claude Code
install-claude-code

# Your work lives here (persisted across restarts)
cd /workspace
```

---

## Idle detection

Each devbox monitors for activity and stops itself after 30 minutes of inactivity (no SSH sessions, no network traffic).

Configure with the `DEVBOX_IDLE_TIMEOUT` environment variable when starting a container:

| Value | Behavior |
|-------|----------|
| `30` (default) | Stop after 30 minutes idle |
| `60` | Stop after 60 minutes idle |
| `0` | Disabled — runs until manually stopped (pinned) |

Idle log inside the container: `/var/log/devbox-idle.log`

Pin/unpin via the webapp or with `devbox pin <name>`.

---

## Devbox state

State is stored in `/data/devboxes/.state.json` on the server:

```json
{
  "clever-otter": {
    "pinned": false,
    "share": {
      "active": true,
      "url": "https://clever-otter.trycloudflare.com",
      "port": 3000
    }
  }
}
```

---

## Troubleshooting

**Tailscale doesn't come up in the container:**
- Make sure `tag:devbox` exists in your Tailscale ACL policy
- Check `TAILSCALE_CLIENT_ID` and `TAILSCALE_CLIENT_SECRET` in `/etc/devbox/config`
- Check container logs: `docker logs devbox-<name>`

**Can't SSH into a devbox:**
- Ensure your SSH public key is in `~/.ssh/authorized_keys` on the server (`devbox create` reads this by default)
- Or set `DEVBOX_SSH_PUBKEY="ssh-ed25519 AAAA..."` in `/etc/devbox/config`
- Check inside the container: `docker exec devbox-<name> cat /root/.ssh/authorized_keys`

**Webapp not accessible:**
- Confirm you're on Tailscale
- Check the service: `ssh yourserver systemctl status devbox-web`
- Check logs: `ssh yourserver journalctl -u devbox-web -n 50`

**Container stopped unexpectedly:**
- Check the idle log: `docker exec devbox-<name> cat /var/log/devbox-idle.log`
- Pin the devbox via the webapp to prevent auto-stop

**`devbox create` fails with Tailscale API error:**
- Verify `TAILSCALE_CLIENT_ID`, `TAILSCALE_CLIENT_SECRET`, and `TAILSCALE_TAILNET` in `/etc/devbox/config`
- Make sure your OAuth client has Auth Keys (write) and Devices (read + write) grants
- Test token exchange manually:
  ```bash
  curl -X POST https://api.tailscale.com/api/v2/oauth/token \
    -d "client_id=$TAILSCALE_CLIENT_ID" \
    -d "client_secret=$TAILSCALE_CLIENT_SECRET" \
    -d "grant_type=client_credentials"
  ```
