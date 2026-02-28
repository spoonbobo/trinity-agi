#!/bin/sh
# Vault initialization and secrets configuration script

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"

export VAULT_ADDR
export VAULT_TOKEN

echo "[vault-init] Waiting for Vault to be ready..."
count=0
while [ $count -lt 30 ]; do
  if vault status > /dev/null 2>&1; then
    echo "[vault-init] Vault is ready"
    break
  fi
  sleep 2
  count=$((count + 1))
done

if [ $count -ge 30 ]; then
  echo "[vault-init] Timeout waiting for Vault"
  exit 1
fi

echo "[vault-init] Using token: $(echo "$VAULT_TOKEN" | cut -c1-4)..."

# Enable KV secrets engine v2 (ignore error if already enabled)
echo "[vault-init] Enabling KV secrets engine..."
vault secrets enable -version=2 kv 2>/dev/null \
  || vault secrets enable -path=secret -version=2 kv 2>/dev/null \
  || echo "[vault-init] KV engine already enabled (ok)"

sleep 1

# Write Trinity secrets
echo "[vault-init] Writing secrets..."

# Supabase secrets
vault kv put secret/trinity/supabase \
  jwt_secret="${SUPABASE_JWT_SECRET:-test-jwt}" \
  anon_key="${SUPABASE_ANON_KEY:-test-anon}" \
  postgres_password="${SUPABASE_POSTGRES_PASSWORD:-test-pg}" \
  2>&1 || echo "[vault-init] WARN: failed to write supabase secrets"

# Keycloak secrets
vault kv put secret/trinity/keycloak \
  admin="${KEYCLOAK_ADMIN_PASSWORD:-test}" \
  client_secret="${KEYCLOAK_CLIENT_SECRET:-test}" \
  2>&1 || echo "[vault-init] WARN: failed to write keycloak secrets"

# Auth service secrets
vault kv put secret/trinity/auth-service \
  token="${OPENCLAW_GATEWAY_TOKEN:-test}" \
  2>&1 || echo "[vault-init] WARN: failed to write auth-service secrets"

# Superadmin configuration
vault kv put secret/trinity/superadmin \
  allowlist="${SUPERADMIN_ALLOWLIST:-}" \
  enabled="${ENABLE_DEFAULT_SUPERADMIN:-true}" \
  2>&1 || echo "[vault-init] WARN: failed to write superadmin config"

echo "[vault-init] Secrets configured"
echo "[vault-init] Vault UI: http://localhost:8200"
echo "[vault-init] Token: $VAULT_TOKEN"
