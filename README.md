# Trinity

## What this repo contains

- Trinity application code (Flutter frontend, OpenClaw gateway, auth service, proxy services)
- Docker Compose stack for local development
- Minikube + Helm setup for Kubernetes deployment
- Kubernetes charts and per-user multi-tenant architecture

## Prerequisites

- Docker Desktop with Compose v2
- An LLM provider API key (OpenRouter, Anthropic, OpenAI, etc.)
- For Kubernetes deploy: `minikube`, `kubectl`, and `helm`

## Deploy with Docker Compose

### 1. Configure environment

```bash
cp app/.env.example app/.env
```

Edit `app/.env` and set **at minimum** these secrets (generate each with `openssl rand -hex 32`):

| Variable | Required | Notes |
|----------|----------|-------|
| `OPENCLAW_GATEWAY_TOKEN` | yes | Gateway auth token (>= 16 chars) |
| `SUPABASE_JWT_SECRET` | yes | JWT signing secret (>= 32 chars, must differ from gateway token) |
| `SUPABASE_ANON_KEY` | yes | GoTrue anonymous key |
| `SUPABASE_POSTGRES_PASSWORD` | yes | Database password (>= 16 chars) |
| `KEYCLOAK_ADMIN_PASSWORD` | yes | Keycloak admin console password |
| `KEYCLOAK_CLIENT_SECRET` | yes | OIDC client secret |
| `GRAFANA_PASSWORD` | yes | Grafana dashboard password |
| `VAULT_TOKEN` | yes | Vault dev-mode root token |
| `BRAVE_API_KEY` | no | Enables `web_search` tool |

See `app/.env.example` for the full list including optional integrations (LightRAG, Copilot, YouTube, Polymarket, etc.).

### 2. Build the frontend

```bash
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
```

This compiles the Flutter web app and copies the static files into a shared Docker volume.

### 3. Start the stack

```bash
docker compose -f app/docker-compose.yml up -d
```

### 4. Open the app

- Trinity UI: [http://localhost](http://localhost)
- OpenClaw dashboard: [http://localhost:18789](http://localhost:18789)

Add your LLM provider API keys in the OpenClaw dashboard.

### Services

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| nginx | trinity-nginx | 80 | Reverse proxy + SPA host |
| openclaw-gateway | trinity-openclaw | 18789 | AI gateway (chat, tools, agents) |
| auth-service | trinity-auth-service | 18791 | RBAC + JWT resolution |
| terminal-proxy | trinity-terminal-proxy | 18790 | WebSocket bridge for CLI |
| supabase-db | trinity-supabase-db | 5432 | PostgreSQL |
| supabase-auth | trinity-supabase-auth | 9999 | GoTrue auth |
| keycloak | trinity-keycloak | 8080 | IdP broker (LDAP/AD/OIDC) |
| vault | trinity-vault | 8200 | Secret management |
| copilot | trinity-copilot | - | OpenCode copilot service |
| lightrag | trinity-lightrag | - | Knowledge graph RAG sidecar |
| grafana | trinity-grafana | 3000 | Monitoring dashboards |
| loki | trinity-loki | 3100 | Log aggregation |
| fluentd | trinity-fluentd | 24224 | Log collection |

### Rebuild after code changes

```bash
# Frontend (Dart/Flutter)
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
docker compose -f app/docker-compose.yml restart nginx

# Backend services (JS/TS)
docker compose -f app/docker-compose.yml build --no-cache auth-service terminal-proxy
docker compose -f app/docker-compose.yml up -d auth-service terminal-proxy

# AGENTS.md or extension changes (no rebuild needed)
docker cp app/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md
docker restart trinity-openclaw
```

## Deploy with Minikube

This Kubernetes path deploys the full multi-tenant platform on your machine.

### One-command setup

```bash
./k8s/minikube-setup.sh all
```

This script:
- installs required tools (`minikube`, `kubectl`, `helm`) if missing
- starts Docker Desktop if needed
- starts Minikube with ingress addon
- builds and loads all container images into Minikube
- deploys the Helm chart into the `trinity` namespace
- runs database migrations and Vault secret seeding
- bootstraps the default superadmin account

### Available commands

```bash
./k8s/minikube-setup.sh install-tools   # install minikube/kubectl/helm
./k8s/minikube-setup.sh start           # start minikube cluster
./k8s/minikube-setup.sh build           # build images inside minikube
./k8s/minikube-setup.sh deploy          # helm install + migrations + bootstrap
./k8s/minikube-setup.sh status          # show pod status
./k8s/minikube-setup.sh teardown        # uninstall and delete namespace
./k8s/minikube-setup.sh all             # full setup (all of the above)
```

### Access the cluster app

Run this in a separate terminal and keep it running:

```bash
minikube tunnel
```

Then open:

| URL | Service |
|-----|---------|
| [http://localhost](http://localhost) | Trinity UI (Flutter shell) |
| [http://site.localhost](http://site.localhost) | Marketing site (Next.js) |
| [http://localhost/keycloak](http://localhost/keycloak) | Keycloak admin console |
| [http://vault.localhost/ui/](http://vault.localhost/ui/) | Vault UI |
| [http://grafana.localhost](http://grafana.localhost) | Grafana dashboards |
| [http://loki.localhost/ready](http://loki.localhost/ready) | Loki readiness check |
| [http://lightrag.localhost](http://lightrag.localhost) | LightRAG API |

Default bootstrap credentials:
- Trinity admin: `admin@trinity.work` / `admin123`
- Keycloak admin: `admin` / `trinity-kc-admin-123`

### Manual frontend rebuild (Minikube)

After changing Flutter source code:

```bash
eval $(minikube docker-env)
docker build --no-cache -t trinity-frontend:latest app/frontend/
kubectl rollout restart deployment/nginx -n trinity
```

## License

See `LICENSE` if present, or contact the maintainers.
