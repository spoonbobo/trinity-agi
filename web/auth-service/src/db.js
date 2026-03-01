const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.POSTGRES_HOST || 'supabase-db',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
  database: process.env.POSTGRES_DB || 'supabase',
  user: process.env.POSTGRES_USER || 'postgres',
  password: process.env.POSTGRES_PASSWORD,
});

module.exports = { pool };
