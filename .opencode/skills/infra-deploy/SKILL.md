---
name: infra-deploy
description: Operate the Trinity AGI Docker infrastructure -- build, deploy, monitor, troubleshoot the 14-service stack with nginx, Supabase, Keycloak, Vault, Grafana, and Loki.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity-agi
---

## What This Skill Covers

The complete Docker Compose infrastructure for Trinity AGI. 14 services, 6 volumes, nginx reverse proxy, monitoring stack, build/deploy workflows, and troubleshooting.

Source: `web/docker-compose.yml`, `web/nginx/`, `web/grafana/`, `web/loki/`, `web/fluentd/`, `web/vault/`, `web/keycloak/`, `web/scripts/`

## Service Map

| Service | Container | Port | Image |
|---------|-----------|------|-------|
| supabase-db | trinity-supabase-db | 5432 | supabase/postgres:15.8.1.127 |
| supabase-auth | trinity-supabase-auth | 9999 | supabase/gotrue:v2.170.0 |
| keycloak | trinity-keycloak | 8080 | quay.io/keycloak/keycloak:26.1 |
| vault | trinity-vault | 8200 | hashicorp/vault:1.15 |
| openclaw-gateway | trinity-openclaw | 18789 | Custom (node:22 + openclaw CLI) |
| terminal-proxy | trinity-terminal-proxy | 18790 | Custom (node:20-alpine + docker-cli) |
| auth-service | trinity-auth-service | 18791 | Custom (node:20-alpine) |
| nginx | trinity-nginx | 80 | nginx:alpine |
| grafana | trinity-grafana | 3000 | grafana/grafana:latest |
| loki | trinity-loki | 3100 | grafana/loki:latest |
| fluentd | trinity-fluentd | 24224 | fluent/fluentd:v1.16-1 |
| vault-init | (one-shot) | - | hashicorp/vault:1.15 |
| keycloak-idp-bootstrap | (one-shot) | - | quay.io/keycloak/keycloak:26.1 |
| frontend-builder | (build profile) | - | ghcr.io/cirruslabs/flutter:stable |

## Nginx Routes (`web/nginx/nginx.conf`)

| Route | Backend | Protocol |
|-------|---------|----------|
| `/` | Flutter SPA (flutter-build volume) | HTTP (try_files) |
| `/ws` | openclaw-gateway:18789 | WebSocket (24h timeout) |
| `/terminal/` | terminal-proxy:18790 | WebSocket (24h timeout) |
| `/auth/` | auth-service:18791 | HTTP |
| `/supabase/auth/` | supabase-auth:9999 | HTTP (rewrite prefix) |
| `/keycloak/` | keycloak:8080 | HTTP |
| `/__openclaw__/` | openclaw-gateway:18789 | HTTP/WS |
| `/v1/` | openclaw-gateway:18789 | HTTP (OpenAI-compatible) |
| `/tools/` | openclaw-gateway:18789 | HTTP |

## Build & Deploy

### Full deploy (after any source changes)

```bash
# Frontend (Dart changes)
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder

# Backend services (JS/YAML changes)
docker compose -f web/docker-compose.yml build --no-cache terminal-proxy auth-service

# Restart everything
docker compose -f web/docker-compose.yml up -d terminal-proxy auth-service
docker restart trinity-nginx

# AGENTS.md / extensions (no rebuild needed)
docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md
docker cp web/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts
docker restart trinity-openclaw
```

### Frontend only

```bash
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder
docker restart trinity-nginx
# User: Ctrl+Shift+R to hard-refresh
```

### Backend only (auth-service or terminal-proxy)

```bash
docker compose -f web/docker-compose.yml build --no-cache auth-service terminal-proxy
docker compose -f web/docker-compose.yml up -d auth-service terminal-proxy
```

### Gateway only (openclaw update)

```bash
docker compose -f web/docker-compose.yml build --no-cache openclaw-gateway
docker compose -f web/docker-compose.yml up -d openclaw-gateway
# Wait for healthy:
docker inspect --format='{{.State.Health.Status}}' trinity-openclaw
```

### Config sync (container -> host)

```bash
docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json web/openclaw.json
```

## Environment Variables

### Core Secrets (in `web/.env`)

| Variable | Purpose |
|----------|---------|
| OPENCLAW_GATEWAY_TOKEN | Gateway auth (shared across services + frontend build) |
| SUPABASE_JWT_SECRET | JWT signing (shared GoTrue <-> auth-service) |
| SUPABASE_ANON_KEY | GoTrue anonymous API key |
| SUPABASE_POSTGRES_PASSWORD | PostgreSQL password |
| KEYCLOAK_ADMIN_PASSWORD | Keycloak admin console |
| KEYCLOAK_CLIENT_SECRET | OIDC client secret |
| GRAFANA_PASSWORD | Grafana admin password |

### Optional: Authentik IdP

| Variable | Purpose |
|----------|---------|
| AUTHENTIK_ENABLED | Enable Authentik IdP wiring (default: false) |
| AUTHENTIK_ISSUER_URL | OIDC issuer URL |
| AUTHENTIK_CLIENT_ID / SECRET | OAuth credentials |

## Monitoring Stack

### Grafana (port 3000)

Dashboard: "Trinity AGI - RBAC Security" (UID: `trinity-rbac`)

Panels: Login Rate, Failed Logins, Role Assignments, Permission Denied Rate, Terminal Commands by Tier, Recent RBAC Errors

Datasource: Loki at `http://loki:3100`

### Loki (port 3100)

Log aggregation. Schema v12, filesystem storage, 168h retention.

### Fluentd (port 24224)

Collects container logs via Docker logging driver, parses JSON, pushes to Loki.

## Volumes

| Volume | Purpose | Persistent data |
|--------|---------|-----------------|
| openclaw-data | Gateway state | Sessions, skills, crons, workspace, WhatsApp auth, extensions |
| flutter-build | Compiled SPA | Built Flutter web output |
| supabase-db-data | PostgreSQL | All DB data (RBAC, GoTrue users) |
| vault-data | Vault secrets | KV store |
| grafana-data | Grafana state | Dashboards, preferences |
| loki-data | Log storage | Indexed logs |

**WARNING:** `openclaw-data` contains WhatsApp auth, sessions, credentials. Never `docker volume rm` without backup.

## Vault (`web/vault/`)

Dev mode with root token. Secrets at `secret/trinity/`:

| Path | Keys |
|------|------|
| `secret/trinity/supabase` | jwt_secret, anon_key, postgres_password |
| `secret/trinity/keycloak` | admin, client_secret |
| `secret/trinity/auth-service` | token (gateway token) |
| `secret/trinity/superadmin` | allowlist, enabled |

## Keycloak (`web/keycloak/`)

Realm: `trinity`. Client: `trinity-shell` (OIDC confidential). Roles: `trinity_guest`, `trinity_user`, `trinity_admin`.

Optional Authentik IdP broker configured by `keycloak-idp-bootstrap` one-shot container.

IdP chain: `Authentik -> Keycloak -> GoTrue -> auth-service`

## Troubleshooting

**Service won't start:**
```bash
docker compose -f web/docker-compose.yml logs <service> --tail 30
docker compose -f web/docker-compose.yml ps
```

**Gateway unhealthy:**
```bash
docker logs trinity-openclaw --tail 30
docker exec trinity-openclaw openclaw doctor --fix
```

**Frontend changes not showing:**
You forgot `build --no-cache` before `run`. Always rebuild the image first.

**Permission denied in terminal:**
Check RBAC: `docker logs trinity-terminal-proxy --tail 20`. The log shows `userRole`, `tier`, and `action` for every command.

**Auth 401/403:**
Check JWT: `docker logs trinity-auth-service --tail 20`. Verify `JWT_SECRET` matches between GoTrue and auth-service.

**DB schema issues:**
Migrations run on first `supabase-db` start. To re-run:
```bash
docker compose -f web/docker-compose.yml down supabase-db
docker volume rm web_supabase-db-data
docker compose -f web/docker-compose.yml up -d supabase-db
```

**Check all service health:**
```bash
docker compose -f web/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"
```
