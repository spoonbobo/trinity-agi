const express = require('express');
const cors = require('cors');
const { verifyToken, resolveRole } = require('./middleware');
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');

const app = express();
const PORT = parseInt(process.env.AUTH_SERVICE_PORT || '18791');

app.use(cors());
app.use(express.json());

// Health check (no auth)
app.get('/auth/health', (req, res) => {
  res.json({ status: 'ok', service: 'trinity-auth' });
});

// Auth middleware for all /auth/* routes (except health)
app.use('/auth', verifyToken, resolveRole);

// Routes
app.use('/auth', authRoutes);
app.use('/auth/users', usersRoutes);

app.listen(PORT, '0.0.0.0', () => {
  console.log(`[auth-service] listening on port ${PORT}`);
});
