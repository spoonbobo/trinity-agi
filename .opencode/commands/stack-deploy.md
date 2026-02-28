---
description: Full deploy -- rebuild frontend + backend services + restart everything
---

Full deploy of all Trinity AGI services after source changes.

Step 1 - Rebuild frontend image (--no-cache):

!`docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder`

Step 2 - Copy frontend build to volume:

!`docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder`

Step 3 - Rebuild backend services (--no-cache):

!`docker compose -f web/docker-compose.yml build --no-cache terminal-proxy auth-service`

Step 4 - Restart backend services:

!`docker compose -f web/docker-compose.yml up -d terminal-proxy auth-service`

Step 5 - Restart nginx:

!`docker restart trinity-nginx`

Step 6 - Update AGENTS.md in gateway container:

!`docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md`

Step 7 - Check service health:

!`docker compose -f web/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}"`

Report results. Remind user to Ctrl+Shift+R.
