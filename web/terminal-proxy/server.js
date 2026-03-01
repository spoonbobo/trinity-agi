const WebSocket = require('ws');
const express = require('express');
const cors = require('cors');
const Docker = require('dockerode');
const { spawn } = require('child_process');
const path = require('path');
const { getRoleTier, isCommandAllowedForTier, getAllowedCommands, getInteractiveCommands } = require('./rbac-registry');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const PORT = process.env.TERMINAL_PROXY_PORT || 18790;
const GATEWAY_TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;
const JWT_SECRET = process.env.JWT_SECRET;
const OPENCLAW_CONTAINER = process.env.OPENCLAW_CONTAINER_NAME || 'trinity-openclaw';

function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'terminal-proxy',
    ...meta,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

const docker = new Docker();

// Allowed OpenClaw commands (whitelist) - now loaded from registry
// Interactive commands - now loaded from registry

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

  const baseCmd = cleanCmd.split(' ')[0];
  const allowedCommands = getAllowedCommands();
  
  const isAllowed = allowedCommands.some(allowed => {
    return cleanCmd.startsWith(allowed) || baseCmd === allowed.split(' ')[0];
  });
  
  return {
    isAllowed,
    isInteractive: getInteractiveCommands().some(ic => cleanCmd.startsWith(ic)),
    cleanCmd,
    baseCmd
  };
}

function executeCommand(ws, cmd, token) {
  const validation = validateCommand(cmd);
  
  if (!validation.isAllowed) {
    ws.send(JSON.stringify({
      type: 'error',
      message: `Command not allowed: ${validation.cleanCmd}. Only OpenClaw commands are permitted.`
    }));
    ws.send(JSON.stringify({
      type: 'exit',
      code: 1,
      message: 'Command rejected'
    }));
    return;
  }

  if (token !== GATEWAY_TOKEN) {
    ws.send(JSON.stringify({
      type: 'error',
      message: 'Invalid authentication token'
    }));
    ws.send(JSON.stringify({
      type: 'exit',
      code: 1,
      message: 'Authentication failed'
    }));
    return;
  }

  // Execute via docker exec
  const dockerCmd = ['exec'];
  
  if (validation.isInteractive) {
    dockerCmd.push('-it');
  }
  
  if (validation.cleanCmd.startsWith('cat ')) {
    const filePath = validation.cleanCmd.substring(4).trim();
    dockerCmd.push(OPENCLAW_CONTAINER, 'cat', filePath);
  } else if (validation.cleanCmd === 'clawhub' || validation.cleanCmd.startsWith('clawhub ')) {
    dockerCmd.push(OPENCLAW_CONTAINER, 'clawhub', ...validation.cleanCmd.split(' ').slice(1));
  } else {
    dockerCmd.push(OPENCLAW_CONTAINER, 'openclaw', ...validation.cleanCmd.split(' '));
  }

  ws.send(JSON.stringify({
    type: 'system',
    message: `$ ${validation.cleanCmd}`
  }));

  const child = spawn('docker', dockerCmd, {
    env: { ...process.env, OPENCLAW_GATEWAY_TOKEN: token }
  });

  child.stdout.on('data', (data) => {
    ws.send(JSON.stringify({
      type: 'stdout',
      data: data.toString()
    }));
  });

  child.stderr.on('data', (data) => {
    ws.send(JSON.stringify({
      type: 'stderr',
      data: data.toString()
    }));
  });

  child.on('close', (code) => {
    ws.send(JSON.stringify({
      type: 'exit',
      code: code,
      message: code === 0 ? 'Command completed successfully' : `Command exited with code ${code}`
    }));
  });

  child.on('error', (err) => {
    ws.send(JSON.stringify({
      type: 'error',
      message: `Failed to execute command: ${err.message}`
    }));
  });

  return child;
}

const helmet = require('helmet');

const app = express();
app.use(helmet());

// CORS with origin restriction
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowedOrigins.includes(origin) || allowedOrigins.includes('*')) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true,
}));

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'terminal-proxy' });
});

// Get allowed commands list
app.get('/commands', (req, res) => {
  res.json({
    allowed: getAllowedCommands(),
    interactive: getInteractiveCommands()
  });
});

const server = app.listen(PORT, () => {
  console.log(`Terminal Proxy Server running on port ${PORT}`);
  console.log(`Connected to OpenClaw container: ${OPENCLAW_CONTAINER}`);
});

const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  console.log('New WebSocket connection from:', req.socket.remoteAddress);
  
  let currentProcess = null;
  let authenticated = false;
  let userRole = 'guest';
  
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case 'auth':
          // Accept gateway token (legacy) or JWT with role
          if (data.token === GATEWAY_TOKEN) {
            authenticated = true;
            userRole = data.role || 'superadmin'; // gateway token = superadmin (highest privilege)
            ws.send(JSON.stringify({
              type: 'auth',
              status: 'ok',
              role: userRole,
              message: 'Authenticated successfully'
            }));
          } else if (data.jwt && JWT_SECRET) {
            try {
              const jwt = require('jsonwebtoken');
              const decoded = jwt.verify(data.jwt, JWT_SECRET);
              authenticated = true;
              userRole = data.role || decoded.user_role || decoded.role || 'user';
              ws.send(JSON.stringify({
                type: 'auth',
                status: 'ok',
                role: userRole,
                message: 'Authenticated via JWT'
              }));
            } catch (jwtErr) {
              ws.send(JSON.stringify({
                type: 'auth',
                status: 'error',
                message: 'Invalid JWT'
              }));
            }
          } else {
            ws.send(JSON.stringify({
              type: 'auth',
              status: 'error',
              message: 'Invalid token'
            }));
          }
          break;
          
        case 'exec':
          if (!authenticated) {
            ws.send(JSON.stringify({
              type: 'error',
              message: 'Not authenticated'
            }));
            log('warn', 'command rejected: not authenticated', { action: 'command.rejected' });
            return;
          }
          
          if (data.command) {
            const tier = getRoleTier(userRole);
            const validation = validateCommand(data.command);
            if (!isCommandAllowedForTier(validation.cleanCmd, tier)) {
              log('warn', 'command denied: insufficient tier', { 
                command: validation.cleanCmd, 
                userRole, 
                tier,
                action: 'command.denied'
              });
              ws.send(JSON.stringify({
                type: 'error',
                message: `Permission denied: "${validation.cleanCmd}" requires higher access (your role: ${userRole})`
              }));
              ws.send(JSON.stringify({
                type: 'exit',
                code: 1,
                message: 'Permission denied'
              }));
              break;
            }
            log('info', 'command executed', { 
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
            currentProcess.kill();
            ws.send(JSON.stringify({
              type: 'system',
              message: 'Command cancelled'
            }));
          }
          break;
          
        case 'ping':
          ws.send(JSON.stringify({ type: 'pong' }));
          break;
          
        default:
          ws.send(JSON.stringify({
            type: 'error',
            message: `Unknown message type: ${data.type}`
          }));
      }
    } catch (err) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid JSON message'
      }));
    }
  });
  
  ws.on('close', () => {
    console.log('WebSocket connection closed');
    if (currentProcess) {
      currentProcess.kill();
    }
  });
  
  ws.on('error', (err) => {
    console.error('WebSocket error:', err);
  });
});

console.log('Terminal Proxy initialized');
