-- Per-user OpenClaw gateway tenant registry
-- Used by the gateway-orchestrator to track per-user pod provisioning.

CREATE TABLE IF NOT EXISTS rbac.tenants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL UNIQUE,
    gateway_token   TEXT NOT NULL,
    pod_name        TEXT,
    service_name    TEXT,
    pvc_name        TEXT,
    namespace       TEXT NOT NULL DEFAULT 'trinity',
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'provisioning', 'running', 'error', 'deleting')),
    error_message   TEXT,
    port            INTEGER NOT NULL DEFAULT 18789,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tenants_user_id ON rbac.tenants(user_id);
CREATE INDEX IF NOT EXISTS idx_tenants_status ON rbac.tenants(status);
CREATE INDEX IF NOT EXISTS idx_tenants_pod_name ON rbac.tenants(pod_name);

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION rbac.update_tenant_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_tenants_updated_at ON rbac.tenants;
CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON rbac.tenants
    FOR EACH ROW
    EXECUTE FUNCTION rbac.update_tenant_timestamp();

-- Comment
COMMENT ON TABLE rbac.tenants IS 'Per-user OpenClaw gateway instance registry for multi-tenant orchestration';
