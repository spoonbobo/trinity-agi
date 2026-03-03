#!/usr/bin/env bash
set -euo pipefail

OPENCLAW_HOME="/home/node/.openclaw"
SEED_ROOT="/opt/trinity-seed"

ensure_config() {
  local key="$1"
  local value="$2"
  if ! openclaw config get "$key" >/dev/null 2>&1; then
    if ! openclaw config set "$key" "$value" >/dev/null 2>&1; then
      echo "[bootstrap] WARN: Failed to set config: $key" >&2
    else
      echo "[bootstrap] Set default config: $key"
    fi
  fi
}

seed_dir_if_empty() {
  local src="$1"
  local dst="$2"

  if [ ! -d "$src" ]; then
    return
  fi

  if ! mkdir -p "$dst"; then
    echo "[bootstrap] ERROR: Failed to create directory: $dst" >&2
    return 1
  fi

  if [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
    cp -a "$src"/. "$dst"/
    echo "[bootstrap] Seeded $dst from $src"
  else
    echo "[bootstrap] Keeping existing $dst"
  fi
}

seed_dir_if_empty "$SEED_ROOT/skills" "$OPENCLAW_HOME/skills"
seed_dir_if_empty "$SEED_ROOT/cron-templates" "$OPENCLAW_HOME/cron-templates"

if ! mkdir -p "$OPENCLAW_HOME/workspace" "$OPENCLAW_HOME/workspace/memory"; then
  echo "[bootstrap] ERROR: Failed to create workspace directories" >&2
  exit 1
fi

if [ ! -f "$OPENCLAW_HOME/workspace/MEMORY.md" ] && [ -f "$SEED_ROOT/workspace/MEMORY.md" ]; then
  cp -a "$SEED_ROOT/workspace/MEMORY.md" "$OPENCLAW_HOME/workspace/MEMORY.md"
  echo "[bootstrap] Seeded $OPENCLAW_HOME/workspace/MEMORY.md"
else
  echo "[bootstrap] Keeping existing $OPENCLAW_HOME/workspace/MEMORY.md"
fi

# ACP defaults (idempotent; only fills missing keys)
ensure_config "plugins.entries.acpx.enabled" "true"
ensure_config "acp.enabled" "true"
ensure_config "acp.dispatch.enabled" "true"
ensure_config "acp.backend" "acpx"
ensure_config "acp.defaultAgent" "opencode"
ensure_config "acp.allowedAgents" '["pi","claude","codex","opencode","gemini"]'
ensure_config "acp.maxConcurrentSessions" "8"
ensure_config "acp.runtime.ttlMinutes" "120"

# Browser defaults (managed browser for canvas collaboration)
ensure_config "browser.enabled" "true"
ensure_config "browser.defaultProfile" '"openclaw"'
ensure_config "browser.headless" "true"
ensure_config "browser.noSandbox" "true"

# Auto-detect Playwright Chromium path
PW_CHROME=$(find /home/node/.cache/ms-playwright -name "chrome" -type f 2>/dev/null | head -1)
if [ -n "$PW_CHROME" ]; then
  ensure_config "browser.executablePath" "\"$PW_CHROME\""
  echo "[bootstrap] Playwright Chromium: $PW_CHROME"
fi

# Bridge the browser control service (loopback:18791) to 0.0.0.0:18793
# so nginx/other containers can proxy to it. Runs in background.
# Port 18792 is reserved for the Chrome extension relay (gateway+3).
if command -v socat >/dev/null 2>&1; then
  socat TCP-LISTEN:18793,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:18791 &
  echo "[bootstrap] Browser control bridge: 0.0.0.0:18793 -> 127.0.0.1:18791"
fi

# Ensure browser screenshot directory is world-readable for nginx (shared volume).
# nginx serves /__openclaw__/browser-media/ directly from the volume.
mkdir -p "$OPENCLAW_HOME/media/browser"
chmod o+rx "$OPENCLAW_HOME/media" "$OPENCLAW_HOME/media/browser" 2>/dev/null || true
# Background job: periodically make new screenshot files world-readable
( while true; do chmod -f o+r "$OPENCLAW_HOME/media/browser/"*.png 2>/dev/null; sleep 2; done ) &

# Pre-launch headless Chromium on CDP port 18800 so OpenClaw can attach to it.
# OpenClaw's internal browser launcher may fail in Docker without a display server;
# pre-launching ensures the CDP endpoint is ready when the gateway's browser
# control service starts.
PW_CHROME=$(find /home/node/.cache/ms-playwright -name "chrome" -type f 2>/dev/null | head -1)
if [ -n "$PW_CHROME" ]; then
  mkdir -p "$OPENCLAW_HOME/browser/openclaw/user-data"
  # Remove stale lock files from previous container runs
  rm -f "$OPENCLAW_HOME/browser/openclaw/user-data/SingletonLock" \
        "$OPENCLAW_HOME/browser/openclaw/user-data/SingletonSocket" \
        "$OPENCLAW_HOME/browser/openclaw/user-data/SingletonCookie" 2>/dev/null
  DBUS_SESSION_BUS_ADDRESS=/dev/null "$PW_CHROME" \
    --headless --no-sandbox --disable-gpu --no-first-run \
    --remote-debugging-port=18800 \
    --remote-debugging-address=127.0.0.1 \
    --user-data-dir="$OPENCLAW_HOME/browser/openclaw/user-data" \
    --disable-dev-shm-usage \
    --disable-background-networking \
    --disable-default-apps \
    --disable-extensions \
    --disable-sync \
    --disable-translate \
    --mute-audio \
    --hide-scrollbars \
    2>/tmp/chrome-debug.log &
  echo "[bootstrap] Pre-launched headless Chromium on CDP port 18800 (PID=$!)"
fi

exec "$@"
