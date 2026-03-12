const express = require('express');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const crypto = require('crypto');
const { pool } = require('../db');
const { writeAuditLogSafe, auditOptsFromReq, ACTIONS } = require('../audit');

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET;
const ORCHESTRATOR_URL = process.env.ORCHESTRATOR_URL;
const ORCHESTRATOR_SERVICE_TOKEN = process.env.ORCHESTRATOR_SERVICE_TOKEN;
const LIGHTRAG_URL = process.env.LIGHTRAG_URL || 'http://lightrag:18803';
const LIGHTRAG_INTERNAL_TOKEN = process.env.LIGHTRAG_INTERNAL_TOKEN || '';
const DELEGATION_JWT_SECRET = process.env.DELEGATION_JWT_SECRET || process.env.OPENCLAW_DELEGATION_SECRET || '';
const GUEST_JWT_TTL = 3600; // 1 hour
const DRAWIO_XML_MAX_BYTES = 10 * 1024 * 1024;

const DELEGATION_ISSUER = 'trinity-auth-service';
const DELEGATION_AUDIENCE = 'trinity-openclaw';
const DELEGATION_TTL_SECONDS = Math.max(60, Number(process.env.DELEGATION_JWT_TTL_SECONDS || 600));

const SCOPE_LIGHTRAG_READ = 'lightrag.read';
const SCOPE_LIGHTRAG_WRITE = 'lightrag.write';
const DEFAULT_DELEGATION_SCOPES = [SCOPE_LIGHTRAG_READ, SCOPE_LIGHTRAG_WRITE];

function headerValue(req, name) {
  const raw = req.headers[name];
  if (Array.isArray(raw)) return raw[0] || '';
  return typeof raw === 'string' ? raw.trim() : '';
}

function extractDelegationToken(req) {
  return headerValue(req, 'x-trinity-delegation');
}

function extractOpenClawGatewayToken(req) {
  return headerValue(req, 'x-openclaw-gateway-token');
}

function hasDelegationToken(req) {
  return extractDelegationToken(req).length > 0;
}

function hasOpenClawGatewayToken(req) {
  return extractOpenClawGatewayToken(req).length > 0;
}

function parseDelegationScopes(value) {
  if (Array.isArray(value)) {
    return value.map((v) => String(v || '').trim()).filter(Boolean);
  }
  if (typeof value === 'string' && value.trim()) {
    return value
      .split(',')
      .map((v) => v.trim())
      .filter(Boolean);
  }
  return [];
}

function verifyDelegationToken(req, expectedOpenclawId) {
  const token = extractDelegationToken(req);
  if (!token) {
    const err = new Error('authentication required');
    err.status = 401;
    throw err;
  }
  if (!DELEGATION_JWT_SECRET) {
    const err = new Error('delegation auth is not configured');
    err.status = 503;
    throw err;
  }

  let claims;
  try {
    claims = jwt.verify(token, DELEGATION_JWT_SECRET, {
      algorithms: ['HS256'],
      issuer: DELEGATION_ISSUER,
      audience: DELEGATION_AUDIENCE,
    });
  } catch (_) {
    const err = new Error('invalid delegation token');
    err.status = 401;
    throw err;
  }

  const userId = String(claims?.sub || '').trim();
  const openclawId = String(claims?.openclaw_id || '').trim();
  const sessionKey = String(claims?.session_key || '').trim();
  const scopes = parseDelegationScopes(claims?.scope);

  if (!userId || !openclawId) {
    const err = new Error('invalid delegation token claims');
    err.status = 401;
    throw err;
  }

  if (expectedOpenclawId && openclawId !== expectedOpenclawId) {
    const err = new Error('delegation token openclaw mismatch');
    err.status = 403;
    throw err;
  }

  return {
    userId,
    openclawId,
    sessionKey,
    scopes,
    jti: String(claims?.jti || ''),
    delegated: true,
  };
}

function ensureDelegatedScope(actor, requiredScope) {
  if (!actor?.delegated) return;
  if ((actor.scopes || []).includes(requiredScope)) return;
  const err = new Error('delegation scope denied');
  err.status = 403;
  throw err;
}

function timingSafeEqualString(a, b) {
  const aa = Buffer.from(String(a || ''));
  const bb = Buffer.from(String(b || ''));
  if (aa.length !== bb.length) {
    crypto.timingSafeEqual(aa, aa);
    return false;
  }
  return crypto.timingSafeEqual(aa, bb);
}

function normalizeWorkspacePart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'default';
}

function looksLikeUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || '').trim());
}

function buildOpenClawWorkspace(tenantId, openclawId, suffix = '') {
  const workspace = `tenant_${normalizeWorkspacePart(tenantId)}__claw_${normalizeWorkspacePart(openclawId)}`;
  if (!suffix) return workspace;
  return `${workspace}__${normalizeWorkspacePart(suffix)}`;
}

function deriveTenantIdFromOpenClaw(openclaw, fallbackUserId) {
  return openclaw?.created_by || openclaw?.createdBy || fallbackUserId || openclaw?.id;
}

async function assertDelegatedOpenClawAccess(delegation, openclawId) {
  if (!delegation?.userId) {
    const err = new Error('authentication required');
    err.status = 401;
    throw err;
  }
  if (delegation.openclawId !== openclawId) {
    const err = new Error('delegation token openclaw mismatch');
    err.status = 403;
    throw err;
  }
  const claws = await fetchAssignedOpenClawsForUser(delegation.userId);
  if (!claws.some((c) => c.id === openclawId)) {
    const err = new Error('not assigned to this openclaw');
    err.status = 403;
    throw err;
  }
}

async function fetchResolvedOpenClawBackend(openclawId) {
  const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${openclawId}/resolve`, {
    headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
  });

  if (!orchRes.ok) {
    const err = new Error(`Failed to resolve openclaw ${openclawId}: ${orchRes.status}`);
    err.status = orchRes.status;
    throw err;
  }

  return orchRes.json();
}

async function resolveOpenClawServiceActor(req, openclawId) {
  const presentedToken = extractOpenClawGatewayToken(req);
  if (!presentedToken) {
    const err = new Error('authentication required');
    err.status = 401;
    throw err;
  }

  const backend = await fetchResolvedOpenClawBackend(openclawId);
  const expectedToken = String(backend?.token || '');
  if (!expectedToken || !timingSafeEqualString(presentedToken, expectedToken)) {
    const err = new Error('invalid openclaw gateway token');
    err.status = 401;
    throw err;
  }

  return {
    userId: `service:${openclawId}`,
    openclawId,
    delegated: false,
    serviceActor: true,
    scopes: DEFAULT_DELEGATION_SCOPES,
    sessionKey: null,
    jti: null,
  };
}

async function resolveOpenClawActor(req, openclawId) {
  if (req.user?.id && !req.user?.isGuest) {
    await assertOpenClawAccess(req, openclawId);
    return {
      userId: req.user.id,
      delegated: false,
      scopes: DEFAULT_DELEGATION_SCOPES,
      sessionKey: null,
      jti: null,
    };
  }

  if (hasDelegationToken(req)) {
    const delegation = verifyDelegationToken(req, openclawId);
    await assertDelegatedOpenClawAccess(delegation, openclawId);
    return delegation;
  }

  if (hasOpenClawGatewayToken(req)) {
    return resolveOpenClawServiceActor(req, openclawId);
  }

  const err = new Error('authentication required');
  err.status = 401;
  throw err;
}

async function deriveLightRagScope(req, openclawId) {
  const canonicalOpenclawId = await resolveOpenClawId(openclawId);
  const actor = await resolveOpenClawActor(req, canonicalOpenclawId);
  const openclaw = await fetchOpenClawById(canonicalOpenclawId);
  const tenantId = deriveTenantIdFromOpenClaw(openclaw, actor.userId);
  const workspaceId = buildOpenClawWorkspace(tenantId, canonicalOpenclawId);
  return {
    tenantId,
    openclawId: canonicalOpenclawId,
    workspaceId,
    userId: actor.userId,
    actor,
  };
}

function lightRagHeaders(scope) {
  return {
    Authorization: `Bearer ${LIGHTRAG_INTERNAL_TOKEN}`,
    'X-Trinity-Tenant': String(scope.tenantId),
    'X-Trinity-Workspace': String(scope.workspaceId),
    'X-Trinity-Openclaw': String(scope.openclawId),
    'X-Trinity-User': String(scope.userId),
  };
}

async function readUpstreamJsonOrText(response) {
  const raw = await response.text();
  try {
    return { raw, json: JSON.parse(raw) };
  } catch (_) {
    return { raw, json: null };
  }
}

async function fetchAssignedOpenClawsForUser(userId) {
  const orchRes = await fetch(`${ORCHESTRATOR_URL}/users/${userId}/openclaws`, {
    headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
  });

  if (!orchRes.ok) {
    const err = new Error(`Failed to list user openclaws: ${orchRes.status}`);
    err.status = orchRes.status;
    throw err;
  }

  return orchRes.json();
}

async function assertOpenClawAccess(req, openclawId) {
  if (!req.user?.id || req.user?.isGuest) {
    const err = new Error('authentication required');
    err.status = 401;
    throw err;
  }

  const isAdmin = ['admin', 'superadmin'].includes(req.user.role);
  if (isAdmin) return;

  const claws = await fetchAssignedOpenClawsForUser(req.user.id);
  if (!claws.some(c => c.id === openclawId)) {
    const err = new Error('not assigned to this openclaw');
    err.status = 403;
    throw err;
  }
}

async function fetchOpenClawById(openclawId) {
  const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${openclawId}`, {
    headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
  });

  if (!orchRes.ok) {
    const err = new Error(`Failed to fetch openclaw ${openclawId}: ${orchRes.status}`);
    err.status = orchRes.status;
    throw err;
  }

  return orchRes.json();
}

async function listAllOpenClaws() {
  const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws`, {
    headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
  });

  if (!orchRes.ok) {
    const err = new Error(`Failed to list openclaws: ${orchRes.status}`);
    err.status = orchRes.status;
    throw err;
  }

  return orchRes.json();
}

async function resolveOpenClawId(inputId) {
  const raw = String(inputId || '').trim();
  if (!raw) {
    const err = new Error('openclaw id is required');
    err.status = 400;
    throw err;
  }
  if (looksLikeUuid(raw)) return raw;

  const list = await listAllOpenClaws();
  const hit = (list || []).find((oc) => {
    const candidates = [
      oc?.id,
      oc?.name,
      oc?.service_name,
      oc?.serviceName,
      oc?.pod_name,
      oc?.podName,
    ]
      .map((v) => String(v || '').trim())
      .filter(Boolean);
    return candidates.includes(raw);
  });

  if (!hit?.id) {
    const err = new Error(`unknown openclaw id: ${raw}`);
    err.status = 404;
    throw err;
  }
  return String(hit.id);
}

async function listDrawIOSnapshots(openclawId, userId) {
  const { rows } = await pool.query(
    `select id, name, xml, xml_hash, created_at, updated_at
       from rbac.drawio_snapshots
      where openclaw_id = $1 and user_id = $2
      order by updated_at desc, created_at desc`,
    [openclawId, userId],
  );
  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    xml: r.xml,
    xmlHash: r.xml_hash,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  }));
}

// GET /auth/me - current user info + permissions
router.get('/me', (req, res) => {
  res.json({
    id: req.user.id,
    email: req.user.email || null,
    role: req.user.role,
    permissions: req.user.permissions,
    isGuest: req.user.isGuest,
  });
});

// GET /auth/permissions - flat permission list
router.get('/permissions', (req, res) => {
  res.json({ permissions: req.user.permissions });
});

// ── OpenClaw Management (admin-managed shared instances) ─────────────────

// GET /auth/openclaws - list OpenClaws assigned to the current user
router.get('/openclaws', async (req, res) => {
  try {
    if (!req.user?.id || req.user?.isGuest) {
      return res.status(401).json({ error: 'authentication required' });
    }
    const userId = req.user.id;
    const openclaws = await fetchAssignedOpenClawsForUser(userId);

    // For each openclaw, get live status
    const enriched = await Promise.all(
      openclaws.map(async (oc) => {
        try {
          const statusRes = await fetch(
            `${ORCHESTRATOR_URL}/openclaws/${oc.id}/status`,
            { headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` } }
          );
          if (statusRes.ok) {
            const statusData = await statusRes.json();
            return { ...oc, ready: statusData.ready || false, podStatus: statusData.podStatus };
          }
        } catch (_) {}
        return { ...oc, ready: false, podStatus: 'unknown' };
      })
    );

    res.json(enriched);
  } catch (err) {
    console.error('[auth] List openclaws error:', err);
    res.status(500).json({ error: 'Failed to list OpenClaws' });
  }
});

// GET /auth/openclaws/:id/status - get status of a specific OpenClaw
router.get('/openclaws/:id/status', async (req, res) => {
  try {
    if (!req.user?.id || req.user?.isGuest) {
      return res.status(401).json({ error: 'authentication required' });
    }
    const userId = req.user.id;
    const openclawId = req.params.id;

    // Verify user is assigned (or is admin)
    const isAdmin = ['admin', 'superadmin'].includes(req.user.role);
    if (!isAdmin) {
      let claws;
      try {
        claws = await fetchAssignedOpenClawsForUser(userId);
      } catch (err) {
        console.error('[auth] OpenClaw assignment lookup failed:', err);
        return res.status(502).json({ error: 'Failed to verify OpenClaw assignment' });
      }
      if (!claws.some(c => c.id === openclawId)) {
        return res.status(403).json({ error: 'Not assigned to this OpenClaw' });
      }
    }

    const statusRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${openclawId}/status`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (statusRes.status === 404) {
      return res.status(404).json({ error: 'OpenClaw not found' });
    }
    if (!statusRes.ok) {
      return res.status(502).json({ error: 'Failed to get OpenClaw status' });
    }

    const data = await statusRes.json();
    res.json({
      id: data.id,
      name: data.name,
      status: data.status,
      ready: data.ready || false,
      podStatus: data.podStatus,
    });
  } catch (err) {
    console.error('[auth] OpenClaw status error:', err);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

// POST /auth/openclaws/:id/delegation-token - mint short-lived scoped token for svc-to-svc delegation
router.post('/openclaws/:id/delegation-token', async (req, res) => {
  try {
    if (!req.user?.id || req.user?.isGuest) {
      return res.status(401).json({ error: 'authentication required' });
    }
    if (!DELEGATION_JWT_SECRET) {
      return res.status(503).json({ error: 'delegation auth is not configured' });
    }

    const openclawId = await resolveOpenClawId(req.params.id);
    await assertOpenClawAccess(req, openclawId);

    const body = (req.body && typeof req.body === 'object') ? req.body : {};
    const requestedScopes = parseDelegationScopes(body.scope);
    const allowedScopes = new Set(DEFAULT_DELEGATION_SCOPES);
    const scopes = (requestedScopes.length ? requestedScopes : DEFAULT_DELEGATION_SCOPES)
      .filter((s) => allowedScopes.has(s));
    if (scopes.length === 0) {
      return res.status(400).json({ error: 'scope must include at least one allowed value' });
    }

    const sessionKey = (body.session_key || '').toString().trim();
    const now = Math.floor(Date.now() / 1000);
    const payload = {
      sub: req.user.id,
      openclaw_id: openclawId,
      session_key: sessionKey || undefined,
      scope: scopes,
      jti: uuidv4(),
      iat: now,
      nbf: now,
      exp: now + DELEGATION_TTL_SECONDS,
      iss: DELEGATION_ISSUER,
      aud: DELEGATION_AUDIENCE,
    };

    const token = jwt.sign(payload, DELEGATION_JWT_SECRET, { algorithm: 'HS256' });
    return res.json({
      token,
      token_type: 'Bearer',
      expires_in: DELEGATION_TTL_SECONDS,
      openclaw_id: openclawId,
      scope: scopes,
      session_key: sessionKey || null,
    });
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to mint delegation token' });
  }
});

// GET /auth/openclaws/:id/lightrag-scope - derive the canonical LightRAG scope for this OpenClaw
router.get('/openclaws/:id/lightrag-scope', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    res.json({
      tenantId: scope.tenantId,
      openclawId: scope.openclawId,
      workspaceId: scope.workspaceId,
      userId: scope.userId,
    });
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to derive LightRAG scope' });
  }
});

router.get('/openclaws/:id/lightrag-graph', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstreamHeaders = {
      Authorization: `Bearer ${LIGHTRAG_INTERNAL_TOKEN}`,
      'X-Trinity-Tenant': String(scope.tenantId),
      'X-Trinity-Workspace': String(scope.workspaceId),
      'X-Trinity-Openclaw': String(scope.openclawId),
      'X-Trinity-User': String(scope.userId),
    };

    const labelsRes = await fetch(`${LIGHTRAG_URL}/graph/label/popular?limit=25`, {
      headers: upstreamHeaders,
    });

    const labelsRaw = await labelsRes.text();
    if (!labelsRes.ok) {
      return res.status(labelsRes.status).json({ error: labelsRaw || 'Failed to fetch LightRAG labels' });
    }

    let labels = [];
    try {
      labels = JSON.parse(labelsRaw);
    } catch (_) {
      labels = [];
    }

    if (!Array.isArray(labels) || labels.length === 0) {
      console.warn('[auth] LightRAG returned no labels for scope', {
        tenantId: scope.tenantId,
        openclawId: scope.openclawId,
        workspaceId: scope.workspaceId,
      });
    }

    const selectedLabel = (req.query.label || labels[0] || '').toString();
    if (!selectedLabel) {
      return res.json({
        tenantId: scope.tenantId,
        openclawId: scope.openclawId,
        workspaceId: scope.workspaceId,
        labels,
        selectedLabel: null,
        graphMeta: {
          selectedLabel: null,
          nodeCount: 0,
          edgeCount: 0,
          isEmpty: true,
        },
        graph: { nodes: [], edges: [] },
      });
    }

    const graphUrl = new URL(`${LIGHTRAG_URL}/graphs`);
    graphUrl.searchParams.set('label', selectedLabel);
    graphUrl.searchParams.set('max_depth', String(req.query.max_depth || 3));
    graphUrl.searchParams.set('max_nodes', String(req.query.max_nodes || 500));

    const graphRes = await fetch(graphUrl, {
      headers: upstreamHeaders,
    });

    const raw = await graphRes.text();
    if (!graphRes.ok) {
      return res.status(graphRes.status).json({ error: raw || 'Failed to fetch LightRAG graph' });
    }
    let graph;
    try {
      graph = JSON.parse(raw);
    } catch (_) {
      graph = { nodes: [], edges: [] };
    }

    const nodes = Array.isArray(graph?.nodes) ? graph.nodes : [];
    const edges = Array.isArray(graph?.edges) ? graph.edges : [];
    const graphMeta = {
      selectedLabel,
      nodeCount: nodes.length,
      edgeCount: edges.length,
      isEmpty: nodes.length === 0 && edges.length === 0,
    };

    if (graphMeta.isEmpty) {
      console.warn('[auth] LightRAG returned empty graph', {
        tenantId: scope.tenantId,
        openclawId: scope.openclawId,
        workspaceId: scope.workspaceId,
        selectedLabel,
        maxDepth: Number(req.query.max_depth || 3),
        maxNodes: Number(req.query.max_nodes || 500),
      });
    }

    res.json({
      tenantId: scope.tenantId,
      openclawId: scope.openclawId,
      workspaceId: scope.workspaceId,
      labels,
      selectedLabel,
      graphMeta,
      graph,
    });
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to fetch LightRAG graph' });
  }
});

// GET /auth/openclaws/:id/lightrag-documents - list documents in scoped workspace
router.get('/openclaws/:id/lightrag-documents', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const url = new URL(`${LIGHTRAG_URL}/documents`);
    for (const key of ['status', 'type', 'q', 'limit', 'offset']) {
      const value = req.query[key];
      if (value != null && `${value}`.trim() !== '') {
        url.searchParams.set(key, `${value}`);
      }
    }

    const upstream = await fetch(url, { headers: lightRagHeaders(scope) });
    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to list LightRAG documents' });
    }

    const documents = Array.isArray(json) ? json : [];
    return res.json({
      tenantId: scope.tenantId,
      openclawId: scope.openclawId,
      workspaceId: scope.workspaceId,
      count: documents.length,
      documents,
    });
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to list LightRAG documents' });
  }
});

// POST /auth/openclaws/:id/lightrag-documents - upload/register document
router.post('/openclaws/:id/lightrag-documents', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_WRITE);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const contentType = String(req.headers['content-type'] || '');
    if (!contentType.toLowerCase().includes('multipart/form-data')) {
      return res.status(400).json({ error: 'multipart/form-data is required' });
    }

    const upstreamHeaders = {
      ...lightRagHeaders(scope),
      'Content-Type': contentType,
    };
    if (req.headers['content-length']) {
      upstreamHeaders['Content-Length'] = String(req.headers['content-length']);
    }

    const upstream = await fetch(`${LIGHTRAG_URL}/documents`, {
      method: 'POST',
      headers: upstreamHeaders,
      body: req,
      duplex: 'half',
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to upload LightRAG document' });
    }

    return res.status(201).json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to upload LightRAG document' });
  }
});

// POST /auth/openclaws/:id/lightrag-documents/:documentId/ingest - index a document
router.post('/openclaws/:id/lightrag-documents/:documentId/ingest', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const documentId = req.params.documentId;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_WRITE);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstream = await fetch(`${LIGHTRAG_URL}/documents/${encodeURIComponent(documentId)}/ingest`, {
      method: 'POST',
      headers: lightRagHeaders(scope),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to ingest LightRAG document' });
    }

    return res.json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to ingest LightRAG document' });
  }
});

// GET /auth/openclaws/:id/lightrag-documents/:documentId/status - fetch document status
router.get('/openclaws/:id/lightrag-documents/:documentId/status', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const documentId = req.params.documentId;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstream = await fetch(`${LIGHTRAG_URL}/documents/${encodeURIComponent(documentId)}/status`, {
      headers: lightRagHeaders(scope),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to fetch document status' });
    }

    return res.json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to fetch document status' });
  }
});

// GET /auth/openclaws/:id/lightrag-documents/:documentId/chunks - fetch document chunks
router.get('/openclaws/:id/lightrag-documents/:documentId/chunks', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const documentId = req.params.documentId;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstream = await fetch(`${LIGHTRAG_URL}/documents/${encodeURIComponent(documentId)}/chunks`, {
      headers: lightRagHeaders(scope),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to fetch document chunks' });
    }

    return res.json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to fetch document chunks' });
  }
});

// DELETE /auth/openclaws/:id/lightrag-documents/:documentId - delete document from workspace + index
router.delete('/openclaws/:id/lightrag-documents/:documentId', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const documentId = req.params.documentId;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_WRITE);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstream = await fetch(`${LIGHTRAG_URL}/documents/${encodeURIComponent(documentId)}`, {
      method: 'DELETE',
      headers: lightRagHeaders(scope),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to delete document' });
    }

    return res.json(json || { document_id: documentId, deleted: true });
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to delete document' });
  }
});

// GET /auth/openclaws/:id/lightrag-search - server-side node search for large graphs
router.get('/openclaws/:id/lightrag-search', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const q = (req.query.q || '').toString().trim();
    if (!q) {
      return res.status(400).json({ error: 'q is required' });
    }

    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);
    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstreamHeaders = {
      Authorization: `Bearer ${LIGHTRAG_INTERNAL_TOKEN}`,
      'X-Trinity-Tenant': String(scope.tenantId),
      'X-Trinity-Workspace': String(scope.workspaceId),
      'X-Trinity-Openclaw': String(scope.openclawId),
      'X-Trinity-User': String(scope.userId),
    };

    const selectedLabel = (req.query.label || '').toString();
    const graphUrl = new URL(`${LIGHTRAG_URL}/graphs`);
    if (selectedLabel) graphUrl.searchParams.set('label', selectedLabel);
    graphUrl.searchParams.set('max_depth', String(req.query.max_depth || 3));
    graphUrl.searchParams.set('max_nodes', String(req.query.max_nodes || 1000));

    const graphRes = await fetch(graphUrl, { headers: upstreamHeaders });
    const raw = await graphRes.text();
    if (!graphRes.ok) {
      return res.status(graphRes.status).json({ error: raw || 'Failed to fetch LightRAG graph' });
    }

    let graph;
    try {
      graph = JSON.parse(raw);
    } catch (_) {
      graph = { nodes: [], edges: [] };
    }

    const nodes = Array.isArray(graph?.nodes) ? graph.nodes : [];
    const edges = Array.isArray(graph?.edges) ? graph.edges : [];

    const degree = new Map();
    for (const edge of edges) {
      const src = (edge?.source || '').toString();
      const tgt = (edge?.target || '').toString();
      if (!src || !tgt) continue;
      degree.set(src, (degree.get(src) || 0) + 1);
      degree.set(tgt, (degree.get(tgt) || 0) + 1);
    }

    const qLower = q.toLowerCase();
    const scoreNode = (node) => {
      const id = (node?.id || node?.identity || '').toString();
      const labels = Array.isArray(node?.labels) ? node.labels.map((v) => String(v)) : [];
      const label = (labels[0] || node?.label || id || '').toString();
      const kind = (node?.entity_type || node?.kind || '').toString();
      const desc = (node?.properties?.description || node?.metadata?.preview || '').toString();

      const fields = [label, id, kind, desc];
      let score = 0;
      for (const f of fields) {
        const v = f.toLowerCase();
        if (!v) continue;
        if (v === qLower) score += 100;
        else if (v.startsWith(qLower)) score += 60;
        else if (v.includes(qLower)) score += 25;
      }
      if (score > 0) score += Math.min(15, degree.get(id) || 0);
      return { score, id, label, kind, preview: desc };
    };

    const ranked = nodes
      .map((n) => ({ raw: n, ...scoreNode(n) }))
      .filter((n) => n.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, Number(req.query.limit || 50));

    res.json({
      tenantId: scope.tenantId,
      openclawId: scope.openclawId,
      workspaceId: scope.workspaceId,
      query: q,
      count: ranked.length,
      results: ranked.map((r) => ({
        id: r.id,
        label: r.label,
        kind: r.kind,
        score: r.score,
        degree: degree.get(r.id) || 0,
        preview: r.preview,
      })),
    });
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to search LightRAG graph' });
  }
});

router.get('/openclaws/:id/lightrag-label-search', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const upstreamHeaders = {
      Authorization: `Bearer ${LIGHTRAG_INTERNAL_TOKEN}`,
      'X-Trinity-Tenant': String(scope.tenantId),
      'X-Trinity-Workspace': String(scope.workspaceId),
      'X-Trinity-Openclaw': String(scope.openclawId),
      'X-Trinity-User': String(scope.userId),
    };

    const q = (req.query.q || '').toString().trim();
    const limit = Math.min(Number(req.query.limit || 80), 100);

    const endpoint = q.length >= 2
      ? `${LIGHTRAG_URL}/graph/label/search?q=${encodeURIComponent(q)}&limit=${limit}`
      : `${LIGHTRAG_URL}/graph/label/popular?limit=${Math.min(limit, 300)}`;

    const labelsRes = await fetch(endpoint, { headers: upstreamHeaders });
    const labelsRaw = await labelsRes.text();
    if (!labelsRes.ok) {
      return res.status(labelsRes.status).json({ error: labelsRaw || 'Failed to fetch labels' });
    }

    let labels = [];
    try {
      labels = JSON.parse(labelsRaw);
    } catch (_) {
      labels = [];
    }

    res.json({ labels: Array.isArray(labels) ? labels : [] });
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to search labels' });
  }
});

// POST /auth/openclaws/:id/lightrag-query - run scoped retrieval search (same workspace only)
router.post('/openclaws/:id/lightrag-query', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const body = (req.body && typeof req.body === 'object') ? req.body : {};
    const requestedWorkspaceId = body.workspace_id;
    if (
      requestedWorkspaceId != null &&
      String(requestedWorkspaceId).trim() !== '' &&
      String(requestedWorkspaceId) !== String(scope.workspaceId)
    ) {
      return res.status(403).json({ error: 'workspace mismatch' });
    }

    const query = (body.query || '').toString().trim();
    if (!query) {
      return res.status(400).json({ error: 'query is required' });
    }

    const upstreamPayload = {
      ...body,
      workspace_id: scope.workspaceId,
      query,
    };

    const upstream = await fetch(`${LIGHTRAG_URL}/retrieval/search`, {
      method: 'POST',
      headers: {
        ...lightRagHeaders(scope),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(upstreamPayload),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to run LightRAG retrieval search' });
    }

    return res.json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to run LightRAG retrieval search' });
  }
});

// POST /auth/openclaws/:id/lightrag-compare - run scoped retrieval compare (same workspace only)
router.post('/openclaws/:id/lightrag-compare', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);
    ensureDelegatedScope(scope.actor, SCOPE_LIGHTRAG_READ);

    if (!LIGHTRAG_INTERNAL_TOKEN) {
      return res.status(503).json({ error: 'LIGHTRAG_INTERNAL_TOKEN not configured' });
    }

    const body = (req.body && typeof req.body === 'object') ? req.body : {};
    const query = (body.query || '').toString().trim();
    const leftDocumentId = (body?.left?.document_id || '').toString().trim();
    const rightDocumentId = (body?.right?.document_id || '').toString().trim();

    if (!query) {
      return res.status(400).json({ error: 'query is required' });
    }
    if (!leftDocumentId || !rightDocumentId) {
      return res.status(400).json({ error: 'left.document_id and right.document_id are required' });
    }

    const leftWorkspace = body?.left?.workspace_id;
    const rightWorkspace = body?.right?.workspace_id;
    if (
      (leftWorkspace != null && String(leftWorkspace).trim() !== '' && String(leftWorkspace) !== String(scope.workspaceId)) ||
      (rightWorkspace != null && String(rightWorkspace).trim() !== '' && String(rightWorkspace) !== String(scope.workspaceId))
    ) {
      return res.status(403).json({ error: 'workspace mismatch' });
    }

    const upstreamPayload = {
      ...body,
      query,
      left: {
        ...(body.left && typeof body.left === 'object' ? body.left : {}),
        workspace_id: scope.workspaceId,
        document_id: leftDocumentId,
      },
      right: {
        ...(body.right && typeof body.right === 'object' ? body.right : {}),
        workspace_id: scope.workspaceId,
        document_id: rightDocumentId,
      },
    };

    const upstream = await fetch(`${LIGHTRAG_URL}/retrieval/compare`, {
      method: 'POST',
      headers: {
        ...lightRagHeaders(scope),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(upstreamPayload),
    });

    const { raw, json } = await readUpstreamJsonOrText(upstream);
    if (!upstream.ok) {
      return res.status(upstream.status).json({ error: raw || 'Failed to run LightRAG retrieval compare' });
    }

    return res.json(json || {});
  } catch (err) {
    const statusCode = err.status || 500;
    return res.status(statusCode).json({ error: err.message || 'Failed to run LightRAG retrieval compare' });
  }
});

// ── Admin: OpenClaw CRUD ────────────────────────────────────────────────

// POST /auth/openclaws/create - create a new OpenClaw instance (admin+)
router.post('/openclaws/create', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { name, description } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}`,
      },
      body: JSON.stringify({ name, description, createdBy: req.user.id }),
    });

    if (!orchRes.ok) {
      const errBody = await orchRes.json().catch(() => ({}));
      return res.status(orchRes.status).json({ error: errBody.error || 'Failed to create OpenClaw' });
    }

    const data = await orchRes.json();

    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.OPENCLAW_CREATE,
      resource: 'openclaw',
      metadata: { name, openclawId: data.id },
    });

    res.status(201).json(data);
  } catch (err) {
    console.error('[auth] Create OpenClaw error:', err);
    res.status(500).json({ error: 'Failed to create OpenClaw' });
  }
});

// DELETE /auth/openclaws/:id - delete an OpenClaw instance (admin+)
router.delete('/openclaws/:id', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${req.params.id}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      const errBody = await orchRes.json().catch(() => ({}));
      return res.status(orchRes.status).json({ error: errBody.error || 'Failed to delete OpenClaw' });
    }

    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.OPENCLAW_DELETE,
      resource: 'openclaw',
      metadata: { openclawId: req.params.id },
    });

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] Delete OpenClaw error:', err);
    res.status(500).json({ error: 'Failed to delete OpenClaw' });
  }
});

// GET /auth/openclaws/all - list all OpenClaws (admin+)
router.get('/openclaws/all', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      return res.status(502).json({ error: 'Failed to list OpenClaws' });
    }

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] List all openclaws error:', err);
    res.status(500).json({ error: 'Failed to list OpenClaws' });
  }
});

// ── Fleet Aggregation (admin+) ──────────────────────────────────────────

// GET /auth/openclaws/fleet/health - fleet-wide health aggregation
router.get('/openclaws/fleet/health', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/fleet/health`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      const body = await orchRes.text();
      return res.status(orchRes.status).json({ error: body || 'Failed to get fleet health' });
    }

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] Fleet health error:', err);
    res.status(500).json({ error: 'Failed to get fleet health' });
  }
});

// GET /auth/openclaws/fleet/sessions - fleet-wide session aggregation
router.get('/openclaws/fleet/sessions', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/fleet/sessions`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      const body = await orchRes.text();
      return res.status(orchRes.status).json({ error: body || 'Failed to get fleet sessions' });
    }

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] Fleet sessions error:', err);
    res.status(500).json({ error: 'Failed to get fleet sessions' });
  }
});

// ── Admin: User Assignment ──────────────────────────────────────────────

// POST /auth/openclaws/:id/assign - assign user to OpenClaw (admin+)
router.post('/openclaws/:id/assign', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { userId } = req.body;
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${req.params.id}/assign`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}`,
      },
      body: JSON.stringify({ userId, assignedBy: req.user.id }),
    });

    if (!orchRes.ok) {
      const errBody = await orchRes.json().catch(() => ({}));
      return res.status(orchRes.status).json({ error: errBody.error || 'Failed to assign user' });
    }

    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.OPENCLAW_ASSIGN,
      resource: 'openclaw',
      metadata: { openclawId: req.params.id, targetUserId: userId },
    });

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] Assign user error:', err);
    res.status(500).json({ error: 'Failed to assign user' });
  }
});

// DELETE /auth/openclaws/:id/assign/:userId - unassign user from OpenClaw (admin+)
router.delete('/openclaws/:id/assign/:userId', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(
      `${ORCHESTRATOR_URL}/openclaws/${req.params.id}/assign/${req.params.userId}`,
      {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
      }
    );

    if (!orchRes.ok) {
      const errBody = await orchRes.json().catch(() => ({}));
      return res.status(orchRes.status).json({ error: errBody.error || 'Failed to unassign user' });
    }

    writeAuditLogSafe({
      ...auditOptsFromReq(req),
      action: ACTIONS.OPENCLAW_UNASSIGN,
      resource: 'openclaw',
      metadata: { openclawId: req.params.id, targetUserId: req.params.userId },
    });

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] Unassign user error:', err);
    res.status(500).json({ error: 'Failed to unassign user' });
  }
});

// GET /auth/openclaws/:id/assignments - list assignments (admin+)
router.get('/openclaws/:id/assignments', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${req.params.id}/assignments`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      return res.status(502).json({ error: 'Failed to list assignments' });
    }

    res.json(await orchRes.json());
  } catch (err) {
    console.error('[auth] List assignments error:', err);
    res.status(500).json({ error: 'Failed to list assignments' });
  }
});

// GET /auth/openclaws/:id/config - read OpenClaw config (admin+)
router.get('/openclaws/:id/config', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${req.params.id}/config`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      const body = await orchRes.text();
      return res.status(orchRes.status).json({ error: body || 'Failed to read config' });
    }

    const config = await orchRes.json();
    res.json(config);
  } catch (err) {
    console.error('[auth] Get config error:', err);
    res.status(500).json({ error: 'Failed to read config' });
  }
});

// PATCH /auth/openclaws/:id/config - update OpenClaw config (admin+)
router.patch('/openclaws/:id/config', async (req, res) => {
  try {
    if (!['admin', 'superadmin'].includes(req.user.role)) {
      return res.status(403).json({ error: 'Admin access required' });
    }

    const { config, restart } = req.body;
    if (!config || typeof config !== 'object') {
      return res.status(400).json({ error: 'config object is required' });
    }

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/openclaws/${req.params.id}/config`, {
      method: 'PATCH',
      headers: {
        Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ config, restart: restart === true }),
    });

    if (!orchRes.ok) {
      const body = await orchRes.text();
      return res.status(orchRes.status).json({ error: body || 'Failed to update config' });
    }

    const result = await orchRes.json();

    writeAuditLogSafe(req.pool, {
      ...auditOptsFromReq(req),
      action: 'OPENCLAW_CONFIG_UPDATE',
      resource: `openclaw:${req.params.id}`,
      metadata: { restart: restart === true },
    });

    res.json(result);
  } catch (err) {
    console.error('[auth] Patch config error:', err);
    res.status(500).json({ error: 'Failed to update config' });
  }
});

// GET /auth/openclaws/:id/drawio/snapshots - list DrawIO snapshots for current user
router.get('/openclaws/:id/drawio/snapshots', async (req, res) => {
  try {
    const openclawId = req.params.id;
    await assertOpenClawAccess(req, openclawId);
    const snapshots = await listDrawIOSnapshots(openclawId, req.user.id);
    res.json({ snapshots });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[auth] DrawIO snapshots list error:', err);
    }
    res.status(status).json({ error: err.message || 'Failed to list snapshots' });
  }
});

// POST /auth/openclaws/:id/drawio/snapshots - save DrawIO snapshot for current user
router.post('/openclaws/:id/drawio/snapshots', async (req, res) => {
  try {
    const openclawId = req.params.id;
    await assertOpenClawAccess(req, openclawId);

    const name = (req.body?.name || '').toString().trim();
    const xml = (req.body?.xml || '').toString();
    if (!xml.trim()) {
      return res.status(400).json({ error: 'xml is required' });
    }
    if (Buffer.byteLength(xml, 'utf8') > DRAWIO_XML_MAX_BYTES) {
      return res.status(413).json({ error: 'xml exceeds 10MB limit' });
    }

    const effectiveName = name || `diagram-${new Date().toISOString().replace(/[:.]/g, '-')}`;
    const xmlHash = crypto.createHash('sha256').update(xml).digest('hex');

    await pool.query(
      `insert into rbac.drawio_snapshots (openclaw_id, user_id, name, xml, xml_hash)
       values ($1, $2, $3, $4, $5)
       on conflict (openclaw_id, user_id, xml_hash)
       do update set
         name = excluded.name,
         xml = excluded.xml,
         updated_at = now()`,
      [openclawId, req.user.id, effectiveName, xml, xmlHash],
    );

    await pool.query(
      `delete from rbac.drawio_snapshots
        where id in (
          select id
            from rbac.drawio_snapshots
           where openclaw_id = $1 and user_id = $2
           order by updated_at desc, created_at desc
           offset 20
        )`,
      [openclawId, req.user.id],
    );

    const snapshots = await listDrawIOSnapshots(openclawId, req.user.id);
    res.status(201).json({ snapshots });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[auth] DrawIO snapshot save error:', err);
    }
    res.status(status).json({ error: err.message || 'Failed to save snapshot' });
  }
});

// DELETE /auth/openclaws/:id/drawio/snapshots/:snapshotId - delete DrawIO snapshot
router.delete('/openclaws/:id/drawio/snapshots/:snapshotId', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const snapshotId = req.params.snapshotId;
    await assertOpenClawAccess(req, openclawId);

    await pool.query(
      `delete from rbac.drawio_snapshots
        where id = $1 and openclaw_id = $2 and user_id = $3`,
      [snapshotId, openclawId, req.user.id],
    );

    const snapshots = await listDrawIOSnapshots(openclawId, req.user.id);
    res.json({ snapshots });
  } catch (err) {
    const status = err.status || 500;
    if (status >= 500) {
      console.error('[auth] DrawIO snapshot delete error:', err);
    }
    res.status(status).json({ error: err.message || 'Failed to delete snapshot' });
  }
});

// ── Legacy endpoints (kept for compatibility) ───────────────────────────

// POST /auth/guest - issue guest JWT
router.post('/guest', (req, res) => {
  const guestId = `guest:${uuidv4()}`;
  const token = jwt.sign(
    {
      sub: guestId,
      role: 'guest',
      iss: 'trinity-auth',
      iat: Math.floor(Date.now() / 1000),
    },
    JWT_SECRET,
    { expiresIn: GUEST_JWT_TTL }
  );

  // Audit: guest token issuance
  writeAuditLogSafe({
    userId: null,
    action: ACTIONS.AUTH_GUEST_ISSUED,
    resource: `user:${guestId}`,
    metadata: { guestId, ttl: GUEST_JWT_TTL },
    ip: req.ip,
    userAgent: req.get('user-agent') || null,
    requestPath: req.originalUrl ? req.originalUrl.split('?')[0] : req.path,
    httpMethod: req.method,
  });

  res.json({
    token,
    role: 'guest',
    expiresIn: GUEST_JWT_TTL,
    permissions: [
      'chat.read', 'canvas.view', 'memory.read',
      'skills.list', 'crons.list', 'settings.read',
      'governance.view', 'terminal.exec.safe',
    ],
  });
});

module.exports = router;
