/**
 * Audit action constants -- single source of truth for all audit event types.
 *
 * Convention:
 *   <domain>.<entity>.<verb>
 *
 * Adding a new action:
 *   1. Add the constant here
 *   2. Use it in the call site via `const { ACTIONS } = require('./audit-actions')`
 *   3. (Optional) update the Grafana dashboard queries if you want the new event visualized
 */

const ACTIONS = Object.freeze({
  // ── Authentication ──────────────────────────────────────────────────
  AUTH_LOGIN_SUCCESS:     'auth.login.success',
  AUTH_LOGIN_FAILED:      'auth.login.failed',
  AUTH_TOKEN_EXPIRED:     'auth.token.expired',
  AUTH_GUEST_ISSUED:      'auth.guest.issued',
  AUTH_SESSION_CREATE:    'auth.session.create',

  // ── RBAC mutations ─────────────────────────────────────────────────
  ROLE_ASSIGNED:          'role.assigned',
  ROLE_ENSURED:           'role.ensured',
  USERS_ROLE_ASSIGN:      'users.role.assign',
  PERMISSIONS_UPDATED:    'permissions.updated',
  PERMISSION_DENIED:      'permission.denied',

  // ── OpenClaw management ────────────────────────────────────────────
  OPENCLAW_CREATE:        'openclaw.create',
  OPENCLAW_DELETE:        'openclaw.delete',
  OPENCLAW_ASSIGN:        'openclaw.assign',
  OPENCLAW_UNASSIGN:      'openclaw.unassign',

  // ── Settings / environment ─────────────────────────────────────────
  SETTINGS_UPDATED:       'settings.updated',
  ENV_SET:                'env.set',
  ENV_DELETE:             'env.delete',

  // ── Audit access (self-referential) ────────────────────────────────
  AUDIT_READ:             'audit.read',
  AUDIT_EXPORT:           'audit.export',

  // ── System ─────────────────────────────────────────────────────────
  SYSTEM_ERROR:           'system.error',
  SYSTEM_STARTUP:         'system.startup',
});

/**
 * All known action strings as a Set for runtime validation.
 */
const KNOWN_ACTIONS = new Set(Object.values(ACTIONS));

/**
 * Validates that an action string is a known audit action.
 * Logs a warning (but does not throw) for unknown actions to avoid
 * breaking callers during a gradual rollout of new events.
 */
function validateAction(action) {
  if (!KNOWN_ACTIONS.has(action)) {
    console.warn(`[audit] Unknown audit action: "${action}" -- consider adding it to audit-actions.js`);
    return false;
  }
  return true;
}

module.exports = { ACTIONS, KNOWN_ACTIONS, validateAction };
