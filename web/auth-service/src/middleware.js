const jwt = require('jsonwebtoken');
const { ensureUserRole, getEffectivePermissions, getUserRoleName } = require('./rbac');

const JWT_SECRET = process.env.JWT_SECRET;
const GUEST_ROLE = 'guest';

function verifyToken(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    // No token -> guest
    req.user = { id: null, role: GUEST_ROLE, permissions: [], isGuest: true };
    return next();
  }

  const token = authHeader.substring(7);
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.user = {
      id: decoded.sub || decoded.user_id || decoded.id,
      email: decoded.email,
      role: decoded.role || decoded.user_role,
      raw: decoded,
      isGuest: false,
    };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
}

async function resolveRole(req, res, next) {
  if (req.user.isGuest) {
    req.user.role = GUEST_ROLE;
    req.user.permissions = [
      'chat.read', 'canvas.view', 'memory.read',
      'skills.list', 'crons.list', 'settings.read',
      'governance.view', 'terminal.exec.safe',
    ];
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
