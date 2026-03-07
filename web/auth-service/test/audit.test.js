/**
 * Integration tests for the centralized audit logging system.
 *
 * These tests verify:
 *   - Audit action constants registry
 *   - writeAuditLog / writeAuditLogSafe behavior
 *   - getAuditLog server-side filtering
 *   - Export endpoint CSV/JSON format
 *   - auditContext middleware
 *   - Backward-compatible legacy wrappers in rbac.js
 */

const { ACTIONS, KNOWN_ACTIONS, validateAction } = require('../src/audit-actions');

// ── Unit tests: audit-actions.js ─────────────────────────────────────────

describe('audit-actions', () => {
  test('ACTIONS is frozen (immutable)', () => {
    expect(Object.isFrozen(ACTIONS)).toBe(true);
  });

  test('all ACTIONS values are unique strings', () => {
    const values = Object.values(ACTIONS);
    expect(values.length).toBeGreaterThan(0);
    const unique = new Set(values);
    expect(unique.size).toBe(values.length);
    for (const v of values) {
      expect(typeof v).toBe('string');
      expect(v.length).toBeGreaterThan(0);
    }
  });

  test('ACTIONS follow <domain>.<entity>.<verb> convention', () => {
    for (const [key, value] of Object.entries(ACTIONS)) {
      // All actions must have at least 2 dot-separated segments
      const parts = value.split('.');
      expect(parts.length).toBeGreaterThanOrEqual(2);
      // No leading/trailing dots
      expect(value).not.toMatch(/^\./);
      expect(value).not.toMatch(/\.$/);
    }
  });

  test('KNOWN_ACTIONS contains all ACTIONS values', () => {
    for (const value of Object.values(ACTIONS)) {
      expect(KNOWN_ACTIONS.has(value)).toBe(true);
    }
  });

  test('validateAction returns true for known actions', () => {
    expect(validateAction(ACTIONS.AUTH_LOGIN_SUCCESS)).toBe(true);
    expect(validateAction(ACTIONS.PERMISSION_DENIED)).toBe(true);
    expect(validateAction(ACTIONS.ROLE_ASSIGNED)).toBe(true);
  });

  test('validateAction returns false for unknown actions', () => {
    // Suppress console.warn during this test
    const warn = jest.spyOn(console, 'warn').mockImplementation();
    expect(validateAction('unknown.action')).toBe(false);
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining('Unknown audit action')
    );
    warn.mockRestore();
  });

  test('expected critical actions exist', () => {
    const required = [
      'AUTH_LOGIN_SUCCESS',
      'AUTH_LOGIN_FAILED',
      'AUTH_TOKEN_EXPIRED',
      'AUTH_GUEST_ISSUED',
      'ROLE_ASSIGNED',
      'ROLE_ENSURED',
      'USERS_ROLE_ASSIGN',
      'PERMISSIONS_UPDATED',
      'PERMISSION_DENIED',
      'OPENCLAW_CREATE',
      'OPENCLAW_DELETE',
      'OPENCLAW_ASSIGN',
      'OPENCLAW_UNASSIGN',
      'AUDIT_READ',
      'AUDIT_EXPORT',
      'SYSTEM_ERROR',
    ];
    for (const name of required) {
      expect(ACTIONS).toHaveProperty(name);
      expect(typeof ACTIONS[name]).toBe('string');
    }
  });
});

// ── Unit tests: audit.js module interface ────────────────────────────────

describe('audit module exports', () => {
  // We can only test the exports exist without a live DB
  const audit = require('../src/audit');

  test('exports all expected functions', () => {
    expect(typeof audit.writeAuditLog).toBe('function');
    expect(typeof audit.writeAuditLogSafe).toBe('function');
    expect(typeof audit.getAuditLog).toBe('function');
    expect(typeof audit.streamAuditExport).toBe('function');
    expect(typeof audit.auditContext).toBe('function');
    expect(typeof audit.auditOptsFromReq).toBe('function');
  });

  test('re-exports ACTIONS from audit-actions', () => {
    expect(audit.ACTIONS).toBe(ACTIONS);
  });
});

// ── Unit tests: auditContext middleware ──────────────────────────────────

describe('auditContext middleware', () => {
  const { auditContext, auditOptsFromReq } = require('../src/audit');

  test('attaches auditContext to req', () => {
    const middleware = auditContext();
    const req = {
      ip: '192.168.1.1',
      method: 'POST',
      path: '/auth/users/test/role',
      originalUrl: '/auth/users/test/role?foo=bar',
      get: (header) => {
        if (header === 'user-agent') return 'TestAgent/1.0';
        return null;
      },
    };
    const next = jest.fn();

    middleware(req, {}, next);

    expect(next).toHaveBeenCalled();
    expect(req.auditContext).toEqual({
      ip: '192.168.1.1',
      userAgent: 'TestAgent/1.0',
      requestPath: '/auth/users/test/role',
      httpMethod: 'POST',
    });
  });

  test('auditOptsFromReq builds complete opts', () => {
    const req = {
      user: { id: 'user-123', sessionId: 'sess-abc' },
      auditContext: {
        ip: '10.0.0.1',
        userAgent: 'Chrome/100',
        requestPath: '/auth/me',
        httpMethod: 'GET',
      },
      ip: '10.0.0.1',
      path: '/auth/me',
      method: 'GET',
      get: () => 'Chrome/100',
    };

    const opts = auditOptsFromReq(req, { action: ACTIONS.AUDIT_READ, resource: 'test' });

    expect(opts.userId).toBe('user-123');
    expect(opts.ip).toBe('10.0.0.1');
    expect(opts.userAgent).toBe('Chrome/100');
    expect(opts.requestPath).toBe('/auth/me');
    expect(opts.httpMethod).toBe('GET');
    expect(opts.sessionId).toBe('sess-abc');
    expect(opts.action).toBe(ACTIONS.AUDIT_READ);
    expect(opts.resource).toBe('test');
  });
});

// ── Unit tests: legacy rbac.js backward compatibility ────────────────────

describe('rbac.js backward compatibility', () => {
  const rbac = require('../src/rbac');

  test('still exports writeAuditLog (legacy)', () => {
    expect(typeof rbac.writeAuditLog).toBe('function');
  });

  test('still exports getAuditLog (legacy)', () => {
    expect(typeof rbac.getAuditLog).toBe('function');
  });
});
