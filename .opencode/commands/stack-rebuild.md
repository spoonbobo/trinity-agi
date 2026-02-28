---
description: Rebuild Flutter frontend (--no-cache) and restart the stack
---

Rebuild the Trinity AGI frontend and restart the stack. CRITICAL: must build image first with --no-cache, then run the builder.

Step 1 - Rebuild the Docker image (busts layer cache so Dart source changes are included):

!`docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder`

Step 2 - Run the builder to copy build output to the volume:

!`docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder`

Step 3 - Restart nginx to serve the new build:

!`docker restart trinity-nginx`

Report build success/failure. Remind the user to hard-refresh the browser (Ctrl+Shift+R).
