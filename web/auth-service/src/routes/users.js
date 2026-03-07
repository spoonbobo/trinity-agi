const express = require('express');
const { requirePermission } = require('../middleware');
const { listUsers, assignRole, getUserRoleName, getRolePermissionMatrix, setRolePermissions } = require('../rbac');
const { writeAuditLogSafe, auditOptsFromReq, getAuditLog, streamAuditExport, ACTIONS } = require('../audit');

const router = express.Router();

// UUID v4 regex for input validation
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// Also accept guest:uuid format
const USER_ID_RE = /^(guest:)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /auth/users - list all users with roles (admin only)
router.get('/', requirePermission('users.list'), async (req, res) => {
  try {
    const users = await listUsers();
    res.json({ users });
  } catch (err) {
    console.error('[users] listUsers error:', err.message);
    res.status(500).json({ error: 'Failed to list users' });
  }
});

// POST /auth/users/:id/role - assign role (admin only)
router.post('/:id/role', requirePermission('users.manage'), async (req, res) => {
  try {
    // Validate user ID format
    if (!USER_ID_RE.test(req.params.id)) {
      return res.status(400).json({ error: 'Invalid user ID format' });
    }

    // Validate Content-Type
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'Content-Type must be application/json' });
    }

    const { role } = req.body || {};
    if (!role) return res.status(400).json({ error: 'role is required' });

    const allowedRoles = ['guest', 'user', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `Invalid role. Allowed: ${allowedRoles.join(', ')}` });
    }

    // Prevent self-demotion from superadmin
    if (req.params.id === req.user.id && req.user.role === 'superadmin') {
      return res.status(400).json({ error: 'Cannot change own superadmin role' });
    }

    // Prevent demoting a superadmin (only other superadmins can do this)
    const targetRole = await getUserRoleName(req.params.id);
    if (targetRole === 'superadmin' && req.user.role !== 'superadmin') {
      return res.status(403).json({ error: 'Only superadmins can change a superadmin\'s role' });
    }

    await assignRole(req.params.id, role, req.user.id);
    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.USERS_ROLE_ASSIGN,
      resource: `user:${req.params.id}`,
      metadata: { newRole: role, previousRole: targetRole },
    });

    res.json({ success: true, userId: req.params.id, role });
  } catch (err) {
    console.error('[users] assignRole error:', err.message);
    res.status(500).json({ error: 'Failed to assign role' });
  }
});

// GET /auth/users/audit - audit log with server-side filtering (admin only)
router.get('/audit', requirePermission('audit.read'), async (req, res) => {
  try {
    const limit = parseInt(req.query.limit || '100', 10);
    const offset = parseInt(req.query.offset || '0', 10);

    // Bounds are clamped inside getAuditLog, but reject obvious junk here
    if (isNaN(limit) || isNaN(offset)) {
      return res.status(400).json({ error: 'limit and offset must be numbers' });
    }

    const filters = {
      limit,
      offset,
      action: req.query.action || null,
      userId: req.query.user_id || null,
      resource: req.query.resource || null,
      ip: req.query.ip || null,
      from: req.query.from || null,
      to: req.query.to || null,
    };

    const result = await getAuditLog(filters);

    // Self-audit: log that the audit log was read
    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.AUDIT_READ,
      resource: 'audit_log',
      metadata: {
        filters: Object.fromEntries(
          Object.entries(filters).filter(([, v]) => v !== null)
        ),
        resultCount: result.logs.length,
      },
    });

    res.json(result);
  } catch (err) {
    console.error('[users] getAuditLog error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve audit log' });
  }
});

// GET /auth/users/audit/export - export audit log as CSV or NDJSON (admin only)
router.get('/audit/export', requirePermission('audit.read'), async (req, res) => {
  try {
    const format = (req.query.format || 'json').toLowerCase();
    if (!['json', 'csv'].includes(format)) {
      return res.status(400).json({ error: 'format must be "json" or "csv"' });
    }

    const filters = {
      action: req.query.action || null,
      userId: req.query.user_id || null,
      resource: req.query.resource || null,
      ip: req.query.ip || null,
      from: req.query.from || null,
      to: req.query.to || null,
    };

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const ext = format === 'csv' ? 'csv' : 'ndjson';
    const contentType = format === 'csv' ? 'text/csv' : 'application/x-ndjson';

    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Disposition', `attachment; filename="audit-export-${timestamp}.${ext}"`);

    // Self-audit: log export event
    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.AUDIT_EXPORT,
      resource: 'audit_log',
      metadata: { format, filters: Object.fromEntries(
        Object.entries(filters).filter(([, v]) => v !== null)
      )},
    });

    await streamAuditExport(res, filters, format);
    res.end();
  } catch (err) {
    console.error('[users] audit export error:', err.message);
    // If headers already sent, we can't send JSON error
    if (!res.headersSent) {
      res.status(500).json({ error: 'Failed to export audit log' });
    } else {
      res.end();
    }
  }
});

// GET /auth/users/roles/permissions - role-permission matrix (admin only)
router.get('/roles/permissions', requirePermission('users.list'), async (req, res) => {
  try {
    const matrix = await getRolePermissionMatrix();
    res.json(matrix);
  } catch (err) {
    console.error('[users] getRolePermissionMatrix error:', err.message);
    res.status(500).json({ error: 'Failed to retrieve role permissions' });
  }
});

// PUT /auth/users/roles/:role/permissions - update role permissions (admin only)
router.put('/roles/:role/permissions', requirePermission('users.manage'), async (req, res) => {
  try {
    // Validate Content-Type
    if (!req.is('application/json')) {
      return res.status(415).json({ error: 'Content-Type must be application/json' });
    }

    const { role } = req.params;
    const { permissions } = req.body || {};

    if (!permissions || !Array.isArray(permissions)) {
      return res.status(400).json({ error: 'permissions array is required' });
    }

    // Cap permissions array size to prevent DoS
    if (permissions.length > 100) {
      return res.status(400).json({ error: 'Too many permissions (max 100)' });
    }

    // Validate all entries are strings
    if (!permissions.every(p => typeof p === 'string' && p.length > 0 && p.length < 100)) {
      return res.status(400).json({ error: 'Each permission must be a non-empty string' });
    }

    // Prevent modifying superadmin permissions directly
    if (role === 'superadmin') {
      return res.status(400).json({ error: 'superadmin inherits all permissions and cannot be modified directly' });
    }

    const allowedRoles = ['guest', 'user', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `Invalid role. Allowed: ${allowedRoles.join(', ')}` });
    }

    await setRolePermissions(role, permissions);
    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.PERMISSIONS_UPDATED,
      resource: `role:${role}`,
      metadata: { permissions, count: permissions.length },
    });

    res.json({ success: true, role, permissions });
  } catch (err) {
    console.error('[users] setRolePermissions error:', err.message);
    res.status(500).json({ error: 'Failed to update role permissions' });
  }
});

module.exports = router;
