const express = require('express');
const cors = require('cors');
const { ensureRole } = require('./rbac');
const { verifyToken, resolveRole } = require('./middleware');
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.AUTH_SERVICE_PORT || '18791');

app.use(cors());
app.use(express.json());

// Health check (no auth)
app.get('/auth/health', (req, res) => {
  res.json({ status: 'ok', service: 'trinity-auth' });
});

// Auth middleware for all /auth/* routes (except health)
app.use('/auth', verifyToken, resolveRole);

// Routes
app.use('/auth', authRoutes);
app.use('/auth/users', usersRoutes);

async function ensureDefaultSuperadmin() {
  const enabled = (process.env.ENABLE_DEFAULT_SUPERADMIN || 'true') === 'true';
  if (!enabled) return;

  const rawEmail = process.env.DEFAULT_SUPERADMIN_EMAIL || 'admin@trinity.local';
  const email = rawEmail.includes('@') ? rawEmail : `${rawEmail}@trinity.local`;
  const password = process.env.DEFAULT_SUPERADMIN_PASSWORD || 'admin';
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

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[auth-service] listening on port ${PORT}`);
  ensureDefaultSuperadmin();
});
