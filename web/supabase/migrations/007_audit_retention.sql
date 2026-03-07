-- Migration 007: Audit log retention policy + automatic partition management
-- Requires pg_cron extension (available in Supabase/CloudNativePG).
--
-- Policy:
--   - Retention: 180 days (configurable by editing the cron job below)
--   - Partitions auto-created 6 months ahead on the 1st of each month
--   - Partitions older than retention are dropped on the 2nd of each month
--   - Archival: before dropping, partition data is exported to a summary row
--     in rbac.audit_archive_manifest for compliance traceability.

BEGIN;

-- ── Archive manifest table (tracks what was dropped and when) ───────────
CREATE TABLE IF NOT EXISTS rbac.audit_archive_manifest (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partition_name  TEXT NOT NULL,
  row_count       BIGINT NOT NULL DEFAULT 0,
  date_range_from DATE NOT NULL,
  date_range_to   DATE NOT NULL,
  dropped_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  retention_days  INTEGER NOT NULL,
  actions_summary JSONB DEFAULT '{}',
  UNIQUE(partition_name)
);

COMMENT ON TABLE rbac.audit_archive_manifest IS 'Records of dropped audit_log partitions for compliance traceability';

-- ── Retention function with manifest logging ────────────────────────────
-- Drops partitions older than retention_days, recording summary before drop.
CREATE OR REPLACE FUNCTION rbac.run_audit_retention(retention_days INTEGER DEFAULT 180)
RETURNS SETOF TEXT AS $$
DECLARE
  cutoff DATE := (now() - (retention_days || ' days')::INTERVAL)::DATE;
  rec RECORD;
  row_count BIGINT;
  part_year INTEGER;
  part_month INTEGER;
  part_start DATE;
  part_end DATE;
  action_summary JSONB;
BEGIN
  FOR rec IN
    SELECT c.relname AS part_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_inherits i ON i.inhrelid = c.oid
    JOIN pg_class parent ON parent.oid = i.inhparent
    WHERE n.nspname = 'rbac'
      AND parent.relname = 'audit_log'
      AND c.relkind = 'r'
    ORDER BY c.relname
  LOOP
    BEGIN
      -- Parse YYYY_MM from partition name
      part_year  := substring(rec.part_name FROM 'audit_log_(\d{4})_\d{2}')::INTEGER;
      part_month := substring(rec.part_name FROM 'audit_log_\d{4}_(\d{2})')::INTEGER;
      part_start := make_date(part_year, part_month, 1);
      part_end   := part_start + INTERVAL '1 month';

      IF part_end <= cutoff THEN
        -- Gather summary before dropping
        EXECUTE format('SELECT count(*) FROM rbac.%I', rec.part_name) INTO row_count;
        EXECUTE format(
          'SELECT COALESCE(jsonb_object_agg(action, cnt), ''{}''::jsonb) FROM (SELECT action, count(*) AS cnt FROM rbac.%I GROUP BY action) sub',
          rec.part_name
        ) INTO action_summary;

        -- Record in manifest
        INSERT INTO rbac.audit_archive_manifest
          (partition_name, row_count, date_range_from, date_range_to, retention_days, actions_summary)
        VALUES
          (rec.part_name, row_count, part_start, part_end, retention_days, action_summary)
        ON CONFLICT (partition_name) DO NOTHING;

        -- Drop the partition
        EXECUTE format('DROP TABLE rbac.%I', rec.part_name);
        RETURN NEXT 'rbac.' || rec.part_name || ' (dropped, ' || row_count || ' rows archived to manifest)';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RETURN NEXT 'rbac.' || rec.part_name || ' (skipped: ' || SQLERRM || ')';
    END;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- ── Enable pg_cron if available ─────────────────────────────────────────
-- pg_cron is pre-installed in Supabase but needs to be created in the DB.
-- This is idempotent; CREATE EXTENSION IF NOT EXISTS is safe.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron extension not available -- schedule cron jobs manually or via external scheduler';
END;
$$;

-- ── Schedule: create future partitions on 1st of each month at 00:05 UTC ─
DO $$
BEGIN
  -- Remove existing job if re-running migration
  PERFORM cron.unschedule('audit_create_partitions');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'audit_create_partitions',
    '5 0 1 * *',
    $$SELECT rbac.ensure_audit_partitions(6)$$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not schedule audit_create_partitions via pg_cron: %', SQLERRM;
END;
$$;

-- ── Schedule: retention cleanup on 2nd of each month at 00:05 UTC ───────
DO $$
BEGIN
  PERFORM cron.unschedule('audit_retention_cleanup');
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

DO $$
BEGIN
  PERFORM cron.schedule(
    'audit_retention_cleanup',
    '5 0 2 * *',
    $$SELECT rbac.run_audit_retention(180)$$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not schedule audit_retention_cleanup via pg_cron: %', SQLERRM;
END;
$$;

COMMIT;
