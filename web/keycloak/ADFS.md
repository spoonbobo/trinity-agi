# ADFS -> Keycloak (SAML Broker) Wiring

This stack can broker your corporate ADFS (or any SAML 2.0 IdP) through Keycloak into the Trinity auth flow.

## Prerequisites

From your ADFS administrator, you need:

1. **Federation Metadata URL** -- typically:
   ```
   https://<adfs-server>/FederationMetadata/2007-06/FederationMetadata.xml
   ```
2. A **Relying Party Trust** created in ADFS for Keycloak (see "ADFS Side Setup" below)
3. The following ADFS claims configured:
   - Name ID (email or UPN)
   - Email address (`http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress`)
   - Given name (`http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname`)
   - Surname (`http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname`)
   - Role/Group (optional: `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`)

## Enable (Kubernetes / Helm)

In your Helm values override (e.g., `values.prod.yaml`):

```yaml
keycloak:
  adfs:
    enabled: true
    metadataUrl: "https://adfs.corp.com/FederationMetadata/2007-06/FederationMetadata.xml"
    # Or supply endpoints manually instead of metadataUrl:
    # ssoUrl: "https://adfs.corp.com/adfs/ls/"
    # sloUrl: "https://adfs.corp.com/adfs/ls/"
    # signingCert: "<base64-encoded-cert>"
    displayName: "Corporate SSO"
    trustEmail: true
    roleMapperEnabled: true
    roleAttribute: "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
    defaultRole: "trinity_user"
```

Then upgrade:

```bash
helm upgrade trinity ./k8s/charts/trinity-platform -n trinity -f values.prod.yaml
```

The `keycloak-adfs-bootstrap` Job runs as a post-install/post-upgrade hook and configures the SAML IdP automatically.

## Enable (Docker Compose)

Set these env vars in `web/.env`:

```env
ADFS_ENABLED=true
ADFS_METADATA_URL=https://adfs.corp.com/FederationMetadata/2007-06/FederationMetadata.xml
ADFS_DISPLAY_NAME=Corporate SSO
ADFS_TRUST_EMAIL=true
ADFS_ROLE_MAPPER_ENABLED=true
ADFS_ROLE_ATTRIBUTE=http://schemas.microsoft.com/ws/2008/06/identity/claims/role
ADFS_DEFAULT_ROLE=trinity_user
```

Then restart:

```bash
docker compose -f web/docker-compose.yml up -d --build keycloak
# Run the bootstrap script manually:
docker exec trinity-keycloak /bin/sh /opt/keycloak/data/import/configure-adfs-idp.sh
```

## ADFS Side Setup

After Keycloak is configured, import the SP metadata into ADFS:

1. Get the Keycloak SP metadata URL:
   ```
   http://<keycloak-host>/keycloak/realms/trinity/broker/adfs/endpoint/descriptor
   ```
2. In ADFS Management Console:
   - **Add Relying Party Trust** > Import from URL > paste the metadata URL above
   - Or import the XML file if your ADFS cannot reach Keycloak directly
3. Configure **Claim Issuance Rules**:
   - Rule 1: Send LDAP Attributes as Claims (E-Mail, Given-Name, Surname)
   - Rule 2: Transform an Incoming Claim (UPN -> Name ID, format: Email)
   - Rule 3 (optional): Send Group Membership as Claim (for role mapping)

## How it works

```
Browser
  -> Keycloak login page (shows "ADFS Login" button)
  -> SAML AuthnRequest to ADFS
  -> User authenticates at ADFS
  -> SAML Response back to Keycloak
  -> Keycloak creates/links local user ("first broker login" flow)
  -> OIDC token issued to trinity-shell client
  -> GoTrue / auth-service receives the Keycloak OIDC token as usual
```

## Attribute Mappers (auto-created)

The bootstrap script creates these mappers automatically:

| Mapper | SAML Attribute | Keycloak User Attribute |
|--------|---------------|------------------------|
| `adfs-email-attribute` | `emailaddress` | `email` |
| `adfs-firstname-attribute` | `givenname` | `firstName` |
| `adfs-lastname-attribute` | `surname` | `lastName` |
| `adfs-role-to-realm-role` | `role` claim | Realm role mapping |

## Role Mapping

Map ADFS groups/roles to Keycloak realm roles:

| ADFS Role/Group | Keycloak Realm Role |
|-----------------|-------------------|
| (default) | `trinity_user` |
| `trinity_admin` | `trinity_admin` |
| `trinity_guest` | `trinity_guest` |

Keycloak realm roles then map to RBAC permissions via `auth-service`.

## Troubleshooting

1. **Check the bootstrap job logs:**
   ```bash
   kubectl logs job/keycloak-adfs-bootstrap-<revision> -n trinity
   ```

2. **Verify the IdP was created:**
   ```
   http://localhost:18080/keycloak/admin -> trinity realm -> Identity Providers
   ```

3. **Test the SAML flow:**
   ```
   http://localhost:18080/keycloak/realms/trinity/account
   ```
   You should see an "ADFS Login" button.

4. **Common issues:**
   - **Certificate mismatch:** Ensure `signingCert` matches the ADFS token-signing cert
   - **Clock skew:** SAML assertions have strict time windows; sync NTP
   - **NameID format:** If ADFS sends UPN instead of email, update `nameIdFormat`
   - **Redirect loops:** Ensure ADFS Relying Party Trust has the correct Keycloak endpoint
