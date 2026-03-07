/**
 * Centralized audit logging module.
 *
 * Responsibilities:
 *   - Write immutable audit entries to rbac.audit_log (partitioned table)
 *   - Query audit entries with server-side filtering + pagination
 *   - Stream/export audit data for compliance downloads
 *   - Provide Express middleware for auto-capturing request context
 *
 * All writes are best-effort: failures are logged but never crash the caller.
 */

const { pool } = require('./db');
const { ACTIONS, validateAction } = require('./audit-actions');

// ── Structured logger (matches existing pattern in rbac.js) ─────────────
function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'auth-service',
    component: 'audit',
    message,
    ...meta,
  };
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

// ── Write ───────────────────────────────────────────────────────────────

/**
 * Write an audit log entry.
 *
 * @param {Object} opts
 * @param {string|null}  opts.userId      - Actor's user ID (null for system/anonymous)
 * @param {string}       opts.action      - Action constant from ACTIONS
 * @param {string|null}  opts.resource    - What was acted on (e.g., 'user:<uuid>')
 * @param {Object}       opts.metadata    - Arbitrary structured data
 * @param {string|null}  opts.ip          - Client IP
 * @param {string|null}  opts.userAgent   - User-Agent header
 * @param {string|null}  opts.requestPath - HTTP request path
 * @param {string|null}  opts.httpMethod  - HTTP method
 * @param {string|null}  opts.sessionId   - Session ID for correlation
 */
async function writeAuditLog({
  userId = null,
  action,
  resource = null,
  metadata = {},
  ip = null,
  userAgent = null,
  requestPath = null,
  httpMethod = null,
  sessionId = null,
} = {}) {
  validateAction(action);

  await pool.query(
    `INSERT INTO rbac.audit_log
       (user_id, action, resource, metadata, ip, user_agent, request_path, http_method, session_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [
      userId,
      action,
      resource,
      metadata ? JSON.stringify(metadata) : '{}',
      ip,
      userAgent ? userAgent.substring(0, 512) : null,   // cap UA length
      requestPath ? requestPath.substring(0, 256) : null,
      httpMethod || null,
      sessionId || null,
    ]
  );
}

/**
 * Best-effort audit write: swallows errors, logs them.
 * Use this in request handlers where audit failure should not break the response.
 */
function writeAuditLogSafe(opts) {
  return writeAuditLog(opts).catch((err) => {
    log('error', 'Audit log write failed', { error: err.message, action: opts.action });
  });
}

// ── Read (with server-side filtering) ───────────────────────────────────

/**
 * Query audit log with server-side filters.
 *
 * @param {Object} opts
 * @param {number}       opts.limit      - Max rows (1-1000, default 100)
 * @param {number}       opts.offset     - Pagination offset (default 0)
 * @param {string|null}  opts.action     - Filter by action (exact or prefix with %)
 * @param {string|null}  opts.userId     - Filter by user_id (exact)
 * @param {string|null}  opts.resource   - Filter by resource (exact or prefix with %)
 * @param {string|null}  opts.ip         - Filter by IP (exact)
 * @param {string|null}  opts.from       - Filter created_at >= (ISO 8601)
 * @param {string|null}  opts.to         - Filter created_at <= (ISO 8601)
 * @returns {Promise<{logs: Array, total: number, limit: number, offset: number}>}
 */
async function getAuditLog({
  limit = 100,
  offset = 0,
  action = null,
  userId = null,
  resource = null,
  ip = null,
  from = null,
  to = null,
} = {}) {
  const safeLimit = Math.max(1, Math.min(parseInt(limit, 10) || 100, 1000));
  const safeOffset = Math.max(0, parseInt(offset, 10) || 0);

  const conditions = [];
  const params = [];
  let paramIdx = 1;

  if (action) {
    if (action.includes('%')) {
      conditions.push(`action LIKE $${paramIdx++}`);
    } else {
      conditions.push(`action = $${paramIdx++}`);
    }
    params.push(action);
  }

  if (userId) {
    conditions.push(`user_id = $${paramIdx++}::UUID`);
    params.push(userId);
  }

  if (resource) {
    if (resource.includes('%')) {
      conditions.push(`resource LIKE $${paramIdx++}`);
    } else {
      conditions.push(`resource = $${paramIdx++}`);
    }
    params.push(resource);
  }

  if (ip) {
    conditions.push(`ip = $${paramIdx++}`);
    params.push(ip);
  }

  if (from) {
    conditions.push(`created_at >= $${paramIdx++}::TIMESTAMPTZ`);
    params.push(from);
  }

  if (to) {
    conditions.push(`created_at <= $${paramIdx++}::TIMESTAMPTZ`);
    params.push(to);
  }

  const whereClause = conditions.length > 0
    ? 'WHERE ' + conditions.join(' AND ')
    : '';

  // Count query (uses partition pruning when date filters are present)
  const countResult = await pool.query(
    `SELECT count(*) AS total FROM rbac.audit_log ${whereClause}`,
    params
  );
  const total = parseInt(countResult.rows[0].total, 10);

  // Data query
  const dataParams = [...params, safeLimit, safeOffset];
  const dataResult = await pool.query(
    `SELECT * FROM rbac.audit_log ${whereClause}
     ORDER BY created_at DESC
     LIMIT $${paramIdx++} OFFSET $${paramIdx++}`,
    dataParams
  );

  return {
    logs: dataResult.rows,
    total,
    limit: safeLimit,
    offset: safeOffset,
  };
}

// ── Export (streaming for large datasets) ────────────────────────────────

/**
 * Stream audit log rows as NDJSON or CSV for export.
 *
 * @param {import('express').Response} res - Express response to stream into
 * @param {Object}  filters  - Same filter params as getAuditLog
 * @param {string}  format   - 'json' or 'csv'
 */
async function streamAuditExport(res, filters = {}, format = 'json') {
  const { action, userId, resource, ip, from, to } = filters;

  const conditions = [];
  const params = [];
  let paramIdx = 1;

  if (action) {
    conditions.push(action.includes('%') ? `action LIKE $${paramIdx++}` : `action = $${paramIdx++}`);
    params.push(action);
  }
  if (userId) {
    conditions.push(`user_id = $${paramIdx++}::UUID`);
    params.push(userId);
  }
  if (resource) {
    conditions.push(resource.includes('%') ? `resource LIKE $${paramIdx++}` : `resource = $${paramIdx++}`);
    params.push(resource);
  }
  if (ip) {
    conditions.push(`ip = $${paramIdx++}`);
    params.push(ip);
  }
  if (from) {
    conditions.push(`created_at >= $${paramIdx++}::TIMESTAMPTZ`);
    params.push(from);
  }
  if (to) {
    conditions.push(`created_at <= $${paramIdx++}::TIMESTAMPTZ`);
    params.push(to);
  }

  const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';

  const client = await pool.connect();
  try {
    // Use a server-side cursor for memory-efficient streaming
    const cursorName = 'audit_export_cursor';
    await client.query('BEGIN');
    await client.query(
      `DECLARE ${cursorName} CURSOR FOR
       SELECT id, user_id, action, resource, metadata, ip, user_agent, request_path, http_method, session_id, created_at
       FROM rbac.audit_log ${whereClause}
       ORDER BY created_at DESC`,
      params
    );

    if (format === 'csv') {
      res.write('id,user_id,action,resource,metadata,ip,user_agent,request_path,http_method,session_id,created_at\n');
    }

    const batchSize = 500;
    let hasMore = true;

    while (hasMore) {
      const batch = await client.query(`FETCH ${batchSize} FROM ${cursorName}`);
      if (batch.rows.length === 0) {
        hasMore = false;
        break;
      }

      for (const row of batch.rows) {
        if (format === 'csv') {
          res.write(auditRowToCsv(row) + '\n');
        } else {
          res.write(JSON.stringify(row) + '\n');
        }
      }

      if (batch.rows.length < batchSize) {
        hasMore = false;
      }
    }

    await client.query(`CLOSE ${cursorName}`);
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Convert an audit row to a CSV line. Handles quoting for fields that may
 * contain commas, quotes, or newlines.
 */
function auditRowToCsv(row) {
  const fields = [
    row.id,
    row.user_id || '',
    row.action,
    row.resource || '',
    JSON.stringify(row.metadata || {}),
    row.ip || '',
    row.user_agent || '',
    row.request_path || '',
    row.http_method || '',
    row.session_id || '',
    row.created_at ? new Date(row.created_at).toISOString() : '',
  ];
  return fields.map(csvEscape).join(',');
}

function csvEscape(val) {
  const str = String(val);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return '"' + str.replace(/"/g, '""') + '"';
  }
  return str;
}

// ── Middleware factory ───────────────────────────────────────────────────

/**
 * Express middleware that extracts request context and attaches it
 * to `req.auditContext` for use by downstream audit writes.
 *
 * Usage: app.use(auditContext());
 */
function auditContext() {
  return (req, _res, next) => {
    req.auditContext = {
      ip: req.ip,
      userAgent: req.get('user-agent') || null,
      requestPath: req.originalUrl ? req.originalUrl.split('?')[0] : req.path,
      httpMethod: req.method,
    };
    next();
  };
}

/**
 * Convenience: build a full audit opts object from req + overrides.
 */
function auditOptsFromReq(req, overrides = {}) {
  return {
    userId: req.user?.id || null,
    ip: req.auditContext?.ip || req.ip,
    userAgent: req.auditContext?.userAgent || req.get('user-agent') || null,
    requestPath: req.auditContext?.requestPath || req.path,
    httpMethod: req.auditContext?.httpMethod || req.method,
    sessionId: req.user?.sessionId || null,
    ...overrides,
  };
}

module.exports = {
  writeAuditLog,
  writeAuditLogSafe,
  getAuditLog,
  streamAuditExport,
  auditContext,
  auditOptsFromReq,
  ACTIONS,
};
