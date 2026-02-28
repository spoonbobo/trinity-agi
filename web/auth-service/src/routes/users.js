const express = require('express');
const { requirePermission } = require('../middleware');
const { listUsers, assignRole, writeAuditLog, getAuditLog } = require('../rbac');

const router = express.Router();

// GET /auth/users - list all users with roles (admin only)
router.get('/', requirePermission('users.list'), async (req, res) => {
  try {
    const users = await listUsers();
    res.json({ users });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /auth/users/:id/role - assign role (admin only)
router.post('/:id/role', requirePermission('users.manage'), async (req, res) => {
  try {
    const { role } = req.body;
    if (!role) return res.status(400).json({ error: 'role is required' });

    const allowedRoles = ['guest', 'user', 'admin'];
    if (!allowedRoles.includes(role)) {
      return res.status(400).json({ error: `Invalid role. Allowed: ${allowedRoles.join(', ')}` });
    }

    // Prevent self-demotion from superadmin
    if (req.params.id === req.user.id && req.user.role === 'superadmin') {
      return res.status(400).json({ error: 'Cannot change own superadmin role' });
    }

    await assignRole(req.params.id, role, req.user.id);
    await writeAuditLog(
      req.user.id,
      'users.role.assign',
      `user:${req.params.id}`,
      { newRole: role },
      req.ip
    );

    res.json({ success: true, userId: req.params.id, role });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /auth/audit - audit log (admin only)
router.get('/audit', requirePermission('audit.read'), async (req, res) => {
  try {
    const limit = parseInt(req.query.limit || '100');
    const offset = parseInt(req.query.offset || '0');
    const logs = await getAuditLog(limit, offset);
    res.json({ logs });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
