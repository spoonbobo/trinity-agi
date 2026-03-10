-- Migration 006: Convert rbac.audit_log to a time-partitioned table
-- Enables efficient retention (DROP PARTITION) and query performance at scale (10M+ rows/month).
-- Also adds context columns for forensic completeness.
--
-- Strategy:
--   1. Rename the existing table to audit_log_legacy
--   2. Create a new partitioned table with the same schema + new columns
--   3. Migrate existing data
--   4. Drop legacy table
--   5. Pre-create partitions for the current month + 6 months ahead
--   6. Create a helper function for auto-creating future partitions

BEGIN;

-- Skip entire migration if audit_log is already partitioned (re-run safe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'rbac' AND c.relname = 'audit_log' AND c.relkind = 'p'
  ) THEN
    RAISE EXCEPTION '__SKIP_MIGRATION__';
  END IF;
END;
$$;

-- ── Step 1: Rename old table ────────────────────────────────────────────
ALTER TABLE rbac.audit_log RENAME TO audit_log_legacy;

-- Drop old indexes (they reference the legacy table now)
DROP INDEX IF EXISTS rbac.idx_audit_log_user;
DROP INDEX IF EXISTS rbac.idx_audit_log_action;
DROP INDEX IF EXISTS rbac.idx_audit_log_created;

-- ── Step 2: Create partitioned table with new context columns ───────────
CREATE TABLE rbac.audit_log (
  id            UUID NOT NULL DEFAULT gen_random_uuid(),
  user_id       UUID,
  action        TEXT NOT NULL,
  resource      TEXT,
  metadata      JSONB DEFAULT '{}',
  ip            TEXT,
  user_agent    TEXT,
  request_path  TEXT,
  http_method   TEXT,
  session_id    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

COMMENT ON TABLE rbac.audit_log IS 'Immutable audit trail, monthly-partitioned by created_at';
COMMENT ON COLUMN rbac.audit_log.user_agent IS 'HTTP User-Agent header of the request';
COMMENT ON COLUMN rbac.audit_log.request_path IS 'HTTP path that triggered this audit event';
COMMENT ON COLUMN rbac.audit_log.http_method IS 'HTTP method (GET/POST/PUT/DELETE)';
COMMENT ON COLUMN rbac.audit_log.session_id IS 'Gateway or auth session ID for correlation';

-- ── Step 3: Create indexes on the partitioned table ─────────────────────
-- These are inherited by all child partitions automatically.
CREATE INDEX idx_audit_log_user       ON rbac.audit_log (user_id);
CREATE INDEX idx_audit_log_action     ON rbac.audit_log (action);
CREATE INDEX idx_audit_log_created    ON rbac.audit_log (created_at DESC);
CREATE INDEX idx_audit_log_resource   ON rbac.audit_log (resource);
CREATE INDEX idx_audit_log_session    ON rbac.audit_log (session_id) WHERE session_id IS NOT NULL;

-- ── Step 4: Create partition management functions ───────────────────────

-- Creates a monthly partition if it doesn't exist.
-- Call: SELECT rbac.create_audit_partition('2026-03-01');
CREATE OR REPLACE FUNCTION rbac.create_audit_partition(partition_date DATE)
RETURNS TEXT AS $$
DECLARE
  start_date DATE := date_trunc('month', partition_date)::DATE;
  end_date   DATE := (date_trunc('month', partition_date) + INTERVAL '1 month')::DATE;
  part_name  TEXT := 'audit_log_' || to_char(start_date, 'YYYY_MM');
  full_name  TEXT := 'rbac.' || part_name;
BEGIN
  -- Check if partition already exists
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'rbac' AND c.relname = part_name
  ) THEN
    RETURN full_name || ' (already exists)';
  END IF;

  EXECUTE format(
    'CREATE TABLE %I.%I PARTITION OF rbac.audit_log FOR VALUES FROM (%L) TO (%L)',
    'rbac', part_name, start_date, end_date
  );

  RETURN full_name || ' (created)';
END;
$$ LANGUAGE plpgsql;

-- Creates partitions from start_month to end_month (inclusive).
CREATE OR REPLACE FUNCTION rbac.ensure_audit_partitions(months_ahead INTEGER DEFAULT 6)
RETURNS SETOF TEXT AS $$
DECLARE
  m INTEGER;
  target_date DATE;
BEGIN
  FOR m IN 0..months_ahead LOOP
    target_date := (date_trunc('month', now()) + (m || ' months')::INTERVAL)::DATE;
    RETURN NEXT rbac.create_audit_partition(target_date);
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Drops partitions older than the given retention period.
-- Returns the names of dropped partitions.
CREATE OR REPLACE FUNCTION rbac.drop_old_audit_partitions(retention_days INTEGER DEFAULT 180)
RETURNS SETOF TEXT AS $$
DECLARE
  cutoff DATE := (now() - (retention_days || ' days')::INTERVAL)::DATE;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT c.relname AS part_name,
           pg_get_expr(c.relpartbound, c.oid) AS bound_expr
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    JOIN pg_class parent ON parent.oid = i.inhparent
    WHERE n.nspname = 'rbac'
      AND parent.relname = 'audit_log'
      AND c.relkind = 'r'
    ORDER BY c.relname
  LOOP
    -- Extract the upper bound date from the partition bound expression.
    -- Partition names follow the pattern audit_log_YYYY_MM.
    -- If the partition name indicates a month entirely before the cutoff, drop it.
    DECLARE
      part_year  INTEGER;
      part_month INTEGER;
      part_end   DATE;
    BEGIN
      -- Parse YYYY_MM from partition name (e.g., audit_log_2025_06)
      part_year  := substring(rec.part_name FROM 'audit_log_(\d{4})_\d{2}')::INTEGER;
      part_month := substring(rec.part_name FROM 'audit_log_\d{4}_(\d{2})')::INTEGER;
      part_end   := make_date(part_year, part_month, 1) + INTERVAL '1 month';

      IF part_end <= cutoff THEN
        EXECUTE format('DROP TABLE rbac.%I', rec.part_name);
        RETURN NEXT 'rbac.' || rec.part_name || ' (dropped, ended ' || part_end::TEXT || ')';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Skip partitions with unexpected names
      CONTINUE;
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ── Step 5: Pre-create partitions ───────────────────────────────────────
-- Create partitions to fully cover legacy data, then current month + 6 ahead.
DO $$
DECLARE
  min_legacy_ts TIMESTAMPTZ;
  max_legacy_ts TIMESTAMPTZ;
  legacy_start DATE;
  legacy_end DATE;
  m INTEGER;
  target_date DATE;
BEGIN
  SELECT min(created_at), max(created_at)
  INTO min_legacy_ts, max_legacy_ts
  FROM rbac.audit_log_legacy;

  IF min_legacy_ts IS NOT NULL THEN
    legacy_start := date_trunc('month', min_legacy_ts)::DATE;
    legacy_end := date_trunc('month', max_legacy_ts)::DATE;
    target_date := legacy_start;
    WHILE target_date <= legacy_end LOOP
      PERFORM rbac.create_audit_partition(target_date);
      target_date := (target_date + INTERVAL '1 month')::DATE;
    END LOOP;
  END IF;

  -- Current month + 6 ahead
  FOR m IN 0..6 LOOP
    target_date := (date_trunc('month', now()) + (m || ' months')::INTERVAL)::DATE;
    PERFORM rbac.create_audit_partition(target_date);
  END LOOP;
END;
$$;

-- ── Step 6: Migrate legacy data ─────────────────────────────────────────
-- New columns (user_agent, request_path, http_method, session_id) are NULL for legacy rows.
INSERT INTO rbac.audit_log (id, user_id, action, resource, metadata, ip, created_at)
SELECT id, user_id, action, resource, metadata, ip, created_at
FROM rbac.audit_log_legacy;

-- ── Step 7: Drop legacy table ───────────────────────────────────────────
DROP TABLE rbac.audit_log_legacy;

COMMIT;
