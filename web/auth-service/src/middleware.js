const jwt = require('jsonwebtoken');
const { ensureUserRole, getEffectivePermissions, getUserRoleName } = require('./rbac');
const { writeAuditLogSafe, auditOptsFromReq, ACTIONS } = require('./audit');
const { getPermissionsByTier } = require('./rbac-registry');

const JWT_SECRET = process.env.JWT_SECRET;
const GUEST_ROLE = 'guest';

// Validate JWT_SECRET at module load time
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  console.error('[auth-service] FATAL: JWT_SECRET must be set and >= 32 characters.');
  process.exit(1);
}

function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'auth-service',
    message,
    ...meta,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    req.user = { id: null, role: GUEST_ROLE, permissions: [], isGuest: true };
    return next();
  }

  const token = authHeader.substring(7);
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    const userId = decoded.sub || decoded.user_id || decoded.id;
    req.user = {
      id: userId,
      email: decoded.email,
      role: decoded.role || decoded.user_role,
      raw: decoded,
      isGuest: false,
    };
    // Audit login success for session-creation endpoints
    const sessionPaths = ['/auth/me'];
    if (sessionPaths.some(p => req.path === p || req.originalUrl?.startsWith(p))) {
      writeAuditLogSafe({
        userId,
        action: ACTIONS.AUTH_LOGIN_SUCCESS,
        resource: `user:${userId}`,
        metadata: { email: decoded.email || null },
        ip: req.ip,
        userAgent: req.get('user-agent') || null,
        requestPath: req.originalUrl ? req.originalUrl.split('?')[0] : req.path,
        httpMethod: req.method,
      });
    }
    next();
  } catch (err) {
    log('warn', 'login: failed', { error: err.message, action: 'login.failed' });

    // Audit: log failed login attempt
    const auditAction = err.name === 'TokenExpiredError'
      ? ACTIONS.AUTH_TOKEN_EXPIRED
      : ACTIONS.AUTH_LOGIN_FAILED;
    writeAuditLogSafe({
      userId: null,
      action: auditAction,
      resource: null,
      metadata: { error: err.message, errorType: err.name },
      ip: req.ip,
      userAgent: req.get('user-agent') || null,
      requestPath: req.originalUrl ? req.originalUrl.split('?')[0] : req.path,
      httpMethod: req.method,
    });

    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
}

async function resolveRole(req, res, next) {
  if (req.user.isGuest) {
    req.user.role = GUEST_ROLE;
    req.user.permissions = getPermissionsByTier('safe');
    return next();
  }

  try {
    const role = await ensureUserRole(req.user.id);
    req.user.role = role;
    const permissions = await getEffectivePermissions(req.user.id);
    req.user.permissions = permissions;
    next();
  } catch (err) {
    // On DB failure, fail closed: assign guest with safe-tier permissions only
    console.error('[auth] Role resolution error:', err.message);
    req.user.role = GUEST_ROLE;
    req.user.permissions = getPermissionsByTier('safe');
    next();
  }
}

function requirePermission(action) {
  return (req, res, next) => {
    if (!req.user.permissions.includes(action)) {
      log('warn', 'permission denied', { 
        userId: req.user.id, 
        required: action, 
        role: req.user.role,
        ip: req.ip,
        action: 'permission.denied'
      });
      // Best-effort audit log with full request context
      writeAuditLogSafe({
        ...auditOptsFromReq(req),
        action: ACTIONS.PERMISSION_DENIED,
        resource: action,
        metadata: { role: req.user.role },
      });
      return res.status(403).json({
        error: 'Forbidden',
        required: action,
        role: req.user.role,
      });
    }
    next();
  };
}

function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({
        error: 'Forbidden',
        required_role: roles,
        current_role: req.user.role,
      });
    }
    next();
  };
}

module.exports = { verifyToken, resolveRole, requirePermission, requireRole };
