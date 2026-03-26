# Trinity + NVIDIA OpenShell Integration

This directory contains the integration layer between Trinity AGI and
[NVIDIA OpenShell](https://github.com/NVIDIA/OpenShell) — a safe, private
runtime for autonomous AI agents.

## Architecture

OpenShell replaces Trinity's custom per-user pod orchestration with sandboxed
execution environments that provide Landlock filesystem isolation, seccomp
process restrictions, policy-enforced network egress, and credential isolation.

### Components replaced by OpenShell

| Old component | OpenShell replacement |
|---|---|
| gateway-orchestrator (Go) | OpenShell Gateway — sandbox lifecycle management |
| gateway-proxy (Go) | openshell-bridge — WebSocket/HTTP routing to sandboxes |
| terminal-proxy (Node.js) | OpenShell sandbox connect — SSH tunneling |
| openclaw-gateway (per-user pod) | OpenShell sandbox (`--from trinity-openclaw`) |
| openclaw-instance Helm chart | OpenShell sandbox lifecycle + policy |

### Components kept

auth-service, supabase-db, supabase-auth, keycloak, Flutter frontend, nginx,
vault, grafana/loki/fluentd. These have no OpenShell equivalent.

## Directory Structure

```
openshell/
  sandboxes/
    trinity-openclaw/          Custom sandbox image
      Dockerfile               Extends community openclaw sandbox
      bootstrap-trinity.sh     Seeds extensions, skills, config
      policy.yaml              OpenShell sandbox policy
      build.sh                 Build script
  README.md                    This file
src/
  openshell-bridge/            WebSocket-to-sandbox bridge service
    main.go                    HTTP/WebSocket proxy + orchestrator compat API
    adapter/
      orchestrator-compat.go   Drop-in API replacement for gateway-orchestrator
    Dockerfile
  nginx/
    nginx.openshell.conf       Nginx config routing through openshell-bridge
  docker-compose.openshell.yml Override to switch from legacy to OpenShell mode
```

## Quick Start

### 1. Install OpenShell

```bash
curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | sh
```

### 2. Start the OpenShell gateway

```bash
openshell gateway start --name trinity-openshell
```

### 3. Build the Trinity sandbox image

```bash
./openshell/sandboxes/trinity-openclaw/build.sh
```

### 4. Run Trinity in OpenShell mode

```bash
cd src
docker compose -f docker-compose.yml -f docker-compose.openshell.yml up -d
```

### 5. Create a user sandbox

```bash
openshell sandbox create \
  --name openclaw-<user-id> \
  --from trinity-openclaw-sandbox:latest \
  --forward 18789
```

## Migration Path

**Phase 1 (current):** Both modes coexist. The original docker-compose.yml
runs the legacy orchestrator. The openshell override disables replaced services
and adds the bridge.

**Phase 2:** Once validated, remove gateway-orchestrator, gateway-proxy,
terminal-proxy from docker-compose.yml and the Helm chart.

**Phase 3:** Define per-user sandbox policies and migrate credential management
to OpenShell Providers.
