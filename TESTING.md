# Testing Checklist

End-to-end verification for a fresh devbox setup. Work through these in order.

## 1. Deploy

- [ ] `DEVBOX_SERVER=ds9 ./deploy.sh` completes without errors
- [ ] Single sudo password prompt during privileged install steps
- [ ] `ssh ds9 devbox help` shows the command list
- [ ] `ssh ds9 systemctl status devbox-web` shows active/running

## 2. Mac-side client

- [ ] `make install` completes
- [ ] `export DEVBOX_HOST=ds9` set in `~/.bashrc` and sourced
- [ ] `devbox list` from Mac says "No devboxes found." (proxies to ds9)
- [ ] `devbox <tab>` shows subcommands
- [ ] `devbox stop <tab>` (after creating one) shows devbox names

## 3. Create a devbox

- [ ] `devbox create test-box` succeeds
- [ ] Output shows Tailscale IP and `ssh root@test-box`
- [ ] `devbox list` shows test-box as running

## 4. SSH access

- [ ] `ssh root@test-box` connects
- [ ] `tailscale status` inside the container shows connected
- [ ] `/workspace` directory exists
- [ ] `cat /var/log/devbox-idle.log` shows idle detection running
- [ ] Exit back to Mac

## 5. Management webapp

- [ ] `http://ds9:4242` loads in browser (must be on Tailscale)
- [ ] test-box appears with CPU/RAM stats
- [ ] Pin toggle works
- [ ] "New Devbox" button creates a devbox

## 6. Sharing

- [ ] Start something to share: `ssh root@test-box 'python3 -m http.server 3000 &'`
- [ ] `devbox share test-box` prints a trycloudflare.com URL
- [ ] URL loads in browser
- [ ] Share URL appears in webapp
- [ ] `devbox unshare test-box` tears it down
- [ ] URL no longer works

## 7. Stop / start

- [ ] `devbox stop test-box` stops the container
- [ ] `devbox list` shows test-box as stopped
- [ ] `devbox create test-box` resumes it (no new Tailscale auth — should be fast)
- [ ] `ssh root@test-box` works again

## 8. Idle detection

- [ ] Create a devbox with a short timeout: `devbox create --timeout 1 idle-test`
- [ ] SSH in, then exit, wait ~2 minutes
- [ ] `devbox list` shows idle-test as stopped on its own
- [ ] Check the log: `ssh ds9 docker logs devbox-idle-test` (container must still exist)

## 9. Pin

- [ ] `devbox pin test-box` — confirm "pinned" message
- [ ] `devbox list` shows pinned: yes
- [ ] `devbox pin test-box` again — confirm unpinned
- [ ] Webapp pin toggle reflects state change

## 10. Upgrade

- [ ] Make a trivial change to `base-image/CLAUDE.md`, rebuild: `DEVBOX_SERVER=ds9 ./deploy.sh --image-only`
- [ ] `devbox upgrade test-box` detects safe-only change and syncs in place
- [ ] Confirm the file changed inside the container: `ssh root@test-box cat /root/CLAUDE.md`

## 11. Destroy

- [ ] `devbox destroy test-box`
- [ ] Container no longer appears in `devbox list`
- [ ] Tailscale node removed from admin console
- [ ] Data preserved: `ssh ds9 ls /data/devboxes/test-box`

## 12. Startup script

- [ ] SSH into a devbox: `ssh root@test-box`
- [ ] Create `/workspace/.devbox-startup.sh` that writes a file or starts a process
- [ ] `chmod +x /workspace/.devbox-startup.sh`
- [ ] `devbox stop test-box && devbox create test-box`
- [ ] Confirm startup script ran: check `/var/log/devbox-startup.log` inside container
