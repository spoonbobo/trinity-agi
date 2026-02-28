const jwt = require('jsonwebtoken');
const { ensureUserRole, getEffectivePermissions, getUserRoleName, writeAuditLog } = require('./rbac');
const { getPermissionsByTier } = require('./rbac-registry');

const JWT_SECRET = process.env.JWT_SECRET;
const GUEST_ROLE = 'guest';

function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'auth-service',
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
    log('info', 'login: success', { userId, email: decoded.email, action: 'login.success' });
    next();
  } catch (err) {
    log('warn', 'login: failed', { error: err.message, action: 'login.failed' });
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
    console.error('[auth] Role resolution error:', err.message);
    req.user.role = 'user';
    req.user.permissions = [];
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
      writeAuditLog(req.user.id, 'permission.denied', action, { role: req.user.role }, req.ip);
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
