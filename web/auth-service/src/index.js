const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { ensureRole } = require('./rbac');
const { pool } = require('./db');
const { verifyToken, resolveRole } = require('./middleware');
const { auditContext } = require('./audit');
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.AUTH_SERVICE_PORT || '18791', 10);

// Security: helmet for standard security headers (API-only service, strict CSP)
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'none'"],
    },
  },
  hsts: {
    maxAge: 31536000,
    includeSubDomains: true,
  },
}));

// Security: CORS with origin restriction (reject wildcard with credentials)
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (server-to-server, curl, etc.)
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true,
}));

app.use(express.json({ limit: '100kb' }));

// Rate limiting on auth endpoints
const authLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 10,
  message: { error: 'Too many auth requests, try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

const guestLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { error: 'Too many guest token requests, try again later' },
  standardHeaders: true,
  legacyHeaders: false,
});

// Health check (no auth, no rate limit)
app.get('/auth/health', (req, res) => {
  res.json({
    status: 'ok',
    service: 'trinity-auth',
    uptime: Math.floor(process.uptime()),
    version: process.env.npm_package_version || '1.0.0',
  });
});

// Rate limit guest endpoint specifically
app.post('/auth/guest', guestLimiter);

// Audit context middleware: captures IP, User-Agent, path, method on every request
app.use(auditContext());

// Auth middleware for all /auth/* routes (except health and guest)
app.use('/auth', verifyToken, resolveRole);

// Routes
app.use('/auth', authRoutes);
app.use('/auth/users', usersRoutes);

async function ensureDefaultSuperadmin() {
  const enabled = (process.env.ENABLE_DEFAULT_SUPERADMIN || 'false') === 'true';
  if (!enabled) return;

  const rawEmail = process.env.DEFAULT_SUPERADMIN_EMAIL || 'admin@trinity.local';
  const email = rawEmail.includes('@') ? rawEmail : `${rawEmail}@trinity.local`;
  const password = process.env.DEFAULT_SUPERADMIN_PASSWORD;

  if (!password || password === 'admin' || password.length < 8) {
    console.error('[auth-service] DEFAULT_SUPERADMIN_PASSWORD must be set to a value >= 8 chars (not "admin"). Skipping superadmin bootstrap.');
    return;
  }

  const gotrueUrl = process.env.SUPABASE_AUTH_URL || 'http://supabase-auth:9999';
  const anonKey = process.env.SUPABASE_ANON_KEY || '';
  
  const allowlist = (process.env.SUPERADMIN_ALLOWLIST || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

  if (allowlist.length === 0) {
    console.warn('[auth-service] SUPERADMIN_ALLOWLIST is empty - no users will receive superadmin role');
    return;
  }

  try {
    let userId = null;

    for (const emailOrId of [email, ...allowlist]) {
      if (!emailOrId.includes('@')) {
        userId = emailOrId;
        break;
      }
      
      const signupResp = await fetch(`${gotrueUrl}/signup`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(anonKey ? { apikey: anonKey } : {}),
        },
        body: JSON.stringify({ email: emailOrId, password }),
      });

      const signupText = await signupResp.text();
      if (signupText) {
        try {
          const signupJson = JSON.parse(signupText);
          const foundId = signupJson?.user?.id || null;
          if (foundId && allowlist.includes(foundId)) {
            userId = foundId;
            break;
          }
        } catch (_) {}
      }

      if (!userId) {
        const tokenResp = await fetch(`${gotrueUrl}/token?grant_type=password`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(anonKey ? { apikey: anonKey } : {}),
          },
          body: JSON.stringify({ email: emailOrId, password }),
        });
        if (tokenResp.ok) {
          const tokenJson = await tokenResp.json();
          const foundId = tokenJson?.user?.id || null;
          if (foundId && allowlist.includes(foundId)) {
            userId = foundId;
            break;
          }
        }
      }
    }

    if (!userId) {
      console.warn(`[auth-service] No user from SUPERADMIN_ALLOWLIST found`);
      return;
    }

    if (!allowlist.includes(userId)) {
      console.warn(`[auth-service] User ${userId} is not in SUPERADMIN_ALLOWLIST - refusing to grant superadmin`);
      return;
    }

    await ensureRole(userId, 'superadmin', null);
    await ensureRole(userId, 'admin', null);
    await ensureRole(userId, 'user', null);
    await ensureRole(userId, 'guest', null);

    console.log(`[auth-service] Superadmin ensured: ${userId} (from allowlist)`);
  } catch (err) {
    console.warn('[auth-service] Default superadmin bootstrap failed:', err.message);
  }
}

// ── Server start ───────────────────────────────────────────────────────
let serverInstance;

async function start() {
  // Run superadmin bootstrap BEFORE accepting requests
  await ensureDefaultSuperadmin();

  serverInstance = app.listen(PORT, '0.0.0.0', () => {
    console.log(`[auth-service] listening on port ${PORT}`);
  });
}

start().catch((err) => {
  console.error('[auth-service] Failed to start:', err.message);
  process.exit(1);
});

// ── Graceful shutdown ──────────────────────────────────────────────────
function gracefulShutdown(signal) {
  console.log(`[auth-service] Received ${signal}, shutting down gracefully`);
  if (serverInstance) {
    serverInstance.close(() => {
      pool.end().then(() => {
        console.log('[auth-service] Closed');
        process.exit(0);
      }).catch(() => process.exit(0));
    });
  } else {
    process.exit(0);
  }
  // Force exit after 10 seconds
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  console.error('[auth-service] Unhandled rejection:', String(reason));
});
