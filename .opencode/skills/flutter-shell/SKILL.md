---
name: flutter-shell
description: Develop the Trinity AGI Flutter Web Shell -- understand the architecture, A2UI renderer, WebSocket models, dual-client pattern, design tokens, and build workflow.
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: trinity
---

## What This Skill Covers

The Flutter Web Shell is the frontend for Trinity AGI. It is an intentionally "empty" command center -- no static features, no predefined dashboards. The agent and user build functionality together at runtime via A2UI surfaces and chat.

Source: `app/frontend/`

## Architecture

The shell opens **two** concurrent WebSocket connections to the OpenClaw Gateway:

1. **`GatewayClient`** (`lib/core/gateway_client.dart`) -- connects as `operator` role. Handles chat I/O (`chat.send`, `chat.history`, `chat.abort`), exec approvals, and receives streaming `chat` + `agent` events.

2. **`NodeClient`** (`lib/core/node_client.dart`) -- connects as `node` role with `canvas` capability. Routes A2UI surface commands and emits them on a `canvasEvents` stream.

Both clients share `GatewayAuth` (token + device identity) from `lib/core/auth.dart`.

## State Management: Riverpod

All providers are centralized in `core/providers.dart`:

| Provider | Type | Purpose |
|----------|------|---------|
| `authClientProvider` | `ChangeNotifierProvider<AuthClient>` | Auth state, login/logout, API methods |
| `gatewayClientProvider` | `ChangeNotifierProvider<GatewayClient>` | OpenClaw WebSocket (operator role) |
| `terminalClientProvider` | `ChangeNotifierProvider<TerminalProxyClient>` | Terminal proxy WebSocket |

UI-level providers in `main.dart`:

| Provider | Type |
|----------|------|
| `themeModeProvider` | `StateProvider<ThemeMode>` |
| `fontFamilyProvider` | `StateProvider<AppFontFamily>` |
| `languageProvider` | `StateProvider<AppLanguage>` |

**IMPORTANT:** `authClientProvider` is defined in `core/providers.dart` and re-exported via `main.dart`. Always import providers from `core/providers.dart` or `main.dart` -- NEVER from `shell_page.dart`.

## Shell Layout

```
+--------------------------------------------------+
| Status Bar: [dot] memory --- setup skills crons [admin] settings |
+-------------------------+------------------------+
|                         |  Canvas Panel          |
|   ChatStreamView        |  (A2UIRendererPanel)   |
|   (flex:6)              |  (flex:4)              |
|                         |       OR               |
|                         |  Governance Panel      |
+-------------------------+------------------------+
| PromptBar (> cursor, text input, voice mic)      |
+--------------------------------------------------+
```

The `admin` toggle is permission-gated: visible only when `authState.hasPermission('users.list')`.

## Project Structure

```
app/frontend/lib/
  main.dart                              -- App entry, re-exports authClientProvider
  core/
    providers.dart                       -- ALL Riverpod providers (auth, gateway, terminal)
    auth.dart                            -- DeviceIdentity, GatewayAuth
    auth_client.dart                     -- AuthClient, AuthState, AuthRole, API methods
    gateway_client.dart                  -- GatewayClient (OpenClaw WebSocket)
    terminal_client.dart                 -- TerminalProxyClient (terminal proxy WebSocket)
    theme.dart                           -- ShellTokens, buildTheme(), dark/light tokens
    i18n.dart                            -- Tri-lingual i18n (en/zh-Hans/zh-Hant)
    rbac_constants.dart                  -- Permission constants, role-tier mappings
    toast_provider.dart                  -- Toast notifications (showError, showInfo)
  models/
    ws_frame.dart                        -- WsRequest, WsResponse, WsEvent, WsFrame
    a2ui_models.dart                     -- A2UI v0.8 surface/component models
  features/
    auth/                                -- LoginPage, AuthGuard
    shell/                               -- ShellPage (status bar + layout)
    chat/                                -- ChatStreamView (streaming, markdown, tool cards)
    canvas/                              -- A2UIRendererPanel, CanvasWebView
    governance/                          -- ApprovalPanel (exec + Lobster workflows)
    settings/                            -- SettingsDialog (theme/font/lang/account)
    catalog/                             -- SkillsCronDialog (skills + crons + ClawHub)
    memory/                              -- MemoryDialog (MEMORY.md viewer)
    onboarding/                          -- OnboardingWizard (4-step setup)
    admin/                               -- AdminDialog (5 tabs: users/audit/health/rbac/sessions)
    prompt_bar/                          -- PromptBar + VoiceInput
    terminal/                            -- TerminalView
```

## AuthClient API Methods (`core/auth_client.dart`)

| Method | Endpoint | Permission |
|--------|----------|------------|
| `loginWithEmail(email, password)` | GoTrue `/supabase/auth/token` | none |
| `signUpWithEmail(email, password)` | GoTrue `/supabase/auth/signup` | none |
| `loginAsGuest()` | `POST /auth/guest` | none |
| `fetchUsers()` | `GET /auth/users` | users.list |
| `assignUserRole(userId, role)` | `POST /auth/users/:id/role` | users.manage |
| `fetchAuditLog({limit, offset})` | `GET /auth/users/audit` | audit.read |
| `fetchRolePermissionMatrix()` | `GET /auth/users/roles/permissions` | users.list |
| `updateRolePermissions(role, perms)` | `PUT /auth/users/roles/:role/permissions` | users.manage |

## A2UI Renderer

Supported: `Text`, `Column`, `Row`, `Button`, `Card`, `Image`, `TextField`, `Slider`, `Toggle`, `Progress`, `Divider`, `Spacer`

A2UI surfaces arrive via operator events, node `canvasEvents`, or `__A2UI__\n` prefix in tool_result agent events.

## Design Tokens (`core/theme.dart`)

| Token | Dark | Light |
|-------|------|-------|
| surfaceBase | #0A0A0A | #F5F5F5 |
| surfaceCard | #141414 | #EBEBEB |
| border | #2A2A2A | #D1D1D1 |
| accentPrimary | #6EE7B7 | #059669 |
| accentSecondary | #3B82F6 | #2563EB |
| statusError | #EF4444 | #DC2626 |
| statusWarning | #FBBF24 | #D97706 |
| fgPrimary | #E5E5E5 | #1A1A1A |
| fgMuted | #6B6B6B | #6B6B6B |

Access: `ShellTokens.of(context)` via ThemeExtension.

**Widget conventions:**
- All borders: 0.5px, `t.border` color, `BorderRadius.zero`
- Dialogs: zero border-radius + 0.5px border
- Interactive: `GestureDetector` + `Text` (no Material buttons)
- Active toggle: `t.accentPrimary`, inactive: `t.fgMuted`
- Font: Google Fonts monospace (IBM Plex Mono / JetBrains Mono)

## Build & Deploy

**CRITICAL: `run --rm frontend-builder` does NOT rebuild the image.** You MUST rebuild first:

```bash
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder
docker restart trinity-nginx
```

### Compile-time Constants (--dart-define)

| Constant | Default |
|----------|---------|
| GATEWAY_TOKEN | replace-me-with-a-real-token |
| GATEWAY_WS_URL | ws://localhost:18789 |
| TERMINAL_WS_URL | ws://localhost/terminal/ |
| AUTH_SERVICE_URL | http://localhost |
| SUPABASE_ANON_KEY | (empty) |

## HTTP Requests -- MANDATORY: Use `safeXhr()` / `safeHttpRequest()`

All browser HTTP requests MUST go through the shared helpers in `core/http_utils.dart`. **Never** create raw `html.HttpRequest` + manual `Completer` patterns.

### `safeXhr(request, {body, timeout})`

Use for requests where you build an `html.HttpRequest` manually (custom headers, auth tokens). Handles `onLoad`, `onError`, `onAbort` with configurable timeout (default 10s). Aborts the XHR on timeout.

```dart
import '../../core/http_utils.dart';

final request = html.HttpRequest();
request.open('GET', url);
request.setRequestHeader('Authorization', 'Bearer $token');
final responseText = await safeXhr(request);  // 10s default timeout
final responseText = await safeXhr(request, body: jsonEncode(data), timeout: const Duration(seconds: 3));
```

### `safeHttpRequest(url, {method, requestHeaders, sendData, responseType, timeout})`

Use as a drop-in replacement for `html.HttpRequest.request()` -- adds timeout. Returns `html.HttpRequest`.

```dart
final response = await safeHttpRequest(url, method: 'GET', requestHeaders: headers, timeout: const Duration(seconds: 5));
```

### Why this matters

The original `Future.delayed(Duration.zero) + onLoadEnd.first` pattern had a race condition: if the browser resolved the request before the next microtask (cached response, reload cancel, bfcache restore), the `onLoadEnd` subscription was set up *after* the event fired and the Future hung forever. The `safeXhr` helper subscribes to events synchronously via a `Completer` before `send()` is called, eliminating the race.

### Patterns to NEVER use

```dart
// BAD: Race condition -- onLoadEnd.first may miss the event
final completer = Future<String>.delayed(Duration.zero, () async {
  await request.onLoadEnd.first;
  ...
});
request.send();

// BAD: Manual Completer without onAbort or timeout
final completer = Completer<String>();
request.onLoad.listen((_) { completer.complete(...); });
request.onError.listen((_) { completer.completeError(...); });
request.send();
return completer.future;  // hangs forever on abort or server hang

// BAD: html.HttpRequest.request() without timeout
final resp = await html.HttpRequest.request(url, method: 'GET', requestHeaders: headers);
```

## WebSocket Best Practices (`gateway_client.dart`)

- **Always store stream subscriptions**: `_channelSub = _channel!.stream.listen(...)`. Cancel in `disconnect()` and before reconnecting to prevent orphaned callbacks accumulating over reconnections.
- **Schedule reconnect on initial connect failure**: If `connect()` throws during `WebSocketChannel.connect()` or `_channel!.ready`, call `_scheduleReconnect()` in the catch block so the client auto-retries instead of getting stuck in error state.
- **Use epoch guards**: The `_connectionEpoch` pattern prevents stale messages from old connections leaking into new ones.

## Widget Lifecycle -- `mounted` Guards

After every `await` in a `State` method, check `if (!mounted) return;` before calling `setState()`. Async operations (XHR, WebSocket, `Future.delayed`) can complete after the user closes a dialog or navigates away.

```dart
// CORRECT
final result = await someAsyncCall();
if (!mounted) return;
setState(() => _data = result);

// WRONG -- will throw "setState() called after dispose()"
final result = await someAsyncCall();
setState(() => _data = result);
```

## File Picker Safety

Never `await picker.onChange.first` -- it hangs forever if the user cancels (some browsers don't fire `onChange` on cancel). Use a `Completer` with `window.onFocus` fallback and an absolute timeout:

```dart
final pickerCompleter = Completer<html.File?>();
picker.onChange.first.then((_) {
  if (!pickerCompleter.isCompleted) {
    pickerCompleter.complete(picker.files?.first);
  }
});
html.window.onFocus.first.then((_) {
  Future.delayed(const Duration(milliseconds: 300), () {
    if (!pickerCompleter.isCompleted) pickerCompleter.complete(null);
  });
});
picker.click();
final file = await pickerCompleter.future.timeout(
  const Duration(minutes: 2), onTimeout: () => null,
);
```

## Completer Safety Checklist

When using `Completer` (outside of `safeXhr`):

1. **Always handle all completion paths**: success, error, abort/cancel
2. **Always add a timeout**: `.timeout(duration, onTimeout: ...)` on the `.future`
3. **Guard against double-completion**: `if (!completer.isCompleted)` before every `.complete()` / `.completeError()`
4. **Prefer `safeXhr()`** over manual Completer for any HTTP request

## Browser Canvas -- Retry on Init

The gateway/OpenClaw pod may not be ready when the canvas first loads. Use retry-with-backoff for initial status fetch (e.g., 3 retries, 1s/2s/3s delay). Don't show an error screen on the first transient failure.

## `ProgressEvent` in Release Mode

`html.HttpRequest.request()` throws a `ProgressEvent` on non-2xx status codes. In release (minified) mode, `ProgressEvent.toString()` produces `"Instance of 'minified:XY'"`. Error humanization code must NOT treat `"minified:"` as a frontend runtime error -- it's usually a gateway/network error.

## Do Not

- Do not import providers from `shell_page.dart` -- use `core/providers.dart`
- Do not add static features, sidebars, or menus
- Do not use Material buttons -- use GestureDetector + Text
- Do not hardcode URLs -- use `String.fromEnvironment()`
- Do not bypass governance
- Do not create raw `html.HttpRequest` + `Completer` patterns -- use `safeXhr()` or `safeHttpRequest()`
- Do not use `Future.delayed(Duration.zero)` to defer stream subscriptions
- Do not use `.onLoadEnd.first` or `.onLoad.first` for XHR -- use `safeXhr()` which subscribes synchronously
- Do not `await stream.first` on browser events that may never fire (file pickers, etc.)
- Do not call `setState()` after an `await` without checking `if (!mounted) return;`
