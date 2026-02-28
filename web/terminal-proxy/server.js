const WebSocket = require('ws');
const express = require('express');
const cors = require('cors');
const Docker = require('dockerode');
const { spawn } = require('child_process');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const PORT = process.env.TERMINAL_PROXY_PORT || 18790;
const GATEWAY_TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;
const OPENCLAW_CONTAINER = process.env.OPENCLAW_CONTAINER_NAME || 'trinity-openclaw';

const docker = new Docker();

// Allowed OpenClaw commands (whitelist)
const ALLOWED_COMMANDS = [
  'status',
  'health',
  'doctor',
  'doctor --fix',
  'models',
  'skills',
  'skills list',
  'skills list --json',
  'cron',
  'cron list',
  'cron list --json',
  'configure',
  'onboard',
  'dashboard',
  'sessions list',
  'logs',
  'channels',
  'tools',
  'memory',
  'config get',
  'config set',
  'config validate',
];

// Commands that require interactive mode (TTY)
const INTERACTIVE_COMMANDS = [
  'configure',
  'onboard',
  'channels login',
];

function validateCommand(cmd) {
  // Remove 'openclaw ' prefix if present
  const cleanCmd = cmd.replace(/^openclaw\s+/, '').trim();
  const baseCmd = cleanCmd.split(' ')[0];
  
  // Check if command starts with allowed base command
  const isAllowed = ALLOWED_COMMANDS.some(allowed => {
    return cleanCmd.startsWith(allowed) || baseCmd === allowed.split(' ')[0];
  });
  
  return {
    isAllowed,
    isInteractive: INTERACTIVE_COMMANDS.some(ic => cleanCmd.startsWith(ic)),
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
  
  dockerCmd.push(OPENCLAW_CONTAINER, 'openclaw', ...validation.cleanCmd.split(' '));

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

const app = express();
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'terminal-proxy' });
});

// Get allowed commands list
app.get('/commands', (req, res) => {
  res.json({
    allowed: ALLOWED_COMMANDS,
    interactive: INTERACTIVE_COMMANDS
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
  
  ws.on('message', (message) => {
    try {
      const data = JSON.parse(message);
      
      switch (data.type) {
        case 'auth':
          if (data.token === GATEWAY_TOKEN) {
            authenticated = true;
            ws.send(JSON.stringify({
              type: 'auth',
              status: 'ok',
              message: 'Authenticated successfully'
            }));
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
            return;
          }
          
          if (data.command) {
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
