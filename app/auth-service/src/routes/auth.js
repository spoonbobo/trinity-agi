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
const GUEST_JWT_TTL = 3600; // 1 hour

function normalizeWorkspacePart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '') || 'default';
}

function buildOpenClawWorkspace(tenantId, openclawId, suffix = '') {
  const workspace = `tenant_${normalizeWorkspacePart(tenantId)}__claw_${normalizeWorkspacePart(openclawId)}`;
  if (!suffix) return workspace;
  return `${workspace}__${normalizeWorkspacePart(suffix)}`;
}

function deriveTenantIdFromOpenClaw(openclaw, fallbackUserId) {
  return openclaw?.created_by || openclaw?.createdBy || fallbackUserId || openclaw?.id;
}

async function deriveLightRagScope(req, openclawId) {
  await assertOpenClawAccess(req, openclawId);
  const openclaw = await fetchOpenClawById(openclawId);
  const tenantId = deriveTenantIdFromOpenClaw(openclaw, req.user.id);
  const workspaceId = buildOpenClawWorkspace(tenantId, openclawId);
  return {
    tenantId,
    openclawId,
    workspaceId,
    userId: req.user.id,
  };
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

// GET /auth/openclaws/:id/lightrag-scope - derive the canonical LightRAG scope for this OpenClaw
router.get('/openclaws/:id/lightrag-scope', async (req, res) => {
  try {
    const openclawId = req.params.id;
    res.json(await deriveLightRagScope(req, openclawId));
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to derive LightRAG scope' });
  }
});

router.get('/openclaws/:id/lightrag-graph', async (req, res) => {
  try {
    const openclawId = req.params.id;
    const scope = await deriveLightRagScope(req, openclawId);

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

    const selectedLabel = (req.query.label || labels[0] || '').toString();
    if (!selectedLabel) {
      return res.json({
        tenantId: scope.tenantId,
        openclawId: scope.openclawId,
        workspaceId: scope.workspaceId,
        labels,
        selectedLabel: null,
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

    res.json({
      tenantId: scope.tenantId,
      openclawId: scope.openclawId,
      workspaceId: scope.workspaceId,
      labels,
      selectedLabel,
      graph,
    });
  } catch (err) {
    const statusCode = err.status || 500;
    res.status(statusCode).json({ error: err.message || 'Failed to fetch LightRAG graph' });
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
    if (xml.length > 2 * 1024 * 1024) {
      return res.status(413).json({ error: 'xml exceeds 2MB limit' });
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
