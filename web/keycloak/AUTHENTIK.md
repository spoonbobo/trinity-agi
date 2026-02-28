# Authentik -> Keycloak (Broker) Wiring

This stack is wired so Keycloak can broker your company Authentik IdP.

## Enable

Set these env vars (in `web/.env` or your deployment environment):

```env
AUTHENTIK_ENABLED=true
AUTHENTIK_ISSUER_URL=https://authentik.example.com/application/o/trinity/
AUTHENTIK_CLIENT_ID=<client-id>
AUTHENTIK_CLIENT_SECRET=<client-secret>
AUTHENTIK_SCOPES=openid profile email groups

# Optional mapper defaults
AUTHENTIK_GROUPS_MAPPER_ENABLED=true
AUTHENTIK_DEFAULT_GROUP_VALUE=trinity_user
```

Then restart:

```bash
docker compose -f web/docker-compose.yml up -d --build keycloak keycloak-idp-bootstrap supabase-auth
```

## How it works

- `keycloak-idp-bootstrap` logs into Keycloak admin API and creates/updates an IdP alias `authentik` in realm `trinity`.
- GoTrue still uses Keycloak as external provider.
- Your Flutter login continues to call GoTrue `/authorize?provider=keycloak`.

## Role mapping recommendation

Map Authentik groups to Keycloak realm roles:

- `trinity_guest`
- `trinity_user`
- `trinity_admin`

Then map Keycloak roles to your RBAC assignment policy in `auth-service`.
