---
description: Copy skills from host to OpenClaw container
---

Sync all skills from the host `web/skills/` directory into the running OpenClaw container.

Step 1 - Copy all skills:

!`docker cp web/skills/. trinity-openclaw:/home/node/.openclaw/skills/`

Step 2 - Verify skills are visible:

!`docker exec trinity-openclaw openclaw skills list --json`

Step 3 - Restart gateway to pick up changes:

!`docker restart trinity-openclaw`

Report how many skills were synced and their status.
