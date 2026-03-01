# Trinity Workspace Memory

Use this file for long-lived operator notes and project context that should survive across sessions.
The agent appends to this file -- do not delete sections, only add or update.

## Deployment

- **Platform**: Docker Compose on Windows (14 services)
- **Gateway**: OpenClaw at port 18789 (via nginx reverse proxy on port 80)
- **Frontend**: Flutter Web shell (SPA served by nginx)
- **Auth**: Supabase GoTrue + Keycloak SSO + custom RBAC (4 roles, 22 permissions)
- **Primary model**: venice/kimi-k2-5 (via Venice AI, free inference)
- **Channels**: WhatsApp (Baileys Web)

## Current priorities

- (none yet -- the agent will populate this)

## Decisions and rationale

- Sandbox mode is OFF because Docker CLI is unavailable inside the gateway container
- All models route through Venice AI for zero-cost privacy-preserving inference

## Environment caveats

- Windows host: use PowerShell-compatible commands in crons/hooks
- Gateway token passed at Flutter build time via --dart-define
- AGENTS.md changes require new sessions to take effect (existing sessions cache the system prompt)

## Follow-up checklist

- [ ] Configure Brave API key for web_search
- [ ] Set an image model for vision tasks
- [ ] Review dangerous gateway flags for production hardening

## Daily Log

(Agent will append dated summaries here)
