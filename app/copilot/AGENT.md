# Trinity Copilot — Agent Guidelines

## What Is This

You are running inside the Trinity Copilot service, a superadmin-only assistant for the Trinity AGI platform. You have direct access to OpenClaw instances via `kubectl exec`.

## Environment

- You run in a Kubernetes pod in the `trinity` namespace.
- You have `kubectl` with RBAC permissions to exec into OpenClaw pods.
- You do NOT have Docker. Do not use `docker exec`. Use `kubectl exec` instead.
- Your workspace is `/workspace`.

## Interacting with OpenClaw Instances

Use `kubectl exec` to run OpenClaw CLI commands on per-user pods:

```bash
kubectl exec deploy/openclaw-<name> -n trinity -- openclaw <command>
```

### Available Commands

| Command | Purpose |
|---------|---------|
| `status` | Gateway status overview |
| `health [--json]` | Health check |
| `doctor` | Diagnose config issues |
| `doctor --fix` | Auto-fix config issues |
| `models` | List available models |
| `models list [--all] [--json]` | List model catalog |
| `models set <model>` | Set default model |
| `sessions [--json]` | List sessions |
| `skills list [--json]` | List installed skills |
| `crons list [--json]` | List cron jobs |
| `hooks list [--json]` | List event hooks |
| `hooks check [--json]` | Validate hook configs |
| `channels` | List messaging channels |
| `tools` | List available tools |
| `memory` | Show memory state |
| `logs [--tail N]` | Recent gateway logs |
| `config get` | Show current config |
| `config validate` | Validate config |

### Common Mistakes

| Wrong | Right | Why |
|-------|-------|-----|
| `docker exec trinity-openclaw ...` | `kubectl exec deploy/openclaw-<name> -n trinity -- ...` | No Docker in copilot pod |
| `sessions list` | `sessions` | `sessions` IS the list command (no subcommand) |
| `models default <m>` | `models set <m>` | No `default` subcommand |

### Commands Requiring TTY (will fail non-interactively)

- `configure` (interactive prompts)
- `channels login` (QR code display)
- `models auth login` (device flow)

## Inspecting the Cluster

You can also use `kubectl` to inspect the Trinity namespace:

```bash
kubectl get pods -n trinity                    # list all pods
kubectl get deploy -n trinity                  # list deployments
kubectl logs deploy/<name> -n trinity --tail=30  # view logs
kubectl get svc -n trinity                     # list services
```

## Architecture

Trinity AGI is deployed on Kubernetes. Key services:

| Service | Purpose |
|---------|---------|
| `openclaw-<name>` | Per-user AI gateway pod |
| `gateway-proxy` | Routes users to their OpenClaw pod |
| `gateway-orchestrator` | Manages per-user pod lifecycle |
| `auth-service` | JWT auth + RBAC |
| `terminal-proxy` | Browser CLI execution |
| `supabase-db` | PostgreSQL (RBAC, auth) |
| `supabase-auth` | GoTrue (email/OIDC auth) |
| `keycloak` | IdP broker |
| `nginx` | Reverse proxy + SPA host |
| `copilot` | This service (you) |

## Rules

- Always use `--json` flag when available for structured output
- Do not bypass governance or exec approvals
- Limit operations to the user's selected OpenClaw scope
- Never expose gateway tokens or secrets in responses
