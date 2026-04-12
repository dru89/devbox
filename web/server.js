'use strict';

const express = require('express');
const Docker = require('dockerode');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const { promisify } = require('util');

const execFileAsync = promisify(execFile);

const app = express();
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

const PORT = process.env.PORT || 4242;
const DATA_ROOT = process.env.DEVBOX_DATA_ROOT || '/data/devboxes';
const STATE_FILE = path.join(DATA_ROOT, '.state.json');
const LOG_DIR = process.env.DEVBOX_LOG_DIR || '/var/log/devbox';
const SCRIPTS_DIR = process.env.DEVBOX_SCRIPTS_DIR || '/usr/local/bin';

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ── State file helpers ────────────────────────────────────────────────────────

function readState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    }
  } catch (e) {
    console.error('Failed to read state file:', e.message);
  }
  return {};
}

function writeState(state) {
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function getDevboxState(name) {
  const state = readState();
  return state[name] || { pinned: false, share: { active: false, url: '', port: 80 } };
}

function setDevboxState(name, updates) {
  const state = readState();
  state[name] = { ...getDevboxState(name), ...updates };
  writeState(state);
}

// ── Docker helpers ────────────────────────────────────────────────────────────

// List all devbox containers (name starts with 'devbox-')
async function listDevboxContainers() {
  const containers = await docker.listContainers({ all: true });
  return containers.filter(c =>
    c.Names.some(n => n.startsWith('/devbox-'))
  );
}

// Parse the devbox name from a container name like '/devbox-clever-otter'
function parseName(containerInfo) {
  const name = containerInfo.Names[0];
  return name.replace(/^\/devbox-/, '');
}

// Get stats and resource limits for a single running container
async function getContainerStats(container) {
  const [stats, inspect] = await Promise.all([
    new Promise((resolve) => {
      container.stats({ stream: false }, (err, data) => {
        if (err || !data) { resolve(null); return; }
        resolve(data);
      });
    }),
    container.inspect().catch(() => null),
  ]);

  const nanoCpus = inspect?.HostConfig?.NanoCpus || 0;
  const cpuLimit = nanoCpus > 0 ? Math.round((nanoCpus / 1e9) * 10) / 10 : 0;
  const memLimitSet = inspect?.HostConfig?.Memory || 0;

  if (!stats) return { cpu: 0, memMB: 0, memLimitMB: 0, cpuLimit };

  try {
    const cpuDelta = stats.cpu_stats.cpu_usage.total_usage - stats.precpu_stats.cpu_usage.total_usage;
    const systemDelta = stats.cpu_stats.system_cpu_usage - stats.precpu_stats.system_cpu_usage;
    const numCpus = stats.cpu_stats.online_cpus || stats.cpu_stats.cpu_usage.percpu_usage?.length || 1;
    const cpuPercent = systemDelta > 0 ? (cpuDelta / systemDelta) * numCpus * 100 : 0;
    const memUsage = stats.memory_stats.usage || 0;
    // Prefer the HostConfig limit (explicit) over the stats limit (system RAM when unconstrained)
    const memLimit = memLimitSet > 0 ? memLimitSet : (stats.memory_stats.limit || 0);
    return {
      cpu: Math.round(cpuPercent * 10) / 10,
      memMB: Math.round(memUsage / 1024 / 1024),
      memLimitMB: memLimitSet > 0 ? Math.round(memLimitSet / 1024 / 1024) : 0,
      cpuLimit,
    };
  } catch {
    return { cpu: 0, memMB: 0, memLimitMB: 0, cpuLimit };
  }
}

// Parse Docker's multiplexed log stream into an array of { stream, text } lines
function parseDockerLogs(buffer) {
  const lines = [];
  let offset = 0;
  while (offset + 8 <= buffer.length) {
    const streamType = buffer[offset]; // 1 = stdout, 2 = stderr
    const size = buffer.readUInt32BE(offset + 4);
    offset += 8;
    if (offset + size > buffer.length) break;
    const chunk = buffer.slice(offset, offset + size).toString('utf8');
    chunk.split('\n').forEach(line => {
      if (line) lines.push({ stream: streamType === 2 ? 'stderr' : 'stdout', text: line });
    });
    offset += size;
  }
  return lines;
}

// Get disk usage for a devbox data directory
function getDiskUsage(name) {
  const dir = path.join(DATA_ROOT, name);
  try {
    const { size } = fs.statfsSync ? fs.statfsSync(dir) : {};
    // statfsSync not always available; fall back to du via sync exec
    // We skip expensive du calls in the API — disk is shown in the UI as N/A unless available
    return null;
  } catch {
    return null;
  }
}

// Run a devbox script
async function devboxCmd(...args) {
  const bin = path.join(SCRIPTS_DIR, 'devbox');
  const { stdout, stderr } = await execFileAsync(bin, args, { timeout: 60000 });
  return { stdout, stderr };
}

// ── API routes ────────────────────────────────────────────────────────────────

// GET /api/devboxes — list all devboxes with status and stats
app.get('/api/devboxes', async (req, res) => {
  try {
    const containers = await listDevboxContainers();
    const state = readState();

    const devboxes = await Promise.all(containers.map(async (info) => {
      const name = parseName(info);
      const boxState = state[name] || {};
      const isRunning = info.State === 'running';

      let stats = { cpu: 0, memMB: 0, memLimitMB: 0, cpuLimit: 0 };
      if (isRunning) {
        try {
          const container = docker.getContainer(info.Id);
          stats = await getContainerStats(container);
        } catch { /* ignore stats errors */ }
      }

      // Read idle log for last activity time
      let idleLog = null;
      try {
        const logPath = path.join(LOG_DIR, `tunnel-${name}.log`);
        // Idle log is at /var/log/devbox-idle.log inside the container
        // We can exec into it to read the last line
      } catch { /* ignore */ }

      return {
        name,
        status: info.State,
        pinned: boxState.pinned || false,
        share: boxState.share || { active: false, url: '', port: 80 },
        cpu: stats.cpu,
        cpuLimit: stats.cpuLimit,
        memMB: stats.memMB,
        memLimitMB: stats.memLimitMB,
        created: info.Created,
        dataPath: path.join(DATA_ROOT, name),
      };
    }));

    res.json(devboxes);
  } catch (err) {
    console.error('GET /api/devboxes error:', err);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/devboxes — create a new devbox
app.post('/api/devboxes', async (req, res) => {
  const { name } = req.body || {};
  try {
    const args = name ? [name] : [];
    const { stdout } = await devboxCmd('create', ...args);
    res.json({ ok: true, output: stdout });
  } catch (err) {
    res.status(500).json({ error: err.message, output: err.stderr });
  }
});

// POST /api/devboxes/:name/start
app.post('/api/devboxes/:name/start', async (req, res) => {
  const { name } = req.params;
  try {
    const { stdout } = await devboxCmd('start', name);
    res.json({ ok: true, output: stdout });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/devboxes/:name/stop
app.post('/api/devboxes/:name/stop', async (req, res) => {
  const { name } = req.params;
  try {
    const container = docker.getContainer(`devbox-${name}`);
    await container.stop();
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/devboxes/:name/destroy
app.post('/api/devboxes/:name/destroy', async (req, res) => {
  const { name } = req.params;
  try {
    const { stdout } = await devboxCmd('destroy', name);
    res.json({ ok: true, output: stdout });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/devboxes/:name/pin — toggle pin state
app.post('/api/devboxes/:name/pin', async (req, res) => {
  const { name } = req.params;
  try {
    const boxState = getDevboxState(name);
    const newPinned = !boxState.pinned;
    setDevboxState(name, { pinned: newPinned });

    // Update the running container's idle timeout env if possible
    // (Docker doesn't support env updates on running containers — the change
    // takes effect on next start)
    res.json({ ok: true, pinned: newPinned });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/devboxes/:name/share — start a Cloudflare Tunnel
app.post('/api/devboxes/:name/share', async (req, res) => {
  const { name } = req.params;
  const port = req.body?.port || 80;
  try {
    const { stdout } = await devboxCmd('share', name, '--port', String(port));
    const boxState = getDevboxState(name);
    res.json({ ok: true, output: stdout, share: boxState.share });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// DELETE /api/devboxes/:name/share — stop the tunnel
app.delete('/api/devboxes/:name/share', async (req, res) => {
  const { name } = req.params;
  try {
    const { stdout } = await devboxCmd('unshare', name);
    res.json({ ok: true, output: stdout });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/devboxes/:name/logs — fetch recent container logs
app.get('/api/devboxes/:name/logs', async (req, res) => {
  const { name } = req.params;
  const tail = Math.min(parseInt(req.query.tail || '200', 10), 1000);
  try {
    const container = docker.getContainer(`devbox-${name}`);
    const buffer = await container.logs({ stdout: true, stderr: true, tail, timestamps: true });
    const lines = parseDockerLogs(buffer);
    res.json({ lines });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ── Start server ──────────────────────────────────────────────────────────────

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Devbox management webapp running on port ${PORT}`);
  console.log(`Accessible via Tailscale — ensure ufw blocks LAN access to port ${PORT}`);
});
