#!/usr/bin/env sh
set -eu

if [ "${AUTHENTIK_ENABLED:-false}" != "true" ]; then
  echo "[keycloak-idp] AUTHENTIK_ENABLED is false; skipping"
  exit 0
fi

if [ -z "${AUTHENTIK_ISSUER_URL:-}" ] || [ -z "${AUTHENTIK_CLIENT_ID:-}" ] || [ -z "${AUTHENTIK_CLIENT_SECRET:-}" ]; then
  echo "[keycloak-idp] Missing AUTHENTIK_ISSUER_URL / AUTHENTIK_CLIENT_ID / AUTHENTIK_CLIENT_SECRET"
  exit 1
fi

KC_SERVER="${KEYCLOAK_SERVER_URL:-http://keycloak:8080/keycloak}"
KC_REALM="${KEYCLOAK_REALM:-trinity}"
KC_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"

echo "[keycloak-idp] Waiting for Keycloak..."
for i in $(seq 1 60); do
  if curl -fsS "${KC_SERVER}/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "${KC_SERVER}/health/ready" >/dev/null 2>&1; then
  echo "[keycloak-idp] Keycloak not ready"
  exit 1
fi

/opt/keycloak/bin/kcadm.sh config credentials \
  --server "${KC_SERVER}" \
  --realm "${KC_ADMIN_REALM}" \
  --user "${KEYCLOAK_ADMIN}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}"

if /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/authentik" -r "${KC_REALM}" >/dev/null 2>&1; then
  echo "[keycloak-idp] authentik IdP already exists; updating"
  /opt/keycloak/bin/kcadm.sh update "identity-provider/instances/authentik" -r "${KC_REALM}" \
    -s "enabled=true" \
    -s "alias=authentik" \
    -s "providerId=oidc" \
    -s "config.useJwksUrl=true" \
    -s "config.authorizationUrl=${AUTHENTIK_ISSUER_URL%/}/authorize/" \
    -s "config.tokenUrl=${AUTHENTIK_ISSUER_URL%/}/token/" \
    -s "config.userInfoUrl=${AUTHENTIK_ISSUER_URL%/}/userinfo/" \
    -s "config.logoutUrl=${AUTHENTIK_ISSUER_URL%/}/end-session/" \
    -s "config.clientId=${AUTHENTIK_CLIENT_ID}" \
    -s "config.clientSecret=${AUTHENTIK_CLIENT_SECRET}" \
    -s "config.defaultScope=${AUTHENTIK_SCOPES:-openid profile email groups}" \
    -s "config.syncMode=FORCE"
else
  echo "[keycloak-idp] creating authentik IdP"
  /opt/keycloak/bin/kcadm.sh create "identity-provider/instances" -r "${KC_REALM}" \
    -s "alias=authentik" \
    -s "displayName=Authentik" \
    -s "providerId=oidc" \
    -s "enabled=true" \
    -s "storeToken=true" \
    -s "trustEmail=true" \
    -s "firstBrokerLoginFlowAlias=first broker login" \
    -s "config.useJwksUrl=true" \
    -s "config.authorizationUrl=${AUTHENTIK_ISSUER_URL%/}/authorize/" \
    -s "config.tokenUrl=${AUTHENTIK_ISSUER_URL%/}/token/" \
    -s "config.userInfoUrl=${AUTHENTIK_ISSUER_URL%/}/userinfo/" \
    -s "config.logoutUrl=${AUTHENTIK_ISSUER_URL%/}/end-session/" \
    -s "config.clientId=${AUTHENTIK_CLIENT_ID}" \
    -s "config.clientSecret=${AUTHENTIK_CLIENT_SECRET}" \
    -s "config.defaultScope=${AUTHENTIK_SCOPES:-openid profile email groups}" \
    -s "config.syncMode=FORCE"
fi

# Optional mapper: claim "groups" -> role names (realm roles)
if [ "${AUTHENTIK_GROUPS_MAPPER_ENABLED:-true}" = "true" ]; then
  if ! /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/authentik/mappers" -r "${KC_REALM}" | grep -q 'authentik-groups-to-roles'; then
    /opt/keycloak/bin/kcadm.sh create "identity-provider/instances/authentik/mappers" -r "${KC_REALM}" \
      -s "name=authentik-groups-to-roles" \
      -s "identityProviderAlias=authentik" \
      -s "identityProviderMapper=oidc-advanced-role-idp-mapper" \
      -s "config.newRoleName=trinity_user" \
      -s "config.claim=groups" \
      -s "config.claimValue=${AUTHENTIK_DEFAULT_GROUP_VALUE:-trinity_user}"
  fi
fi

echo "[keycloak-idp] Authentik wiring complete"
