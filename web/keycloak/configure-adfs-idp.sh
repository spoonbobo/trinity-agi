#!/usr/bin/env sh
set -eu

if [ "${ADFS_ENABLED:-false}" != "true" ]; then
  echo "[keycloak-idp] ADFS_ENABLED is false; skipping"
  exit 0
fi

# Require either metadataUrl or manual ssoUrl
if [ -z "${ADFS_METADATA_URL:-}" ] && [ -z "${ADFS_SSO_URL:-}" ]; then
  echo "[keycloak-idp] Missing ADFS_METADATA_URL or ADFS_SSO_URL"
  exit 1
fi

KC_SERVER="${KEYCLOAK_SERVER_URL:-http://keycloak:8080/keycloak}"
KC_REALM="${KEYCLOAK_REALM:-trinity}"
KC_ADMIN_REALM="${KEYCLOAK_ADMIN_REALM:-master}"

ALIAS="adfs"
DISPLAY_NAME="${ADFS_DISPLAY_NAME:-ADFS Login}"
NAME_ID_FORMAT="${ADFS_NAMEID_FORMAT:-urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress}"
TRUST_EMAIL="${ADFS_TRUST_EMAIL:-true}"

echo "[keycloak-idp] Waiting for Keycloak..."
for i in $(seq 1 60); do
  if curl -fsS "${KC_SERVER}/health/ready" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

if ! curl -fsS "${KC_SERVER}/health/ready" >/dev/null 2>&1; then
  echo "[keycloak-idp] Keycloak not ready after 120s"
  exit 1
fi

echo "[keycloak-idp] Authenticating to Keycloak admin CLI..."
/opt/keycloak/bin/kcadm.sh config credentials \
  --server "${KC_SERVER}" \
  --realm "${KC_ADMIN_REALM}" \
  --user "${KEYCLOAK_ADMIN}" \
  --password "${KEYCLOAK_ADMIN_PASSWORD}"

# ─── Build SAML config arguments ──────────────────────────────────────────
# If metadataUrl is provided, Keycloak will auto-discover SSO/SLO/cert from it.
# Otherwise fall back to manual endpoints.

build_saml_config() {
  CONFIG_ARGS=""

  if [ -n "${ADFS_METADATA_URL:-}" ]; then
    CONFIG_ARGS="${CONFIG_ARGS} -s config.useMetadataDescriptorUrl=true"
    CONFIG_ARGS="${CONFIG_ARGS} -s config.metadataDescriptorUrl=${ADFS_METADATA_URL}"
  fi

  # Manual endpoints override metadata-discovered values
  if [ -n "${ADFS_SSO_URL:-}" ]; then
    CONFIG_ARGS="${CONFIG_ARGS} -s config.singleSignOnServiceUrl=${ADFS_SSO_URL}"
  fi
  if [ -n "${ADFS_SLO_URL:-}" ]; then
    CONFIG_ARGS="${CONFIG_ARGS} -s config.singleLogoutServiceUrl=${ADFS_SLO_URL}"
  fi
  if [ -n "${ADFS_SIGNING_CERT:-}" ]; then
    CONFIG_ARGS="${CONFIG_ARGS} -s config.signingCertificate=${ADFS_SIGNING_CERT}"
    CONFIG_ARGS="${CONFIG_ARGS} -s config.wantAssertionsSigned=true"
    CONFIG_ARGS="${CONFIG_ARGS} -s config.validateSignature=true"
  fi

  CONFIG_ARGS="${CONFIG_ARGS} -s config.nameIDPolicyFormat=${NAME_ID_FORMAT}"
  CONFIG_ARGS="${CONFIG_ARGS} -s config.principalType=ATTRIBUTE"
  CONFIG_ARGS="${CONFIG_ARGS} -s config.principalAttribute=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
  CONFIG_ARGS="${CONFIG_ARGS} -s config.syncMode=FORCE"
  # POST binding is standard for ADFS
  CONFIG_ARGS="${CONFIG_ARGS} -s config.postBindingResponse=true"
  CONFIG_ARGS="${CONFIG_ARGS} -s config.postBindingAuthnRequest=true"
  CONFIG_ARGS="${CONFIG_ARGS} -s config.forceAuthn=false"

  echo "${CONFIG_ARGS}"
}

SAML_CONFIG=$(build_saml_config)

# ─── Create or update the SAML IdP ───────────────────────────────────────
if /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/${ALIAS}" -r "${KC_REALM}" >/dev/null 2>&1; then
  echo "[keycloak-idp] ${ALIAS} IdP already exists; updating"
  eval /opt/keycloak/bin/kcadm.sh update "identity-provider/instances/${ALIAS}" -r "${KC_REALM}" \
    -s "enabled=true" \
    -s "alias=${ALIAS}" \
    -s "displayName=${DISPLAY_NAME}" \
    -s "providerId=saml" \
    -s "trustEmail=${TRUST_EMAIL}" \
    ${SAML_CONFIG}
else
  echo "[keycloak-idp] Creating ${ALIAS} SAML IdP"
  eval /opt/keycloak/bin/kcadm.sh create "identity-provider/instances" -r "${KC_REALM}" \
    -s "alias=${ALIAS}" \
    -s "displayName=${DISPLAY_NAME}" \
    -s "providerId=saml" \
    -s "enabled=true" \
    -s "storeToken=true" \
    -s "trustEmail=${TRUST_EMAIL}" \
    -s "firstBrokerLoginFlowAlias=first broker login" \
    ${SAML_CONFIG}
fi

# ─── Optional mapper: SAML attribute -> realm role ────────────────────────
# Maps the ADFS role/group claim to Keycloak realm roles
if [ "${ADFS_ROLE_MAPPER_ENABLED:-true}" = "true" ]; then
  ROLE_ATTR="${ADFS_ROLE_ATTRIBUTE:-http://schemas.microsoft.com/ws/2008/06/identity/claims/role}"
  DEFAULT_ROLE="${ADFS_DEFAULT_ROLE:-trinity_user}"

  MAPPER_NAME="adfs-role-to-realm-role"
  if ! /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" 2>/dev/null | grep -q "${MAPPER_NAME}"; then
    echo "[keycloak-idp] Creating role mapper: ${MAPPER_NAME}"
    /opt/keycloak/bin/kcadm.sh create "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" \
      -s "name=${MAPPER_NAME}" \
      -s "identityProviderAlias=${ALIAS}" \
      -s "identityProviderMapper=saml-advanced-role-idp-mapper" \
      -s "config.syncMode=INHERIT" \
      -s "config.attributes=[{\"key\":\"${ROLE_ATTR}\",\"value\":\"${DEFAULT_ROLE}\"}]" \
      -s "config.role=trinity_user"
  else
    echo "[keycloak-idp] Role mapper ${MAPPER_NAME} already exists; skipping"
  fi

  # Also create an email attribute mapper so user profile is populated
  EMAIL_MAPPER_NAME="adfs-email-attribute"
  if ! /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" 2>/dev/null | grep -q "${EMAIL_MAPPER_NAME}"; then
    echo "[keycloak-idp] Creating email mapper: ${EMAIL_MAPPER_NAME}"
    /opt/keycloak/bin/kcadm.sh create "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" \
      -s "name=${EMAIL_MAPPER_NAME}" \
      -s "identityProviderAlias=${ALIAS}" \
      -s "identityProviderMapper=saml-user-attribute-idp-mapper" \
      -s "config.syncMode=INHERIT" \
      -s "config.user.attribute=email" \
      -s "config.attribute.name=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
  else
    echo "[keycloak-idp] Email mapper ${EMAIL_MAPPER_NAME} already exists; skipping"
  fi

  # First name mapper
  FNAME_MAPPER_NAME="adfs-firstname-attribute"
  if ! /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" 2>/dev/null | grep -q "${FNAME_MAPPER_NAME}"; then
    echo "[keycloak-idp] Creating first name mapper: ${FNAME_MAPPER_NAME}"
    /opt/keycloak/bin/kcadm.sh create "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" \
      -s "name=${FNAME_MAPPER_NAME}" \
      -s "identityProviderAlias=${ALIAS}" \
      -s "identityProviderMapper=saml-user-attribute-idp-mapper" \
      -s "config.syncMode=INHERIT" \
      -s "config.user.attribute=firstName" \
      -s "config.attribute.name=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname"
  else
    echo "[keycloak-idp] First name mapper ${FNAME_MAPPER_NAME} already exists; skipping"
  fi

  # Last name mapper
  LNAME_MAPPER_NAME="adfs-lastname-attribute"
  if ! /opt/keycloak/bin/kcadm.sh get "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" 2>/dev/null | grep -q "${LNAME_MAPPER_NAME}"; then
    echo "[keycloak-idp] Creating last name mapper: ${LNAME_MAPPER_NAME}"
    /opt/keycloak/bin/kcadm.sh create "identity-provider/instances/${ALIAS}/mappers" -r "${KC_REALM}" \
      -s "name=${LNAME_MAPPER_NAME}" \
      -s "identityProviderAlias=${ALIAS}" \
      -s "identityProviderMapper=saml-user-attribute-idp-mapper" \
      -s "config.syncMode=INHERIT" \
      -s "config.user.attribute=lastName" \
      -s "config.attribute.name=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname"
  else
    echo "[keycloak-idp] Last name mapper ${LNAME_MAPPER_NAME} already exists; skipping"
  fi
fi

echo "[keycloak-idp] ADFS SAML wiring complete"
echo "[keycloak-idp] SP metadata available at: ${KC_SERVER}/realms/${KC_REALM}/broker/${ALIAS}/endpoint/descriptor"
echo "[keycloak-idp] Import the above URL as a Relying Party Trust in ADFS"
