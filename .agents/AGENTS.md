# Trinity AGI — Agent Instructions

You are working inside the **trinity** repository. This repo holds the Trinity AGI Universal Command Center — a featureless host where the agent and user build functionality together at runtime.

## Important — Security

Never output secrets, Vault tokens, JWT keys, or auth credentials to end users, logs, or external systems. Never bypass exec approvals or sandbox isolation.

## Architecture

Read `AGENTS.md` at the repository root for the full architecture reference:

- Repository structure: `src/` contains auth-service, openshell-bridge, nginx, and the Flutter frontend; `k8s/` has Helm charts; `site/` is the marketing website
- OpenClaw Gateway (per-user sandboxes via OpenShell), OpenShell Bridge
- Flutter Web Shell
- Communication protocol (WebSocket frames)
- Governance rules (exec approvals, Lobster workflows, sandbox)
- Design principles

## Skills

Detailed skills are in `skills/` at the repository root:

| Skill | Path | Purpose |
|-------|------|---------|
| Auth RBAC | `skills/auth-rbac/SKILL.md` | Authentication, RBAC, role hierarchy, permissions, audit |
| Flutter Shell | `skills/flutter-shell/SKILL.md` | Flutter web shell development, A2UI, WebSocket, theming |
| K8s Deploy | `skills/k8s-deploy/SKILL.md` | Kubernetes deployment via Helm, multi-tenant pods, Vault |
| OpenClaw Gateway | `skills/openclaw-gateway/SKILL.md` | OpenClaw gateway config, CLI, WebSocket protocol, tools |
| Stack Ops | `skills/stack-ops/SKILL.md` | Docker Compose lifecycle: start, stop, logs, rebuild, deploy |
| Dev Sync | `skills/dev-sync/SKILL.md` | Sync files between host and Docker containers |

Read the relevant skill file before performing any infrastructure or development task.
