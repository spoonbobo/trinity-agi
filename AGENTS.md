# Trinity AGI — Agent Guidelines

## What Is This

Trinity AGI is a "featureless" Universal Command Center. It is a host, not an application. The UI is intentionally blank — the agent and user build functionality together at runtime. Do not add static features, predefined dashboards, or hardcoded navigation. Everything the user sees should be generated dynamically by the agent.

## Repository Structure

- **`src/`** — The command center application (Flutter frontend, openshell-bridge, auth-service, nginx, Dockerfiles).
- **`k8s/`** — Helm charts for Kubernetes deployment (`trinity-platform` shared services + `openclaw-instance` per-user pods).
- **`site/`** — The public marketing website (Next.js, Tailwind CSS, dark theme).

## Architecture

Trinity AGI is deployed on Kubernetes. Each user gets an isolated OpenClaw sandbox managed by OpenShell Gateway.

- **OpenClaw Gateway** (per-user) is the AI backend. Each user gets their own sandbox with isolated state, sessions, and workspace. Do not build a separate backend. Do not call LLM APIs directly. All agent logic flows through OpenClaw.
- **OpenShell Bridge** (Go) routes WebSocket/HTTP traffic to per-user OpenClaw sandboxes via OpenShell Gateway. Handles JWT authentication, session routing, and terminal access.
- **Flutter Web Shell** is the frontend. It connects via WebSocket through the openshell-bridge. Auth is JWT-based (no compile-time gateway token).
- **nginx** serves the built Flutter app and reverse-proxies all routes through the openshell-bridge.
- **Vault** (with Agent Injector) manages all secrets. No `.env` files in production.

## Deployment

Infrastructure is managed via Helm on Kubernetes. See the `k8s-deploy` skill for full deployment instructions.

- **Minikube**: use `values.minikube.yaml`
- **Other clusters**: any K8s cluster with `values.yaml` plus your own override file
- **Images**: pushed to `ghcr.io/spoonbobo/trinity/`
- **Docker Compose** (`src/docker-compose.yml`): legacy single-tenant mode, deprecated.

## Communication Protocol

The Flutter shell talks to OpenClaw via WebSocket:

1. Gateway sends a challenge, shell responds with operator credentials
2. Messages sent via `chat.send` with session and idempotency keys
3. Streaming responses arrive as `chat` and `agent` events
4. Exec approvals arrive as events, resolved by the user

All frames follow: requests `{type:"req"}`, responses `{type:"res"}`, events `{type:"event"}`.

## Governance Rules

Every agent action that modifies system state must pass through OpenClaw's governance layer:

- **Exec approvals** require user consent when configured with `ask` policy. Never bypass. Never auto-approve.
- **Lobster workflows** with `approval: required` steps halt until the user explicitly approves or rejects.
- **Sandbox isolation** is on by default for non-main sessions. Do not disable it.
- **Loop detection** is enabled. Do not disable it.

## Design Principles

- **The shell stays minimal by default.** Keep permanent chrome extremely light (status indicator + small text toggles, chat, canvas, prompt).
- **The agent builds the UI.** Interactive content is pushed via A2UI/Canvas surfaces at runtime.
- **Voice and text are equal.** Both feed into `chat.send`. Transcription happens on-device.
- **Multi-channel is native.** Users may interact via WhatsApp, Telegram, Discord, etc. The Flutter shell is the command center for complex tasks, not the only interface.
- **Plain, immersive terminal aesthetic.** Keep visuals flat and quiet (minimal borders, no decorative cards by default), with theme-aware colors and the app monospace font (`monofur`).

## Do Not

- Do not add traditional navigation bars, sidebars, or feature menus
- Do not call LLM provider APIs directly — use OpenClaw Gateway
- Do not store secrets in code — use Vault (K8s) or `.env` for single-machine development
- Do not disable sandbox mode or exec approvals
- Do not add heavy UI frameworks or component libraries — keep the shell minimal
- Do not commit `.env`
- Do not commit provider keys, auth profiles, or generated OpenClaw state files
