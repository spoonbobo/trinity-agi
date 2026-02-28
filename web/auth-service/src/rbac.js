const { pool } = require('./db');

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

async function getEffectivePermissions(userId) {
  const result = await pool.query(
    'SELECT action FROM rbac.effective_permissions($1)',
    [userId]
  );
  return result.rows.map(r => r.action);
}

async function hasPermission(userId, action) {
  const result = await pool.query(
    'SELECT rbac.has_permission($1, $2) AS allowed',
    [userId, action]
  );
  return result.rows[0]?.allowed === true;
}

async function getUserRoleName(userId) {
  const result = await pool.query(
    'SELECT rbac.user_role_name($1) AS role_name',
    [userId]
  );
  return result.rows[0]?.role_name || null;
}

async function assignRole(userId, roleName, grantedBy) {
  const roleResult = await pool.query(
    'SELECT id FROM rbac.roles WHERE name = $1',
    [roleName]
  );
  if (roleResult.rows.length === 0) throw new Error(`Role not found: ${roleName}`);

  await pool.query('DELETE FROM rbac.user_roles WHERE user_id = $1', [userId]);

  await pool.query(
    'INSERT INTO rbac.user_roles (user_id, role_id, granted_by) VALUES ($1, $2, $3)',
    [userId, roleResult.rows[0].id, grantedBy]
  );

  log('info', 'RBAC: role assigned', { userId, role: roleName, grantedBy, action: 'role.assigned' });
  
  await writeAuditLog(grantedBy, 'role.assigned', `user:${userId}`, { role: roleName }, null);
}

async function ensureUserRole(userId, defaultRole = 'user') {
  const existing = await getUserRoleName(userId);
  if (!existing) {
    await assignRole(userId, defaultRole, null);
    return defaultRole;
  }
  return existing;
}

async function listUsers() {
  const result = await pool.query(`
    SELECT
      ur.user_id,
      r.name AS role_name,
      ur.granted_at
    FROM rbac.user_roles ur
    JOIN rbac.roles r ON r.id = ur.role_id
    ORDER BY ur.granted_at DESC
  `);
  return result.rows;
}

async function writeAuditLog(userId, action, resource, metadata, ip) {
  await pool.query(
    'INSERT INTO rbac.audit_log (user_id, action, resource, metadata, ip) VALUES ($1, $2, $3, $4, $5)',
    [userId, action, resource, metadata ? JSON.stringify(metadata) : '{}', ip]
  );
}

async function getAuditLog(limit = 100, offset = 0) {
  const result = await pool.query(
    'SELECT * FROM rbac.audit_log ORDER BY created_at DESC LIMIT $1 OFFSET $2',
    [limit, offset]
  );
  return result.rows;
}

async function findRoleIdByName(roleName) {
  const result = await pool.query(
    'SELECT id FROM rbac.roles WHERE name = $1 LIMIT 1',
    [roleName]
  );
  return result.rows[0]?.id || null;
}

async function ensureRole(userId, roleName, grantedBy = null) {
  const roleId = await findRoleIdByName(roleName);
  if (!roleId) throw new Error(`Role not found: ${roleName}`);

  const result = await pool.query(
    `INSERT INTO rbac.user_roles (user_id, role_id, granted_by)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, role_id) DO NOTHING
     RETURNING user_id`,
    [userId, roleId, grantedBy]
  );

  if (result.rows.length > 0) {
    log('info', 'RBAC: role ensured', { userId, role: roleName, grantedBy, action: 'role.ensured' });
    await writeAuditLog(grantedBy, 'role.ensured', `user:${userId}`, { role: roleName }, null);
  }
}

module.exports = {
  getEffectivePermissions,
  hasPermission,
  getUserRoleName,
  assignRole,
  ensureRole,
  ensureUserRole,
  listUsers,
  writeAuditLog,
  getAuditLog,
};
