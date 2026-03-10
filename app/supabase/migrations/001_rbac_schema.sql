-- RBAC Schema (NIST Level 2: Roles + Permissions + Hierarchy)
-- Runs against supabase-db postgres

DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pgcrypto;
EXCEPTION WHEN insufficient_privilege THEN
  RAISE NOTICE 'pgcrypto extension requires elevated privileges; ensure it exists before running RBAC migrations';
END;
$$;

DO $$
BEGIN
  CREATE SCHEMA IF NOT EXISTS rbac;
EXCEPTION WHEN insufficient_privilege THEN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.schemata WHERE schema_name = 'rbac'
  ) THEN
    RAISE;
  END IF;
END;
$$;

-- Roles with hierarchy support
CREATE TABLE IF NOT EXISTS rbac.roles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT UNIQUE NOT NULL,
  parent_id   UUID REFERENCES rbac.roles(id) ON DELETE SET NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Fine-grained permission actions
CREATE TABLE IF NOT EXISTS rbac.permissions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  action      TEXT UNIQUE NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Role <-> Permission mapping
CREATE TABLE IF NOT EXISTS rbac.role_permissions (
  role_id       UUID NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
  permission_id UUID NOT NULL REFERENCES rbac.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- User <-> Role mapping (references GoTrue auth.users)
CREATE TABLE IF NOT EXISTS rbac.user_roles (
  user_id   UUID NOT NULL,
  role_id   UUID NOT NULL REFERENCES rbac.roles(id) ON DELETE CASCADE,
  granted_by UUID,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);

-- Indexes for role hierarchy traversal and role-based lookups
CREATE INDEX IF NOT EXISTS idx_roles_parent_id ON rbac.roles(parent_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role_id ON rbac.user_roles(role_id);

-- Audit log (may already be partitioned by migration 006)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'rbac' AND c.relname = 'audit_log'
  ) THEN
    CREATE TABLE rbac.audit_log (
      id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id     UUID,
      action      TEXT NOT NULL,
      resource    TEXT,
      metadata    JSONB DEFAULT '{}',
      ip          TEXT,
      created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
    );
  END IF;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_audit_log_user ON rbac.audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON rbac.audit_log(action);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON rbac.audit_log(created_at DESC);

-- Recursive CTE function: resolve all effective permissions for a user
CREATE OR REPLACE FUNCTION rbac.effective_permissions(p_user_id UUID)
RETURNS TABLE(action TEXT) AS $$
  WITH RECURSIVE role_tree AS (
    -- Direct roles
    SELECT r.id, r.parent_id
    FROM rbac.roles r
    JOIN rbac.user_roles ur ON ur.role_id = r.id
    WHERE ur.user_id = p_user_id
    UNION
    -- Inherited roles (walk up)
    SELECT r.id, r.parent_id
    FROM rbac.roles r
    JOIN role_tree rt ON r.id = rt.parent_id
  )
  SELECT DISTINCT p.action
  FROM role_tree rt
  JOIN rbac.role_permissions rp ON rp.role_id = rt.id
  JOIN rbac.permissions p ON p.id = rp.permission_id;
$$ LANGUAGE SQL STABLE;

-- Helper: check if user has a specific permission
CREATE OR REPLACE FUNCTION rbac.has_permission(p_user_id UUID, p_action TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM rbac.effective_permissions(p_user_id) ep WHERE ep.action = p_action
  );
$$ LANGUAGE SQL STABLE;

-- Helper: get user's highest role name
CREATE OR REPLACE FUNCTION rbac.user_role_name(p_user_id UUID)
RETURNS TEXT AS $$
  SELECT r.name
  FROM rbac.user_roles ur
  JOIN rbac.roles r ON r.id = ur.role_id
  WHERE ur.user_id = p_user_id
  ORDER BY
    CASE r.name
      WHEN 'superadmin' THEN 0
      WHEN 'admin' THEN 1
      WHEN 'user' THEN 2
      WHEN 'guest' THEN 3
      ELSE 4
    END
  LIMIT 1;
$$ LANGUAGE SQL STABLE;
