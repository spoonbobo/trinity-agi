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

// ── Multi-tenant K8s support ───────────────────────────────────────────
const EXEC_MODE = process.env.EXEC_MODE || 'docker'; // 'docker' or 'kubectl'
const ORCHESTRATOR_URL = process.env.ORCHESTRATOR_URL || '';
const ORCHESTRATOR_SERVICE_TOKEN = process.env.ORCHESTRATOR_SERVICE_TOKEN || '';
const K8S_NAMESPACE = process.env.NAMESPACE || 'trinity';
const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:18791';

// ── Dynamic environment variable overrides ─────────────────────────────
const ENV_OVERRIDES_PATH = process.env.ENV_OVERRIDES_PATH || path.join(__dirname, 'data', 'env-overrides.json');
const ENV_KEY_REGEX = /^[A-Za-z_][A-Za-z0-9_]*$/;
const ENV_KEY_MAX_LEN = 128;
const ENV_VALUE_MAX_LEN = 4096;
const ENV_BLOCKLIST = new Set([
  'OPENCLAW_GATEWAY_TOKEN', 'JWT_SECRET', 'PATH', 'HOME', 'USER',
  'NODE_ENV', 'DOCKER_HOST', 'HOSTNAME', 'TERMINAL_PROXY_PORT',
  'OPENCLAW_CONTAINER_NAME', 'ALLOWED_ORIGINS', 'SUPABASE_JWT_SECRET',
  'EXEC_MODE', 'ORCHESTRATOR_URL', 'ORCHESTRATOR_SERVICE_TOKEN', 'NAMESPACE',
]);

// envOverrides is now keyed by scope: { "_global": {...}, "oc:<id>": {...} }
// Docker mode uses "_global". Kubectl mode uses "oc:<openclawId>" with "_global" as fallback.
let envOverrides = {};

function _envScopeKey(openclawId) {
  return openclawId ? `oc:${openclawId}` : '_global';
}

function getEnvForScope(openclawId) {
  const global = envOverrides['_global'] || {};
  if (!openclawId) return { ...global };
  const scoped = envOverrides[_envScopeKey(openclawId)] || {};
  return { ...global, ...scoped };
}

// ── Env-to-gateway-config mapping ──────────────────────────────────────
// Maps environment variable names to OpenClaw config paths. Used by the
// env_sync_gateway handler to write values into the gateway config file
// via `openclaw config set`, so they survive gateway restarts.
const ENV_TO_CONFIG_MAP = {
  'BRAVE_API_KEY':       'tools.web.search.apiKey',
  'PERPLEXITY_API_KEY':  'tools.web.search.perplexity.apiKey',
  'OPENROUTER_API_KEY':  'tools.web.search.perplexity.apiKey',
  'GEMINI_API_KEY':      'tools.web.search.gemini.apiKey',
  'XAI_API_KEY':         'tools.web.search.grok.apiKey',
  'FIRECRAWL_API_KEY':   'tools.web.fetch.firecrawl.apiKey',
};

function loadEnvOverrides() {
  try {
    if (fs.existsSync(ENV_OVERRIDES_PATH)) {
      const raw = fs.readFileSync(ENV_OVERRIDES_PATH, 'utf8');
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
        // Migrate flat format (old single-claw) to scoped format
        const keys = Object.keys(parsed);
        const isScoped = keys.some(k => k.startsWith('oc:') || k === '_global');
        if (isScoped || keys.length === 0) {
          envOverrides = parsed;
        } else {
          // Old flat format: move everything under _global
          envOverrides = { '_global': parsed };
          log('info', 'Migrated flat env overrides to scoped format');
          saveEnvOverrides();
        }
        const totalScopes = Object.keys(envOverrides).length;
        const totalVars = Object.values(envOverrides).reduce((n, scope) => n + Object.keys(scope || {}).length, 0);
        log('info', `Loaded ${totalVars} env override(s) across ${totalScopes} scope(s) from disk`);
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

// ── RBAC role resolution via auth-service ──────────────────────────────
// GoTrue JWTs only contain role="authenticated". The real RBAC role
// (guest/user/admin/superadmin) must be resolved from the auth-service.
async function resolveRbacRole(jwtToken) {
  try {
    const res = await fetch(`${AUTH_SERVICE_URL}/auth/me`, {
      headers: { Authorization: `Bearer ${jwtToken}` },
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    return data.role || null;
  } catch (err) {
    log('warn', 'RBAC role resolution failed', { error: err.message });
    return null;
  }
}

// ── Startup validation ─────────────────────────────────────────────────
if (!GATEWAY_TOKEN || GATEWAY_TOKEN.length < 16) {
  console.error('[terminal-proxy] FATAL: OPENCLAW_GATEWAY_TOKEN must be set and >= 16 characters.');
  process.exit(1);
}

// ── Orchestrator pod resolver (K8s multi-tenant) ──────────────────────
// Caches resolved pods for 30s to avoid hammering the orchestrator on
// every command execution within the same connection.
const _podCache = new Map(); // key=userId, value={data, expiresAt}
const POD_CACHE_TTL = 30_000;

async function resolveUserPod(userId) {
  if (!ORCHESTRATOR_URL) throw new Error('ORCHESTRATOR_URL not configured');

  const cached = _podCache.get(userId);
  if (cached && cached.expiresAt > Date.now()) return cached.data;

  const res = await fetch(`${ORCHESTRATOR_URL}/resolve/${userId}`, {
    headers: { 'Authorization': `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` }
  });
  if (!res.ok) throw new Error(`Pod not found for user ${userId}: ${res.status}`);
  const data = await res.json(); // { host, port, token, podName }
  _podCache.set(userId, { data, expiresAt: Date.now() + POD_CACHE_TTL });
  return data;
}

// Resolve an OpenClaw instance pod by its ID (new shared model).
async function resolveOpenClawPod(openclawId) {
  if (!ORCHESTRATOR_URL) throw new Error('ORCHESTRATOR_URL not configured');

  const cacheKey = `oc:${openclawId}`;
  const cached = _podCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.data;

  const res = await fetch(`${ORCHESTRATOR_URL}/openclaws/${openclawId}/resolve`, {
    headers: { 'Authorization': `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` }
  });
  if (!res.ok) throw new Error(`OpenClaw ${openclawId} not found: ${res.status}`);
  const data = await res.json(); // { host, port, token, podName }
  _podCache.set(cacheKey, { data, expiresAt: Date.now() + POD_CACHE_TTL });
  return data;
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
// Build the argv array for Docker mode.
function _buildDockerArgs(validation, token, openclawId) {
  const args = ['exec'];

  if (validation.isInteractive) {
    args.push('-i');
  }

  // Inject dynamic env var overrides as -e flags (before container name)
  const scopedEnv = getEnvForScope(openclawId);
  for (const [k, v] of Object.entries(scopedEnv)) {
    args.push('-e', `${k}=${v}`);
  }

  if (validation.cleanCmd.startsWith('cat ')) {
    const filePath = validation.cleanCmd.substring(4).trim();
    args.push(OPENCLAW_CONTAINER, 'cat', filePath);
  } else if (validation.cleanCmd === 'clawhub' || validation.cleanCmd.startsWith('clawhub ')) {
    args.push(OPENCLAW_CONTAINER, 'clawhub', ...validation.cleanCmd.split(' ').slice(1));
  } else {
    args.push(OPENCLAW_CONTAINER, 'openclaw', ...validation.cleanCmd.split(' '));
  }

  return { bin: 'docker', args, env: { ...process.env, OPENCLAW_GATEWAY_TOKEN: token } };
}

// Build the argv array for kubectl mode.
function _buildKubectlArgs(validation, podName, podToken, openclawId) {
  const args = ['exec', '-i', podName, '-n', K8S_NAMESPACE, '--'];

  // kubectl exec doesn't support -e for env injection, so we prefix the
  // command with env KEY=VAL ... to achieve the same effect.
  const scopedEnv = getEnvForScope(openclawId);
  const envPrefix = [];
  for (const [k, v] of Object.entries(scopedEnv)) {
    envPrefix.push(`${k}=${v}`);
  }
  // Always inject the per-user gateway token
  envPrefix.push(`OPENCLAW_GATEWAY_TOKEN=${podToken}`);

  if (envPrefix.length > 0) {
    args.push('env', ...envPrefix);
  }

  if (validation.cleanCmd.startsWith('cat ')) {
    const filePath = validation.cleanCmd.substring(4).trim();
    args.push('cat', filePath);
  } else if (validation.cleanCmd === 'clawhub' || validation.cleanCmd.startsWith('clawhub ')) {
    args.push('clawhub', ...validation.cleanCmd.split(' ').slice(1));
  } else {
    args.push('openclaw', ...validation.cleanCmd.split(' '));
  }

  return { bin: 'kubectl', args, env: { ...process.env } };
}

// Spawn the child process and wire up ws streaming.
function _spawnAndStream(ws, bin, args, env, cleanCmd) {
  safeSend(ws, { type: 'system', message: `$ ${cleanCmd}` });

  const child = spawn(bin, args, { env });

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

// Main entry point -- dispatches to Docker or kubectl depending on EXEC_MODE.
// When using kubectl, podInfo must be pre-resolved via resolveUserPod().
// openclawId is used to scope env overrides to the correct claw.
function executeCommand(ws, cmd, token, podInfo, openclawId) {
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

  if (EXEC_MODE === 'kubectl') {
    if (!podInfo || !podInfo.podName) {
      safeSend(ws, { type: 'error', message: 'No pod resolved for this user' });
      safeSend(ws, { type: 'exit', code: 1, message: 'Pod resolution required' });
      return null;
    }
    const { bin, args, env } = _buildKubectlArgs(validation, podInfo.podName, podInfo.token || token, openclawId);
    return _spawnAndStream(ws, bin, args, env, validation.cleanCmd);
  }

  // Default: Docker mode (backward compatible)
  const { bin, args, env } = _buildDockerArgs(validation, token, openclawId);
  return _spawnAndStream(ws, bin, args, env, validation.cleanCmd);
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
// Optional ?openclawId= query param to scope to a specific claw
app.get('/env', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const ocId = req.query.openclawId || null;
  res.json({ vars: getEnvForScope(ocId) });
});

app.put('/env', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const { key, value, openclawId } = req.body;
  const keyErr = validateEnvKey(key);
  if (keyErr) return res.status(400).json({ error: keyErr });
  const valErr = validateEnvValue(value);
  if (valErr) return res.status(400).json({ error: valErr });
  const scopeKey = _envScopeKey(openclawId || null);
  if (!envOverrides[scopeKey]) envOverrides[scopeKey] = {};
  envOverrides[scopeKey][key] = String(value);
  saveEnvOverrides();
  log('info', 'Env override set via REST', { key, scope: scopeKey, action: 'env.set' });
  res.json({ status: 'ok', key, value: String(value) });
});

app.delete('/env/:key', (req, res) => {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!timingSafeTokenCompare(token, GATEWAY_TOKEN)) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  const { key } = req.params;
  const ocId = req.query.openclawId || null;
  const scopeKey = _envScopeKey(ocId);
  const scope = envOverrides[scopeKey] || {};
  if (!(key in scope)) {
    return res.status(404).json({ error: `Key "${key}" not found` });
  }
  delete scope[key];
  if (Object.keys(scope).length === 0) delete envOverrides[scopeKey];
  else envOverrides[scopeKey] = scope;
  saveEnvOverrides();
  log('info', 'Env override deleted via REST', { key, scope: scopeKey, action: 'env.delete' });
  res.json({ status: 'ok', key });
});

const server = app.listen(PORT, () => {
  log('info', `Terminal Proxy Server running on port ${PORT}`);
  if (EXEC_MODE === 'kubectl') {
    log('info', `Exec mode: kubectl (namespace: ${K8S_NAMESPACE})`);
    if (ORCHESTRATOR_URL) log('info', `Orchestrator: ${ORCHESTRATOR_URL}`);
    else log('warn', 'ORCHESTRATOR_URL not set -- pod resolution will fail');
  } else {
    log('info', `Exec mode: docker (container: ${OPENCLAW_CONTAINER})`);
  }
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
  let userId = null;      // Set from JWT `sub` claim (K8s pod routing)
  let openclawId = null;  // Set from auth handshake (per-claw routing)
  let resolvedPod = null;  // Cached pod info for kubectl mode

  // Rate limiting state
  let msgTimestamps = [];

  ws.on('message', async (message) => {
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
            openclawId = data.openclawId || null;

            // In kubectl mode, superadmin can target a specific user's pod
            // via data.targetUserId.  Without it, commands run against the
            // default Docker container (backward compatible).
            if (EXEC_MODE === 'kubectl' && data.targetUserId) {
              userId = data.targetUserId;
              resolveUserPod(userId)
                .then((pod) => {
                  resolvedPod = pod;
                  log('info', 'Superadmin targeting user pod', { userId, podName: pod.podName });
                  safeSend(ws, {
                    type: 'auth',
                    status: 'ok',
                    role: userRole,
                    message: `Authenticated successfully (targeting pod for ${userId})`
                  });
                })
                .catch((err) => {
                  log('error', 'Pod resolution failed for targetUserId', { userId, error: err.message });
                  safeSend(ws, {
                    type: 'auth',
                    status: 'ok',
                    role: userRole,
                    message: 'Authenticated successfully',
                    warning: `Could not resolve pod for ${userId}: ${err.message}`
                  });
                });
            } else {
              safeSend(ws, {
                type: 'auth',
                status: 'ok',
                role: userRole,
                message: 'Authenticated successfully'
              });
            }
          } else if (data.jwt && JWT_SECRET) {
            try {
              const decoded = jwt.verify(data.jwt, JWT_SECRET);
              authenticated = true;
              userId = decoded.sub || null;

              // Resolve RBAC role from auth-service (GoTrue JWT only has "authenticated")
              const rbacRole = await resolveRbacRole(data.jwt);
              userRole = rbacRole || decoded.user_role || decoded.role || 'user';

              // In kubectl mode, await pod resolution before sending auth ok.
              // Supports both legacy userId resolution and new openclawId resolution.
              openclawId = data.openclawId || null;
              if (EXEC_MODE === 'kubectl' && (openclawId || userId)) {
                try {
                  const pod = openclawId
                    ? await resolveOpenClawPod(openclawId)
                    : await resolveUserPod(userId);
                  resolvedPod = pod;
                  log('info', 'Pod resolved', { userId, openclawId, podName: pod.podName, role: userRole });
                  safeSend(ws, {
                    type: 'auth',
                    status: 'ok',
                    role: userRole,
                    openclawId: openclawId || null,
                    message: 'Authenticated via JWT (pod ready)'
                  });
                } catch (podErr) {
                  log('error', 'Pod resolution failed at auth', { userId, openclawId, error: podErr.message });
                  safeSend(ws, {
                    type: 'auth',
                    status: 'ok',
                    role: userRole,
                    message: 'Authenticated via JWT (pod pending)',
                    warning: 'Pod not yet available; commands may fail'
                  });
                }
              } else {
                safeSend(ws, {
                  type: 'auth',
                  status: 'ok',
                  role: userRole,
                  message: 'Authenticated via JWT'
                });
              }
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
              execMode: EXEC_MODE,
              action: 'command.executed'
            });

            // In kubectl mode, resolve pod on-demand if not already cached
            if (EXEC_MODE === 'kubectl' && !resolvedPod && (openclawId || userId)) {
              const resolveFn = openclawId
                ? () => resolveOpenClawPod(openclawId)
                : () => resolveUserPod(userId);
              resolveFn()
                .then((pod) => {
                  resolvedPod = pod;
                  currentProcess = executeCommand(ws, data.command, GATEWAY_TOKEN, resolvedPod, openclawId);
                })
                .catch((err) => {
                  log('error', 'Pod resolution failed during exec', { openclawId, userId, error: err.message });
                  safeSend(ws, { type: 'error', message: `Cannot resolve pod: ${err.message}` });
                  safeSend(ws, { type: 'exit', code: 1, message: 'Pod resolution failed' });
                });
            } else {
              currentProcess = executeCommand(ws, data.command, GATEWAY_TOKEN, resolvedPod, openclawId);
            }
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
          const scopeKey = _envScopeKey(openclawId);
          if (!envOverrides[scopeKey]) envOverrides[scopeKey] = {};
          envOverrides[scopeKey][data.key] = String(data.value);
          saveEnvOverrides();
          log('info', 'Env override set', { key: data.key, scope: scopeKey, userRole, action: 'env.set' });
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
          const delScopeKey = _envScopeKey(openclawId);
          const delScope = envOverrides[delScopeKey] || {};
          if (!(data.key in delScope)) {
            safeSend(ws, { type: 'env_delete', status: 'error', message: `Key "${data.key}" not found` });
            break;
          }
          delete delScope[data.key];
          if (Object.keys(delScope).length === 0) delete envOverrides[delScopeKey];
          else envOverrides[delScopeKey] = delScope;
          saveEnvOverrides();
          log('info', 'Env override deleted', { key: data.key, scope: delScopeKey, userRole, action: 'env.delete' });
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
          safeSend(ws, { type: 'env_list', vars: getEnvForScope(openclawId) });
          break;
        }

        // ── Sync env overrides into the gateway config + restart ──────
        case 'env_sync_gateway': {
          if (!authenticated) {
            safeSend(ws, { type: 'error', message: 'Not authenticated' });
            break;
          }
          if (userRole !== 'superadmin') {
            safeSend(ws, { type: 'env_sync_gateway', status: 'error', message: 'Permission denied: requires superadmin' });
            break;
          }

          const synced = [];
          const skipped = [];
          const errors = [];

          // Collect mappable vars from the scoped env for this claw
          const syncEnv = getEnvForScope(openclawId);
          for (const [envKey, envVal] of Object.entries(syncEnv)) {
            const configPath = ENV_TO_CONFIG_MAP[envKey];
            if (configPath) {
              synced.push({ key: envKey, configPath, value: envVal });
            } else {
              skipped.push(envKey);
            }
          }

          if (synced.length === 0) {
            safeSend(ws, {
              type: 'env_sync_gateway',
              status: 'ok',
              synced: [],
              skipped,
              message: 'no gateway-mappable env vars to sync',
            });
            break;
          }

          // Run config set for each mapped var sequentially
          const runConfigSet = (configPath, value) => {
            return new Promise((resolve, reject) => {
              let bin, args, env;
              if (EXEC_MODE === 'kubectl' && resolvedPod && resolvedPod.podName) {
                bin = 'kubectl';
                args = ['exec', '-i', resolvedPod.podName, '-n', K8S_NAMESPACE, '--',
                  'env', `OPENCLAW_GATEWAY_TOKEN=${resolvedPod.token || GATEWAY_TOKEN}`,
                  'openclaw', 'config', 'set', configPath, value];
                env = { ...process.env };
              } else {
                bin = 'docker';
                args = ['exec', OPENCLAW_CONTAINER, 'openclaw', 'config', 'set', configPath, value];
                env = { ...process.env, OPENCLAW_GATEWAY_TOKEN: GATEWAY_TOKEN };
              }
              const child = spawn(bin, args, { env });
              let stderr = '';
              child.stderr.on('data', (d) => { stderr += d.toString(); });
              child.on('close', (code) => {
                if (code === 0) resolve();
                else reject(new Error(`config set ${configPath} failed (exit ${code}): ${stderr.trim()}`));
              });
              child.on('error', reject);
            });
          };

          // Restart gateway -- Docker restarts the container; kubectl does
          // a rollout restart of the pod's parent deployment.
          const runGatewayRestart = () => {
            return new Promise((resolve, reject) => {
              let bin, args;
              if (EXEC_MODE === 'kubectl' && resolvedPod && resolvedPod.podName) {
                // kubectl rollout restart targets the deployment, not the pod
                // Pod names follow the pattern <deployment>-<hash>-<hash>,
                // but we delete the pod to force a reschedule instead.
                bin = 'kubectl';
                args = ['delete', 'pod', resolvedPod.podName, '-n', K8S_NAMESPACE];
              } else {
                bin = 'docker';
                args = ['restart', OPENCLAW_CONTAINER];
              }
              const child = spawn(bin, args);
              let stderr = '';
              child.stderr.on('data', (d) => { stderr += d.toString(); });
              child.on('close', (code) => {
                if (code === 0) {
                  // Clear cached pod since it will be replaced
                  if (EXEC_MODE === 'kubectl') {
                    resolvedPod = null;
                    if (userId) _podCache.delete(userId);
                    if (openclawId) _podCache.delete(`oc:${openclawId}`);
                  }
                  resolve();
                }
                else reject(new Error(`restart failed (exit ${code}): ${stderr.trim()}`));
              });
              child.on('error', reject);
            });
          };

          // Execute all config sets, then restart
          (async () => {
            for (const item of synced) {
              try {
                await runConfigSet(item.configPath, item.value);
                log('info', 'Env synced to gateway config', { key: item.key, configPath: item.configPath, action: 'env.sync' });
              } catch (err) {
                errors.push(`${item.key}: ${err.message}`);
                log('error', 'Env sync config set failed', { key: item.key, configPath: item.configPath, error: err.message });
              }
            }

            if (errors.length > 0) {
              safeSend(ws, {
                type: 'env_sync_gateway',
                status: 'error',
                synced: synced.filter(s => !errors.some(e => e.startsWith(s.key + ':'))).map(s => s.key),
                skipped,
                errors,
                message: `${errors.length} config set(s) failed`,
              });
              return;
            }

            // All config sets succeeded -- restart gateway
            try {
              await runGatewayRestart();
              log('info', 'Gateway restart triggered after env sync', { syncedCount: synced.length, action: 'env.sync.restart' });
              safeSend(ws, {
                type: 'env_sync_gateway',
                status: 'ok',
                synced: synced.map(s => s.key),
                skipped,
                message: `synced ${synced.length} var(s) to gateway config, restarting`,
              });
            } catch (err) {
              log('error', 'Gateway restart failed after env sync', { error: err.message });
              safeSend(ws, {
                type: 'env_sync_gateway',
                status: 'error',
                synced: synced.map(s => s.key),
                skipped,
                errors: [err.message],
                message: `config set succeeded but gateway restart failed: ${err.message}`,
              });
            }
          })();
          break;
        }

        case 'ping':
          safeSend(ws, { type: 'pong' });
          break;

        default:
          safeSend(ws, { type: 'error', message: 'Unknown message type' });
      }
    } catch (err) {
      log('error', 'Message handling error', { error: err.message, stack: err.stack?.split('\n')[0] });
      safeSend(ws, { type: 'error', message: `Message error: ${err.message}` });
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
