# Trinity Workspace Memory

Use this file for long-lived operator notes and project context that should survive across sessions.
The agent appends to this file -- do not delete sections, only add or update.

## Deployment

- **Platform**: Docker Compose on Windows (WSL2, 14 services)
- **Gateway**: OpenClaw 2026.2.26 at port 18789 (via nginx reverse proxy on port 80)
- **Frontend**: Flutter Web shell (SPA served by nginx, Riverpod state management)
- **Auth**: Supabase GoTrue + Keycloak SSO + custom RBAC (4 roles: guest/user/admin/superadmin, 22 permissions)
- **Database**: PostgreSQL via Supabase (RBAC schema with recursive permission CTE)
- **Monitoring**: Grafana + Loki + Fluentd log pipeline
- **Secrets**: HashiCorp Vault (dev mode)

## Models

- **Primary**: `opencode/kimi-k2.5` (200k context)
- **Fallbacks**: `opencode/claude-opus-4-6`
- **Image model**: `opencode/kimi-k2.5`
- **Aliases**: MiniMax M2.5 -> `opencode/minimax-m2.5`, Claude Opus 4.6 -> `opencode/claude-opus-4-6`
- **Providers**: OpenCode (profiles auth), Venice AI (API key auth)

## Channels

- **WhatsApp**: ON, linked (+85297928130), Baileys Web, DM policy: allowlist, self-chat enabled
- **DM scope**: `per-channel-peer` (sessions isolated per channel + sender)

## Memory System

- **Backend**: memory-core (default plugin)
- **Search**: NOT functional -- OpenClaw requires an embedding provider to index files, even for FTS. No embedding API key configured.
- **Workaround**: Agent reads/writes MEMORY.md and memory/*.md via file tools (read/write/edit). Flutter Memory dialog reads via `cat` through terminal proxy.
- **Files**: `MEMORY.md` (curated long-term), `memory/YYYY-MM-DD.md` (daily logs)
- **Index store**: `~/.openclaw/memory/main.sqlite`
- **To enable**: Add an embedding provider (OpenAI, Gemini, Voyage, or Mistral API key) to `openclaw.json` under `agents.defaults.memorySearch`

## Architecture Decisions

- **Sandbox mode OFF**: Docker CLI unavailable inside the gateway container; `"non-main"` causes `spawn docker ENOENT` errors
- **Dangerous gateway flags**: `dangerouslyDisableDeviceAuth` and `dangerouslyAllowHostHeaderOriginFallback` enabled for local development; must be disabled for production
- **Config not bind-mounted**: `openclaw.json` lives in the `openclaw-data` Docker volume (atomic rename fails on Windows bind mounts). Sync to host via `docker cp` or `sync-openclaw.sh`
- **AGENTS.md changes**: only take effect on new sessions (existing sessions cache the system prompt)
- **Gateway token**: passed at Flutter build time via `--dart-define=GATEWAY_TOKEN=...`
- **ACP**: enabled with acpx backend, allowed agents: pi, claude, codex, opencode, gemini

## Flutter Shell Bug Fixes (2026-03-01)

- **Chat history blank**: Gateway returns `content` as `List<block>` (e.g. `[{type:"text",text:"..."}]`), but parser used `as String?` which silently returned null. Fixed with `_extractContent()` helper.
- **History race condition**: Added `_historyLoading` guard and `if (!mounted) return` check to prevent concurrent fetches and setState-after-dispose.
- **History not loading on first login**: `_subscribeToChatEvents()` now checks if client is already connected and loads history immediately (covers missed `notifyListeners` race).
- **Canvas poll wrong session**: `_pollCanvasSurface()` now passes `activeSessionProvider` session key instead of defaulting to `"main"`.
- **Timestamps lost**: History messages now extract `timestamp` (epoch ms) from gateway response instead of using `DateTime.now()`.
- **Session delete client-only**: `_deleteSession()` now calls `sessions.delete` on the gateway.
- **Hardcoded protocol strings**: Replaced with `protocol.dart` constants.
- **Copy-image also downloaded**: Clipboard API interop via `eval+promiseToFuture` was unreliable; replaced with direct `dart:html` Blob + `js_util.callConstructor` for native `ClipboardItem`.
- **Template overlay reappears after Esc**: Replaced boolean flag with `_dismissedAtText` snapshot; overlay stays closed until text changes, then reopens with updated filter.
- **Session badge hidden for main**: Removed `if (activeSession != 'main')` guard; badge now always visible.

## Environment Caveats

- Windows host (WSL2): use PowerShell-compatible commands in crons/hooks
- nginx has `Cache-Control: no-cache, no-store` on JS/HTML; Flutter service worker is a no-op (self-unregisters)
- Hard-refresh (Ctrl+Shift+R) required after frontend rebuilds
- Workspace sync is manual: `scripts/sync-openclaw.sh pull|push workspace`

## Follow-up Checklist

- [ ] Configure Brave API key for web_search tool
- [ ] Add embedding provider for vector memory search (Gemini or OpenAI)
- [ ] Disable dangerous gateway flags for production
- [ ] Restrict state/credentials dir permissions (chmod 700)
- [ ] Set up automated memory sync (cron or hook)
- [ ] Enable nightly-memory-summary cron template
- [ ] Review security audit findings (`openclaw security audit`)

## Daily Log

(Agent will append dated summaries here)
