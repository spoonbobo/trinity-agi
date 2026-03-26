---
name: k8s-deploy
description: Operate the Trinity AGI Kubernetes infrastructure -- Helm charts, multi-tenant per-user OpenClaw pods, Vault Agent Injector secrets, minikube dev, and production deployment.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity
---

## What This Skill Covers

Multi-tenant Kubernetes deployment for Trinity AGI. Each user gets an isolated OpenClaw sandbox with its own state, sessions, and workspace. Shared platform services (DB, auth, Keycloak, Vault, monitoring) run once; per-user OpenClaw sandboxes are managed by OpenShell Gateway.

Source: `k8s/charts/`, `src/openshell-bridge/`, `src/docker-compose.yml` (legacy, deprecated)

## Architecture

```
Browser -> Ingress -> nginx -> openshell-bridge:18800
                                  |
                      Parses JWT, routes to OpenShell sandbox
                                  |
                         OpenShell Gateway (manages per-user sandboxes)
                                  |
                      PostgreSQL (rbac.tenants table)
```

## Service Map

| Service | Port | Image | Replicas | Purpose |
|---------|------|-------|----------|---------|
| supabase-db | 5432 | supabase/postgres:15.8.1.127 | 1 (StatefulSet) | PostgreSQL (RBAC, GoTrue, Keycloak schemas) |
| supabase-auth | 9999 | supabase/gotrue:v2.170.0 | 1 | User auth (email/password + OIDC) |
| keycloak | 8080 | quay.io/keycloak/keycloak:26.1 | 1 | IdP broker (LDAP/AD/OIDC) |
| vault | 8200 | hashicorp/vault:1.15 | 1 | Secrets management |
| auth-service | 18791 | ghcr.io/spoonbobo/trinity/auth-service | 1 | JWT verify + RBAC + pod provisioning trigger |
| openshell-bridge | 18800 | ghcr.io/spoonbobo/trinity/openshell-bridge | 2+ (HPA) | Routes users to OpenClaw sandboxes via OpenShell Gateway |
| nginx | 80 | nginx:1.27-alpine | 1 | Reverse proxy + SPA host (app subdomain) |
| site | 3000 | ghcr.io/spoonbobo/trinity/site | 1-2 | Marketing site + docs (Next.js, site subdomain) |
| loki | 3100 | grafana/loki:3.4.2 | 1 (StatefulSet) | Log aggregation |
| grafana | 3000 | grafana/grafana:11.5.2 | 1 | Monitoring dashboards |
| fluentd | - | fluent/fluentd:v1.16-1 | DaemonSet | Log collection |
| openclaw-{userId} | 18789 | (OpenShell sandbox) | 1 per user | Per-user AI gateway (managed by OpenShell Gateway) |

## Helm Charts

### trinity-platform (deploy once)

All shared services. Source: `k8s/charts/trinity-platform/`

```bash
helm install trinity k8s/charts/trinity-platform \
  -n trinity --create-namespace \
  -f k8s/charts/trinity-platform/values.minikube.yaml
```

### Per-user OpenClaw sandboxes

Per-user OpenClaw instances are now managed by OpenShell Gateway as sandboxes — no separate Helm chart or manual provisioning required.

## Subdomain Routing

Two separate Ingress resources route traffic by subdomain:

| Subdomain | Ingress | Backend | Content |
|-----------|---------|---------|---------|
| `www.trinity.work` (or `trinity.work`) | `trinity-site-ingress` | site:3000 | Marketing landing page + docs (Next.js) |
| `app.trinity.work` | `trinity-ingress` | nginx:80 | Flutter shell + all APIs |

Configure subdomains in your Helm override file:
```yaml
site:
  host: "www.trinity.work"
ingress:
  host: "app.trinity.work"
```

## Nginx Routes (app subdomain, updated for multi-tenant)

All routes below are on the **app subdomain** (`app.trinity.work`):

| Route | Backend | Protocol | Notes |
|-------|---------|----------|-------|
| `/` | Flutter SPA (static) | HTTP | try_files |
| `/ws` | openshell-bridge:18800 | WebSocket | Routes to per-user OpenClaw sandbox |
| `/auth/` | auth-service:18791 | HTTP | RBAC + pod provisioning |
| `/supabase/auth/` | supabase-auth:9999 | HTTP | GoTrue auth |
| `/keycloak/` | keycloak:8080 | HTTP | IdP broker |
| `/__openclaw__/*` | openshell-bridge:18800 | HTTP/WS | Routes to per-user OpenClaw sandbox |
| `/v1/` | openshell-bridge:18800 | HTTP | OpenAI-compatible API |
| `/tools/` | openshell-bridge:18800 | HTTP | Tool catalog |

## Secrets Management (Vault Agent Injector)

All secrets are stored in HashiCorp Vault and injected into pods via Vault Agent Injector. No `.env` files in production.

### Vault paths

| Path | Keys | Used by |
|------|------|---------|
| `secret/trinity/supabase` | jwt_secret, anon_key, postgres_password | supabase-auth, auth-service, openshell-bridge |
| `secret/trinity/keycloak` | admin_password, client_secret | keycloak, supabase-auth |
| `secret/trinity/openshell` | service_token | openshell-bridge, auth-service |
| `secret/trinity/grafana` | password | grafana |
| `secret/trinity/superadmin` | allowlist, enabled, email, password | auth-service |

### Pod annotations for Vault injection

```yaml
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "<service-name>"
vault.hashicorp.com/agent-inject-secret-config: "secret/data/trinity/<service>"
vault.hashicorp.com/agent-inject-template-config: |
  {{- with secret "secret/data/trinity/<service>" -}}
  export KEY={{ .Data.data.key }}
  {{- end -}}
```

### Seeding secrets into Vault

```bash
# Port-forward Vault
kubectl port-forward svc/vault 8200:8200 -n trinity

# Login
export VAULT_ADDR=http://127.0.0.1:8200
vault login root

# Write secrets
vault kv put secret/trinity/supabase \
  jwt_secret="$(openssl rand -hex 32)" \
  anon_key="$(openssl rand -hex 32)" \
  postgres_password="$(openssl rand -hex 16)"

vault kv put secret/trinity/keycloak \
  admin_password="$(openssl rand -hex 16)" \
  client_secret="$(openssl rand -hex 32)"

vault kv put secret/trinity/openshell \
  service_token="$(openssl rand -hex 32)"

vault kv put secret/trinity/grafana \
  password="$(openssl rand -hex 16)"
```

## Build & Deploy

### Container Registry

Images are pushed to `ghcr.io/spoonbobo/trinity/`. Auth:

```bash
echo $GHCR_TOKEN | docker login ghcr.io -u spoonbobo --password-stdin
```

`GHCR_TOKEN` is stored in `src/.env` (gitignored).

### Build all images

```bash
# Inside the minikube Docker daemon:
eval $(minikube docker-env)

# Or build and push to GHCR (for production):
REGISTRY=ghcr.io/spoonbobo/trinity

docker build -t $REGISTRY/auth-service:latest src/auth-service/
docker build -t $REGISTRY/openshell-bridge:latest src/openshell-bridge/
docker build -t $REGISTRY/frontend:latest src/frontend/
docker build -t $REGISTRY/site:latest site/

# Push
for img in auth-service openshell-bridge frontend site; do
  docker push $REGISTRY/$img:latest
done
```

### Deploy on minikube

```bash
# 1. Start minikube with sufficient resources
minikube start --memory 16384 --cpus 4 --driver=docker

# 2. Build images inside minikube
eval $(minikube docker-env)
docker build -t trinity-auth-service:latest src/auth-service/
docker build -t trinity-openshell-bridge:latest src/openshell-bridge/
docker build -t trinity-frontend:latest src/frontend/
docker build -t trinity-site:latest site/

# 3. Install Vault + Vault Agent Injector
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault -n trinity --create-namespace \
  --set "server.dev.enabled=true" \
  --set "injector.enabled=true"

# 4. Seed secrets into Vault (see "Seeding secrets" section above)

# 5. Install platform
helm install trinity k8s/charts/trinity-platform \
  -n trinity \
  -f k8s/charts/trinity-platform/values.minikube.yaml

# 6. Verify
kubectl get pods -n trinity
kubectl get svc -n trinity

# 7. Access
minikube service nginx -n trinity --url
```

### Production deploy

```bash
# 1. Set registry
helm install trinity k8s/charts/trinity-platform \
  -n trinity --create-namespace \
  -f my-values.yaml \
  --set global.imageRegistry="ghcr.io/spoonbobo/trinity/" \
  --set ingress.host="trinity.example.com" \
  --set ingress.tls.enabled=true \
  --set ingress.tls.secretName="trinity-tls"
```

### Upgrade

```bash
helm upgrade trinity k8s/charts/trinity-platform \
  -n trinity \
  -f my-values.yaml
```

## Database

Single PostgreSQL instance (`supabase-db`), multi-schema:

| Schema | Used by | Tables |
|--------|---------|--------|
| `rbac` | auth-service, openshell-bridge | roles, permissions, role_permissions, user_roles, audit_log, **tenants** |
| `auth` | GoTrue/supabase-auth | users, sessions, refresh_tokens, etc. |
| `keycloak` | Keycloak | realm config, IdP state, etc. |

Migrations: `src/supabase/migrations/001-005*.sql` (run on first DB start)

## Per-User Pod Lifecycle

1. User logs in via Flutter shell (email/password or Keycloak SSO)
2. Frontend calls `POST /auth/session` with JWT
3. Auth-service provisions an OpenShell sandbox for the user
4. OpenShell Gateway creates the sandbox with isolated state and workspace
5. Frontend polls `GET /auth/gateway-status` until sandbox is ready
6. Frontend connects WebSocket to `/ws` with JWT
7. OpenShell Bridge routes traffic to the user's sandbox
8. User now has a fully isolated OpenClaw instance

## Troubleshooting

**Pod not starting:**
```bash
kubectl describe pod -l trinity.work/user-id=<userId> -n trinity
kubectl logs -l trinity.work/user-id=<userId> -n trinity --tail=30
```

**Bridge routing issues:**
```bash
kubectl logs deploy/openshell-bridge -n trinity --tail=30
```

**Gateway unhealthy (per-user pod):**
```bash
kubectl exec -it <pod-name> -n trinity -- openclaw doctor --fix
```

**DB schema issues:**
```bash
kubectl exec -it sts/supabase-db -n trinity -- psql -U postgres -d supabase -c "\dt rbac.*"
```

**Check all services:**
```bash
kubectl get pods -n trinity -o wide
kubectl get svc -n trinity
helm status trinity -n trinity
```

**View per-user pods:**
```bash
kubectl get pods -n trinity -l app.kubernetes.io/name=openclaw-instance
```

**Delete a user's pod (force reprovision):**
```bash
kubectl delete deploy openclaw-<userId-prefix> -n trinity
```
