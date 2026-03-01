---
description: Restart OpenClaw Gateway only (preserves sessions)
---

Restart just the OpenClaw Gateway container. This reloads extensions, AGENTS.md, and config without affecting other services.

!`docker restart trinity-openclaw`

Wait for healthy:

!`powershell -Command "1..10 | ForEach-Object { Start-Sleep -Seconds 3; $s = docker inspect --format='{{.State.Health.Status}}' trinity-openclaw 2>$null; Write-Host \"Status: $s\"; if ($s -eq 'healthy') { break } }"`

Report the gateway status.
