const WebSocket = require('ws');
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const fs = require('fs');
const Docker = require('dockerode');
const { spawn } = require('child_process');
const path = require('path');
const { getRoleTier, isCommandAllowedForTier, getAllowedCommands, getInteractiveCommands } = require('./rbac-registry');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const PORT = process.env.TERMINAL_PROXY_PORT || 18790;
const GATEWAY_TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;
const JWT_SECRET = process.env.JWT_SECRET;
const OPENCLAW_CONTAINER = process.env.OPENCLAW_CONTAINER_NAME || 'trinity-openclaw';

// ── Dynamic environment variable overrides ─────────────────────────────
const ENV_OVERRIDES_PATH = process.env.ENV_OVERRIDES_PATH || path.join(__dirname, 'data', 'env-overrides.json');
const ENV_KEY_REGEX = /^[A-Za-z_][A-Za-z0-9_]*$/;
const ENV_KEY_MAX_LEN = 128;
const ENV_VALUE_MAX_LEN = 4096;
const ENV_BLOCKLIST = new Set([
  'OPENCLAW_GATEWAY_TOKEN', 'JWT_SECRET', 'PATH', 'HOME', 'USER',
  'NODE_ENV', 'DOCKER_HOST', 'HOSTNAME', 'TERMINAL_PROXY_PORT',
  'OPENCLAW_CONTAINER_NAME', 'ALLOWED_ORIGINS', 'SUPABASE_JWT_SECRET',
]);

let envOverrides = {};

function loadEnvOverrides() {
  try {
    if (fs.existsSync(ENV_OVERRIDES_PATH)) {
      const raw = fs.readFileSync(ENV_OVERRIDES_PATH, 'utf8');
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        envOverrides = parsed;
        log('info', `Loaded ${Object.keys(envOverrides).length} env override(s) from disk`);
      }
    }
  } catch (err) {
    log('error', 'Failed to load env overrides, starting empty', { error: err.message });
    envOverrides = {};
  }
}

function saveEnvOverrides() {
  try {
    const dir = path.dirname(ENV_OVERRIDES_PATH);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    const tmpPath = ENV_OVERRIDES_PATH + '.tmp';
    fs.writeFileSync(tmpPath, JSON.stringify(envOverrides, null, 2), 'utf8');
    fs.renameSync(tmpPath, ENV_OVERRIDES_PATH);
  } catch (err) {
    log('error', 'Failed to save env overrides', { error: err.message });
  }
}

function validateEnvKey(key) {
  if (!key || typeof key !== 'string') return 'Key is required';
  if (key.length > ENV_KEY_MAX_LEN) return `Key exceeds ${ENV_KEY_MAX_LEN} characters`;
  if (!ENV_KEY_REGEX.test(key)) return 'Key must match [A-Za-z_][A-Za-z0-9_]*';
  if (ENV_BLOCKLIST.has(key.toUpperCase())) return `Key "${key}" is a protected system variable`;
  return null;
}

function validateEnvValue(value) {
  if (value === undefined || value === null) return 'Value is required';
  const str = String(value);
  if (str.length > ENV_VALUE_MAX_LEN) return `Value exceeds ${ENV_VALUE_MAX_LEN} characters`;
  if (str.includes('\0')) return 'Value must not contain null bytes';
  return null;
}

// Load persisted env overrides at startup
loadEnvOverrides();

// ── Startup validation ─────────────────────────────────────────────────
if (!GATEWAY_TOKEN || GATEWAY_TOKEN.length < 16) {
  console.error('[terminal-proxy] FATAL: OPENCLAW_GATEWAY_TOKEN must be set and >= 16 characters.');
  process.exit(1);
}

// ── Structured logging ─────────────────────────────────────────────────
function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'terminal-proxy',
    message,
    ...meta,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

const docker = new Docker();

// ── Timing-safe token comparison ───────────────────────────────────────
function timingSafeTokenCompare(a, b) {
  if (!a || !b) return false;
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) {
    // Still do a comparison to avoid length-based timing leak
    crypto.timingSafeEqual(bufA, bufA);
    return false;
  }
  return crypto.timingSafeEqual(bufA, bufB);
}

// ── Safe ws.send helper ────────────────────────────────────────────────
function safeSend(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(typeof data === 'string' ? data : JSON.stringify(data));
    } catch (_) { /* ignore send errors on closing connections */ }
  }
}

// ── Command validation (exact word-boundary matching) ──────────────────
function validateCommand(cmd) {
  const cleanCmd = cmd.replace(/^openclaw\s+/, '').trim();

  if (cleanCmd === 'cat /home/node/.openclaw/workspace/MEMORY.md') {
    return {
      isAllowed: true,
      isInteractive: false,
      cleanCmd,
      baseCmd: 'cat'
    };
  }

  const allowedCommands = getAllowedCommands();

  // Use exact match or exact-prefix-with-space matching (word boundary)
  const isAllowed = allowedCommands.some(allowed => {
    return cleanCmd === allowed || cleanCmd.startsWith(allowed + ' ');
  });

  return {
    isAllowed,
    isInteractive: getInteractiveCommands().some(ic => cleanCmd === ic || cleanCmd.startsWith(ic + ' ')),
    cleanCmd,
    baseCmd: cleanCmd.split(' ')[0]
  };
}

// ── Command execution ──────────────────────────────────────────────────
function executeCommand(ws, cmd, token) {
  const validation = validateCommand(cmd);

  // Auth check FIRST, before revealing command validation details
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    safeSend(ws, { type: 'error', message: 'Invalid authentication token' });
    safeSend(ws, { type: 'exit', code: 1, message: 'Authentication failed' });
    return null;
  }

  if (!validation.isAllowed) {
    safeSend(ws, { type: 'error', message: 'Command not permitted' });
    safeSend(ws, { type: 'exit', code: 1, message: 'Command rejected' });
    return null;
  }

  // Execute via docker exec (use -i only, not -it since we don't have a TTY)
  const dockerCmd = ['exec'];

  if (validation.isInteractive) {
    dockerCmd.push('-i');
  }

  // Inject dynamic env var overrides as -e flags (before container name)
  for (const [k, v] of Object.entries(envOverrides)) {
    dockerCmd.push('-e', `${k}=${v}`);
  }

  if (validation.cleanCmd.startsWith('cat ')) {
    const filePath = validation.cleanCmd.substring(4).trim();
    dockerCmd.push(OPENCLAW_CONTAINER, 'cat', filePath);
  } else if (validation.cleanCmd === 'clawhub' || validation.cleanCmd.startsWith('clawhub ')) {
    dockerCmd.push(OPENCLAW_CONTAINER, 'clawhub', ...validation.cleanCmd.split(' ').slice(1));
  } else {
    dockerCmd.push(OPENCLAW_CONTAINER, 'openclaw', ...validation.cleanCmd.split(' '));
  }

  safeSend(ws, { type: 'system', message: `$ ${validation.cleanCmd}` });

  const child = spawn('docker', dockerCmd, {
    env: { ...process.env, OPENCLAW_GATEWAY_TOKEN: token }
  });

  child.stdout.on('data', (data) => {
    safeSend(ws, { type: 'stdout', data: data.toString() });
  });

  child.stderr.on('data', (data) => {
    safeSend(ws, { type: 'stderr', data: data.toString() });
  });

  child.on('close', (code) => {
    safeSend(ws, {
      type: 'exit',
      code: code,
      message: code === 0 ? 'Command completed successfully' : `Command exited with code ${code}`
    });
  });

  child.on('error', (err) => {
    safeSend(ws, { type: 'error', message: 'Failed to execute command' });
    log('error', 'Child process error', { error: err.message });
  });

  return child;
}

// ── Express app ────────────────────────────────────────────────────────
const app = express();
app.use(helmet());

// CORS with origin restriction (reject wildcard with credentials)
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true,
}));

app.use(express.json());

// Health check endpoint (minimal info)
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Get allowed commands list (requires auth via query token)
app.get('/commands', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  res.json({
    allowed: getAllowedCommands(),
    interactive: getInteractiveCommands()
  });
});

// Get/set dynamic environment variable overrides (superadmin via gateway token)
app.get('/env', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  res.json({ vars: { ...envOverrides } });
});

app.put('/env', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const { key, value } = req.body;
  const keyErr = validateEnvKey(key);
  if (keyErr) return res.status(400).json({ error: keyErr });
  const valErr = validateEnvValue(value);
  if (valErr) return res.status(400).json({ error: valErr });
  envOverrides[key] = String(value);
  saveEnvOverrides();
  log('info', 'Env override set via REST', { key, action: 'env.set' });
  res.json({ status: 'ok', key, value: String(value) });
});

app.delete('/env/:key', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const { key } = req.params;
  if (!(key in envOverrides)) {
    return res.status(404).json({ error: `Key "${key}" not found` });
  }
  delete envOverrides[key];
  saveEnvOverrides();
  log('info', 'Env override deleted via REST', { key, action: 'env.delete' });
  res.json({ status: 'ok', key });
});

const server = app.listen(PORT, () => {
  log('info', `Terminal Proxy Server running on port ${PORT}`);
  log('info', `Connected to OpenClaw container: ${OPENCLAW_CONTAINER}`);
});

// ── WebSocket server with security options ─────────────────────────────
const wss = new WebSocket.Server({
  server,
  maxPayload: 1 * 1024 * 1024, // 1 MB max message size
  verifyClient: (info, callback) => {
    // Validate WebSocket origin
    const origin = info.origin || info.req.headers.origin;
    if (!origin || allowedOrigins.includes(origin) || allowedOrigins.includes('*')) {
      callback(true);
    } else {
      log('warn', 'WebSocket connection rejected: invalid origin', { origin });
      callback(false, 403, 'Forbidden');
    }
  }
});

// ── Per-connection rate limiting ───────────────────────────────────────
const MSG_RATE_WINDOW = 10_000; // 10 seconds
const MSG_RATE_MAX = 30;        // max 30 messages per window

// ── Server-initiated heartbeat (detect dead connections) ───────────────
const HEARTBEAT_INTERVAL = 30_000; // 30 seconds
const heartbeatTimer = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      log('info', 'Terminating dead WebSocket connection');
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, HEARTBEAT_INTERVAL);

wss.on('close', () => {
  clearInterval(heartbeatTimer);
});

wss.on('connection', (ws, req) => {
  log('info', 'New WebSocket connection', { ip: req.socket.remoteAddress });

  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  let currentProcess = null;
  let authenticated = false;
  let userRole = 'guest';

  // Rate limiting state
  let msgTimestamps = [];

  ws.on('message', (message) => {
    // Rate limiting
    const now = Date.now();
    msgTimestamps = msgTimestamps.filter(t => t > now - MSG_RATE_WINDOW);
    if (msgTimestamps.length >= MSG_RATE_MAX) {
      safeSend(ws, { type: 'error', message: 'Rate limit exceeded. Slow down.' });
      return;
    }
    msgTimestamps.push(now);

    try {
      const data = JSON.parse(message);

      switch (data.type) {
        case 'auth':
          // Accept gateway token (legacy) or JWT with role
          if (data.token && timingSafeTokenCompare(data.token, GATEWAY_TOKEN)) {
            authenticated = true;
            // Gateway token always grants superadmin -- NEVER accept client-supplied role
            userRole = 'superadmin';
            safeSend(ws, {
              type: 'auth',
              status: 'ok',
              role: userRole,
              message: 'Authenticated successfully'
            });
          } else if (data.jwt && JWT_SECRET) {
            try {
              const decoded = jwt.verify(data.jwt, JWT_SECRET);
              authenticated = true;
              // Role comes ONLY from verified JWT claims -- NEVER from client-supplied data
              userRole = decoded.user_role || decoded.role || 'user';
              safeSend(ws, {
                type: 'auth',
                status: 'ok',
                role: userRole,
                message: 'Authenticated via JWT'
              });
            } catch (jwtErr) {
              safeSend(ws, {
                type: 'auth',
                status: 'error',
                message: 'Invalid JWT'
              });
            }
          } else {
            safeSend(ws, {
              type: 'auth',
              status: 'error',
              message: 'Invalid token'
            });
          }
          break;

        case 'exec':
          if (!authenticated) {
            safeSend(ws, { type: 'error', message: 'Not authenticated' });
            log('warn', 'Command rejected: not authenticated', { action: 'command.rejected' });
            return;
          }

          if (data.command) {
            const tier = getRoleTier(userRole);
            const validation = validateCommand(data.command);
            if (!isCommandAllowedForTier(validation.cleanCmd, tier)) {
              log('warn', 'Command denied: insufficient tier', {
                command: validation.cleanCmd,
                userRole,
                tier,
                action: 'command.denied'
              });
              safeSend(ws, {
                type: 'error',
                message: `Permission denied: "${validation.cleanCmd}" requires higher access (your role: ${userRole})`
              });
              safeSend(ws, { type: 'exit', code: 1, message: 'Permission denied' });
              break;
            }

            // Kill previous process before starting new one (prevent orphans)
            if (currentProcess) {
              try { currentProcess.kill('SIGKILL'); } catch (_) {}
              currentProcess = null;
            }

            log('info', 'Command executed', {
              command: validation.cleanCmd,
              userRole,
              tier,
              action: 'command.executed'
            });
            currentProcess = executeCommand(ws, data.command, GATEWAY_TOKEN);
          }
          break;

        case 'cancel':
          if (currentProcess) {
            try { currentProcess.kill('SIGTERM'); } catch (_) {}
            // Follow up with SIGKILL after 3 seconds if still alive
            const proc = currentProcess;
            setTimeout(() => {
              try { if (!proc.killed) proc.kill('SIGKILL'); } catch (_) {}
            }, 3000);
            safeSend(ws, { type: 'system', message: 'Command cancelled' });
            currentProcess = null;
          }
          break;

        // ── Dynamic environment variable management (superadmin only) ──
        case 'env_set': {
          if (!authenticated) {
            safeSend(ws, { type: 'error', message: 'Not authenticated' });
            break;
          }
          if (userRole !== 'superadmin') {
            safeSend(ws, { type: 'error', message: 'Permission denied: env management requires superadmin' });
            break;
          }
          const keyErr = validateEnvKey(data.key);
          if (keyErr) {
            safeSend(ws, { type: 'env_set', status: 'error', message: keyErr });
            break;
          }
          const valErr = validateEnvValue(data.value);
          if (valErr) {
            safeSend(ws, { type: 'env_set', status: 'error', message: valErr });
            break;
          }
          envOverrides[data.key] = String(data.value);
          saveEnvOverrides();
          log('info', 'Env override set', { key: data.key, userRole, action: 'env.set' });
          safeSend(ws, { type: 'env_set', status: 'ok', key: data.key, value: String(data.value) });
          break;
        }

        case 'env_delete': {
          if (!authenticated) {
            safeSend(ws, { type: 'error', message: 'Not authenticated' });
            break;
          }
          if (userRole !== 'superadmin') {
            safeSend(ws, { type: 'error', message: 'Permission denied: env management requires superadmin' });
            break;
          }
          if (!data.key || typeof data.key !== 'string') {
            safeSend(ws, { type: 'env_delete', status: 'error', message: 'Key is required' });
            break;
          }
          if (!(data.key in envOverrides)) {
            safeSend(ws, { type: 'env_delete', status: 'error', message: `Key "${data.key}" not found` });
            break;
          }
          delete envOverrides[data.key];
          saveEnvOverrides();
          log('info', 'Env override deleted', { key: data.key, userRole, action: 'env.delete' });
          safeSend(ws, { type: 'env_delete', status: 'ok', key: data.key });
          break;
        }

        case 'env_list': {
          if (!authenticated) {
            safeSend(ws, { type: 'error', message: 'Not authenticated' });
            break;
          }
          if (userRole !== 'superadmin') {
            safeSend(ws, { type: 'error', message: 'Permission denied: env management requires superadmin' });
            break;
          }
          safeSend(ws, { type: 'env_list', vars: { ...envOverrides } });
          break;
        }

        case 'ping':
          safeSend(ws, { type: 'pong' });
          break;

        default:
          safeSend(ws, { type: 'error', message: 'Unknown message type' });
      }
    } catch (err) {
      safeSend(ws, { type: 'error', message: 'Invalid JSON message' });
    }
  });

  ws.on('close', () => {
    log('info', 'WebSocket connection closed');
    if (currentProcess) {
      try { currentProcess.kill('SIGKILL'); } catch (_) {}
      currentProcess = null;
    }
  });

  ws.on('error', (err) => {
    log('error', 'WebSocket error', { error: err.message });
  });
});

// ── Graceful shutdown ──────────────────────────────────────────────────
function gracefulShutdown(signal) {
  log('info', `Received ${signal}, shutting down gracefully`);
  clearInterval(heartbeatTimer);

  // Close all WebSocket connections
  wss.clients.forEach((ws) => {
    safeSend(ws, { type: 'system', message: 'Server shutting down' });
    ws.terminate();
  });

  wss.close(() => {
    server.close(() => {
      log('info', 'Server closed');
      process.exit(0);
    });
  });

  // Force exit after 10 seconds
  setTimeout(() => {
    log('error', 'Forced shutdown after timeout');
    process.exit(1);
  }, 10_000).unref();
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// ── Global error handlers ──────────────────────────────────────────────
process.on('unhandledRejection', (reason) => {
  log('error', 'Unhandled rejection', { error: String(reason) });
});

process.on('uncaughtException', (err) => {
  log('error', 'Uncaught exception', { error: err.message, stack: err.stack });
  process.exit(1);
});

log('info', 'Terminal Proxy initialized');
