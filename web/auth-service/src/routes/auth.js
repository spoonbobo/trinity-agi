const express = require('express');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { writeAuditLog, getEffectivePermissions } = require('../rbac');

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET;
const ORCHESTRATOR_URL = process.env.ORCHESTRATOR_URL;
const ORCHESTRATOR_SERVICE_TOKEN = process.env.ORCHESTRATOR_SERVICE_TOKEN;
const GUEST_JWT_TTL = 3600; // 1 hour

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

    const orchRes = await fetch(`${ORCHESTRATOR_URL}/users/${userId}/openclaws`, {
      headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
    });

    if (!orchRes.ok) {
      console.error(`[auth] Failed to list user openclaws: ${orchRes.status}`);
      return res.status(502).json({ error: 'Failed to list OpenClaws' });
    }

    const openclaws = await orchRes.json();

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
      const clawsRes = await fetch(`${ORCHESTRATOR_URL}/users/${userId}/openclaws`, {
        headers: { Authorization: `Bearer ${ORCHESTRATOR_SERVICE_TOKEN}` },
      });
      if (clawsRes.ok) {
        const claws = await clawsRes.json();
        if (!claws.some(c => c.id === openclawId)) {
          return res.status(403).json({ error: 'Not assigned to this OpenClaw' });
        }
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

    await writeAuditLog(
      req.user.id, 'openclaw.create', 'openclaw',
      { name, openclawId: data.id }, req.ip
    ).catch(() => {});

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

    await writeAuditLog(
      req.user.id, 'openclaw.delete', 'openclaw',
      { openclawId: req.params.id }, req.ip
    ).catch(() => {});

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

    await writeAuditLog(
      req.user.id, 'openclaw.assign', 'openclaw',
      { openclawId: req.params.id, targetUserId: userId }, req.ip
    ).catch(() => {});

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

    await writeAuditLog(
      req.user.id, 'openclaw.unassign', 'openclaw',
      { openclawId: req.params.id, targetUserId: req.params.userId }, req.ip
    ).catch(() => {});

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
