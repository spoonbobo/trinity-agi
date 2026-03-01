---
description: Sync live gateway config + agent files from container to host
---

Sync configuration and agent files from the running OpenClaw container back to the host.

Step 1 - Sync openclaw.json:

!`docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json web/openclaw.json`

Step 2 - Sync agent models.json:

!`docker cp trinity-openclaw:/home/node/.openclaw/agents/main/models.json web/agents/main/models.json`

Step 3 - Sync AGENTS.md from workspace:

!`docker cp trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md web/AGENTS.md`

Step 4 - Show what changed:

!`git diff --stat web/openclaw.json web/agents/main/models.json web/AGENTS.md`

Report what was synced and any notable changes. Do NOT sync auth-profiles.json (contains secrets).
