---
name: openclaw-gateway
description: Operate the OpenClaw Gateway that powers Trinity AGI — configure providers, manage sessions, use the CLI, and understand the WebSocket protocol.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity-agi
---

## What This Skill Covers

OpenClaw Gateway is the backend engine for Trinity AGI. It provides the agent runtime, multi-provider LLM, tool execution, sessions, memory, governance, and multi-channel messaging. All agent logic flows through OpenClaw — never call LLM APIs directly.

Documentation index: https://docs.openclaw.ai/llms.txt
Use that file to discover all available doc pages before exploring further.

## Running Stack (Docker)

The Trinity stack runs via Docker Compose from `web/docker-compose.yml`:

```
docker compose -f web/docker-compose.yml up -d          # start
docker compose -f web/docker-compose.yml down            # stop
docker compose -f web/docker-compose.yml logs -f         # follow logs
docker restart trinity-openclaw                          # restart gateway only
```

Services:
- `trinity-openclaw` — OpenClaw Gateway on port 18789
- `trinity-nginx` — serves Flutter shell on port 80, proxies WS/API to gateway

## CLI Inside the Container

Run OpenClaw CLI commands via `docker exec`:

```
docker exec trinity-openclaw openclaw <command>
```

Essential commands:

```
docker exec trinity-openclaw openclaw status              # gateway status
docker exec trinity-openclaw openclaw health --token $TOK # health check
docker exec trinity-openclaw openclaw dashboard --no-open # get dashboard URL with token
docker exec trinity-openclaw openclaw doctor              # diagnose config issues
docker exec trinity-openclaw openclaw doctor --fix        # auto-fix config issues
docker exec trinity-openclaw openclaw models              # list available models
docker exec -it trinity-openclaw bash         # interactive config - openclow configure
docker exec trinity-openclaw openclaw sessions              # list sessions (NO subcommand)
docker exec trinity-openclaw openclaw sessions --json       # list sessions as JSON
docker exec trinity-openclaw openclaw sessions --all-agents # list all agents' sessions
docker exec trinity-openclaw openclaw logs --tail 50      # recent logs
docker exec -it trinity-openclaw openclaw channels login # login
```

The gateway token is stored in `web/.env` as `OPENCLAW_GATEWAY_TOKEN`.

## openclaw-exec Tool (OpenCode MCP)

OpenCode provides a built-in `openclaw-exec` tool that runs CLI commands inside the `trinity-openclaw` Docker container. Use it instead of `docker exec` when working in OpenCode.

**Syntax:** The tool takes a single `command` string -- this is the CLI command WITHOUT the `openclaw` prefix. The tool automatically runs `docker exec trinity-openclaw openclaw <command>`.

```
openclaw-exec("status")              # runs: openclaw status
openclaw-exec("models")              # runs: openclaw models
openclaw-exec("sessions")            # runs: openclaw sessions
openclaw-exec("sessions --json")     # runs: openclaw sessions --json
openclaw-exec("doctor --fix")        # runs: openclaw doctor --fix
openclaw-exec("logs --tail 50")      # runs: openclaw logs --tail 50
```

**Common mistakes that cause ShellError (exit code 1):**

| Wrong | Right | Why |
|-------|-------|-----|
| `sessions list` | `sessions` | `sessions` has no `list` subcommand; it IS the list command |
| `sessions inspect <key>` | `sessions --json` | No `inspect` subcommand; use `--json` for details |
| `models default <m>` | `models set <m>` | No `default` subcommand |
| `models --list` | `models list` | Flag syntax wrong; `list` is a subcommand |

**Commands that require TTY (`-it` flag) will fail** in `openclaw-exec` because it runs non-interactively:
- `configure` (interactive prompts)
- `channels login` (QR code display)
- `models auth login` (device flow)

For these, use `docker exec -it trinity-openclaw openclaw <command>` via the Bash tool instead.

## Models CLI Reference

The `models` command has several subcommands. Use these exact forms — **there are no shorthand aliases** (e.g. `models default` does not exist; use `models set`).

```
openclaw models                          # show configured model status (alias for `models status`)
openclaw models status                   # same — show default, fallbacks, aliases, auth overview
openclaw models status --json            # JSON output
openclaw models status --probe           # live-probe configured provider auth
openclaw models list                     # list configured models only
openclaw models list --all               # list full model catalog (all providers)
openclaw models list --provider <name>   # filter by provider (e.g. opencode, venice, openrouter)
openclaw models list --local             # filter to local models only
openclaw models list --json              # JSON output
openclaw models set <model>              # set the default model (by id or alias)
openclaw models set-image <model>        # set the image model
openclaw models fallbacks list           # list fallback models
openclaw models fallbacks add <model>    # add a fallback model
openclaw models fallbacks remove <model> # remove a fallback model
openclaw models fallbacks clear          # clear all fallback models
openclaw models aliases list             # list model aliases
openclaw models aliases add              # add or update a model alias
openclaw models aliases remove           # remove a model alias
openclaw models auth add                 # interactive auth helper
openclaw models auth login               # run provider plugin auth flow
openclaw models auth paste-token         # paste a token into auth-profiles.json
openclaw models auth setup-token         # run provider CLI to create/sync token (TTY)
openclaw models auth login-github-copilot # GitHub Copilot device flow (TTY)
openclaw models scan                     # scan OpenRouter free models for tools + images
openclaw models scan --set-default       # scan and set first selection as default
openclaw models scan --set-image         # scan and set first image selection
```

**Common mistakes to avoid:**
- `models default <model>` — does not exist. Use `models set <model>`.
- `models set-default <model>` — does not exist. Use `models set <model>`.
- `models --list` — does not exist. Use `models list`.
- `models list --all` is required to see models beyond the currently configured ones.

## Configuration

Config lives at `web/openclaw.json` (mounted read-only into the container at `~/.openclaw/openclaw.json`).

Format is JSON5 (comments + trailing commas allowed). All fields are optional — OpenClaw uses safe defaults when omitted.

The live config is inside the Docker volume at `/home/node/.openclaw/openclaw.json`. The `command` in `docker-compose.yml` passes `--bind lan` so the gateway listens on all container interfaces (required for Docker port mapping).

**Important notes from setup:**

- The config file is NOT bind-mounted (atomic rename fails on Windows Docker bind mounts). It lives in the `openclaw-data` volume. To sync it back to the host: `docker cp trinity-openclaw:/home/node/.openclaw/openclaw.json web/openclaw.json`
- `agents.defaults.sandbox.mode` must be `"off"` (not `"non-main"`) because Docker CLI is not available inside the gateway container. Setting it to `"non-main"` causes `spawn docker ENOENT` errors when handling WhatsApp or non-main sessions.
- The onboarding wizard (`openclaw onboard`) may overwrite `gateway.bind` back to `"loopback"` and inject its own token into the config. Always verify after running the wizard.
- The Flutter frontend needs the gateway token at build time via `--dart-define=GATEWAY_TOKEN=...`. The docker-compose passes `OPENCLAW_GATEWAY_TOKEN` from `.env` as a build arg.

### Key Config Sections

**LLM providers** — configured via the dashboard at `http://localhost:18789` or via:
```
docker exec trinity-openclaw openclaw configure --section providers
```
Docs: https://docs.openclaw.ai/providers/index.md

**Tools** — `tools.profile` controls the base allowlist (`minimal`, `coding`, `messaging`, `full`). Individual tools toggled via `tools.allow` / `tools.deny`. Tool groups: `group:runtime`, `group:fs`, `group:sessions`, `group:memory`, `group:web`, `group:ui`, `group:automation`, `group:messaging`, `group:nodes`.

**Web tools** — `web_search` requires a Brave API key. Configure via:
```
docker exec trinity-openclaw openclaw configure --section web
```

**Sandbox** — `agents.defaults.sandbox.mode: "non-main"` means non-main sessions run tools in Docker isolation. Scope `"agent"` = one sandbox container per agent.

**Channels** (WhatsApp, Telegram, Discord, etc.):
```
docker exec -it trinity-openclaw openclaw channels login        # WhatsApp QR
docker exec trinity-openclaw openclaw channels add --channel telegram --token "BOT_TOKEN"
docker exec trinity-openclaw openclaw channels add --channel discord --token "BOT_TOKEN"
```
Docs: https://docs.openclaw.ai/channels/index.md

Full config reference: https://docs.openclaw.ai/gateway/configuration-reference.md

## WebSocket Protocol

The Flutter shell and all clients connect to the gateway via WebSocket. Protocol version 3.

### Frame Types

- **Request**: `{type:"req", id, method, params}`
- **Response**: `{type:"res", id, ok, payload|error}`
- **Event**: `{type:"event", event, payload, seq?, stateVersion?}`

### Handshake Flow

1. Gateway sends `connect.challenge` event with a nonce
2. Client sends `connect` request with auth token, client info, device identity
3. Gateway responds with `hello-ok` including protocol version and policy

### Roles

- `operator` — control plane client (CLI, web UI, Flutter shell). Scopes: `operator.read`, `operator.write`, `operator.admin`, `operator.approvals`.
- `node` — capability host (camera, screen, canvas). Declares `caps`, `commands`, `permissions`.

### Key Methods

- `chat.send` — send user message (requires session key + idempotency key)
- `chat.history` — fetch chat history
- `chat.abort` — cancel in-progress agent run
- `exec.approval.resolve` — resolve exec approval requests
- `tools.catalog` — fetch available tools for an agent

### Key Events

- `chat` — chat messages and streaming updates
- `agent` — agent thinking, tool calls, tool results
- `exec.approval.requested` — approval gate triggered
- `canvas` / `a2ui` — UI surface updates from the agent

Full protocol docs: https://docs.openclaw.ai/gateway/protocol.md

## Available Tools

The gateway exposes these tools to the agent (with `tools.profile: "full"`):

| Tool | Purpose |
|------|---------|
| `exec` | Run shell commands in workspace |
| `process` | Manage background exec sessions |
| `read` / `write` / `edit` / `apply_patch` | File operations |
| `web_search` | Brave Search API (needs API key) |
| `web_fetch` | Fetch URL content as markdown |
| `browser` | Control OpenClaw-managed browser |
| `canvas` | Drive node Canvas / A2UI surfaces |
| `nodes` | Discover and target paired nodes |
| `image` | Analyze images with image model |
| `message` | Send across Discord/Telegram/WhatsApp/Slack/etc. |
| `cron` | Manage scheduled jobs and wakeups |
| `gateway` | Restart or apply config updates |
| `sessions_*` | List, inspect, send to, spawn sessions |
| `lobster` | Typed workflow runtime with approval gates |
| `memory_search` / `memory_get` | Agent memory |

Full tools docs: https://docs.openclaw.ai/tools/index.md

## Governance

Every agent action that modifies system state passes through OpenClaw's governance layer:

- **Exec approvals** — `ask` policy requires user consent. Never bypass. Never auto-approve.
- **Lobster workflows** — `approval: required` steps halt until user approves/rejects.
- **Sandbox isolation** — on by default for non-main sessions.
- **Loop detection** — enabled. Blocks repetitive no-progress tool-call loops.

## Troubleshooting

**Gateway won't start:**
```
docker logs trinity-openclaw --tail 30
docker exec trinity-openclaw openclaw doctor --fix
```

**Config validation errors:** check `web/openclaw.json` syntax. The config is JSON5 but must pass OpenClaw's schema validation.

**"unauthorized" / "token mismatch":** the dashboard needs the gateway token. Get the authenticated URL:
```
docker exec trinity-openclaw openclaw dashboard --no-open
```

**Rebuild frontend after Dart source changes:**

CRITICAL: `run --rm frontend-builder` alone does NOT rebuild the image — it reuses the cached one. You MUST `build` first:

```bash
# 1. Rebuild image (--no-cache busts Docker layer cache — REQUIRED for source changes)
docker compose -f web/docker-compose.yml --profile build build --no-cache frontend-builder

# 2. Run builder to copy output to volume
docker compose -f web/docker-compose.yml --profile build run --rm frontend-builder

# 3. Restart nginx to serve new build
docker restart trinity-nginx

# 4. Tell user to hard-refresh (Ctrl+Shift+R)
```

**Deploy extension or AGENTS.md changes (no rebuild needed):**

```bash
docker cp web/extensions/canvas-bridge/index.ts trinity-openclaw:/home/node/.openclaw/extensions/canvas-bridge/index.ts
docker cp web/AGENTS.md trinity-openclaw:/home/node/.openclaw/workspace/AGENTS.md
docker restart trinity-openclaw
```

Note: AGENTS.md changes only take effect on new sessions. Clear the webchat session to force a fresh system prompt.

**Update OpenClaw to latest:**
```
docker compose -f web/docker-compose.yml build --no-cache openclaw-gateway
docker compose -f web/docker-compose.yml up -d
```
