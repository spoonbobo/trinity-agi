const express = require('express');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { writeAuditLog, getEffectivePermissions } = require('../rbac');

const router = express.Router();

const JWT_SECRET = process.env.JWT_SECRET;
const OPENCLAW_GATEWAY_TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;
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

// POST /auth/session - exchange auth JWT for scoped gateway session token
router.post('/session', async (req, res) => {
  try {
    const sessionToken = OPENCLAW_GATEWAY_TOKEN;

    await writeAuditLog(
      req.user.id,
      'auth.session.create',
      'gateway',
      { role: req.user.role },
      req.ip
    );

    res.json({
      gatewayToken: sessionToken,
      role: req.user.role,
      permissions: req.user.permissions,
      expiresIn: 86400,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to create session' });
  }
});

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
