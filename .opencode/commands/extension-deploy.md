---
description: Deploy canvas-bridge extension + AGENTS.md to gateway
---

Deploy the canvas-bridge extension and AGENTS.md to the running OpenClaw container without rebuilding.

Step 1 - Copy canvas-bridge extension:

!`docker cp web/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts`

Step 2 - Copy AGENTS.md:

!`docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md`

Step 3 - Restart gateway to reload:

!`docker restart trinity-openclaw`

Note: AGENTS.md changes only take effect on new sessions. Clear the webchat session to force a fresh system prompt.
