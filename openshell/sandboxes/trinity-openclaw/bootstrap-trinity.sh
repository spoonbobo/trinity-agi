#!/usr/bin/env bash
# bootstrap-trinity — Configure OpenClaw with Trinity extensions and start the gateway.
# Designed for OpenShell sandboxes. Adapted from src/scripts/bootstrap-openclaw.sh.
#
# Usage:
#   openshell sandbox create --from ./openshell/sandboxes/trinity-openclaw \
#     --forward 18789 -- bootstrap-trinity
set -euo pipefail

OPENCLAW_HOME="${HOME}/.openclaw"
SEED_ROOT="/opt/trinity-seed"

seed_dir_if_empty() {
  local src="$1" dst="$2"
  [ -d "$src" ] || return
  mkdir -p "$dst"
  if [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
    cp -a "$src"/. "$dst"/
    echo "[trinity] Seeded $dst"
  else
    echo "[trinity] Keeping existing $dst"
  fi
}

sync_managed_extension() {
  local id="$1"
  local src="$SEED_ROOT/extensions/$id"
  local dst="$OPENCLAW_HOME/extensions/$id"
  [ -d "$src" ] || return
  mkdir -p "$OPENCLAW_HOME/extensions"
  rm -rf "$dst"
  cp -a "$src" "$dst"
  echo "[trinity] Synced extension: $id"
}

sync_managed_skills() {
  local src_root="$SEED_ROOT/skills"
  local dst_root="$OPENCLAW_HOME/skills"
  [ -d "$src_root" ] || return
  mkdir -p "$dst_root"
  local count=0
  for src in "$src_root"/*; do
    [ -d "$src" ] || continue
    local id; id="$(basename "$src")"
    rm -rf "$dst_root/$id"
    cp -a "$src" "$dst_root/$id"
    count=$((count + 1))
  done
  echo "[trinity] Synced skills: $count"
}

echo "[trinity] Bootstrapping Trinity OpenClaw sandbox..."

sync_managed_skills
seed_dir_if_empty "$SEED_ROOT/cron-templates" "$OPENCLAW_HOME/cron-templates"
sync_managed_extension "canvas-bridge"
sync_managed_extension "file-upload"

mkdir -p "$OPENCLAW_HOME/workspace" "$OPENCLAW_HOME/workspace/memory"

if [ ! -f "$OPENCLAW_HOME/workspace/MEMORY.md" ] && [ -f "$SEED_ROOT/workspace/MEMORY.md" ]; then
  cp -a "$SEED_ROOT/workspace/MEMORY.md" "$OPENCLAW_HOME/workspace/MEMORY.md"
  echo "[trinity] Seeded MEMORY.md"
fi

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
  openclaw config set gateway.auth.token "\"$OPENCLAW_GATEWAY_TOKEN\"" >/dev/null 2>&1 \
    && echo "[trinity] Synced gateway token from env" \
    || echo "[trinity] WARN: Failed to sync gateway token" >&2
fi

# Browser defaults
openclaw config set browser.enabled true >/dev/null 2>&1 || true
openclaw config set browser.headless true >/dev/null 2>&1 || true
openclaw config set browser.noSandbox true >/dev/null 2>&1 || true

PW_CHROME=$(find "$HOME/.cache/ms-playwright" -name "chrome" -type f 2>/dev/null | head -1)
if [ -n "$PW_CHROME" ]; then
  openclaw config set browser.executablePath "\"$PW_CHROME\"" >/dev/null 2>&1 || true
  echo "[trinity] Playwright Chromium: $PW_CHROME"

  mkdir -p "$OPENCLAW_HOME/browser/openclaw/user-data"
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
  echo "[trinity] Pre-launched headless Chromium (PID=$!)"
fi

# Browser control bridge (loopback:18791 -> 0.0.0.0:18793) for external proxy access
if command -v socat >/dev/null 2>&1; then
  socat TCP-LISTEN:18793,fork,reuseaddr,bind=0.0.0.0 TCP:127.0.0.1:18791 &
  echo "[trinity] Browser control bridge: 0.0.0.0:18793 -> 127.0.0.1:18791"
fi

mkdir -p "$OPENCLAW_HOME/media/browser"

echo "[trinity] Starting OpenClaw gateway..."
nohup openclaw gateway run --port 18789 --bind lan --allow-unconfigured > /tmp/gateway.log 2>&1 &
GATEWAY_PID=$!

sleep 2

CONFIG_FILE="$OPENCLAW_HOME/openclaw.json"
token=$(grep -o '"token"\s*:\s*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d'"' -f4 || true)

echo ""
echo "Trinity OpenClaw gateway started (PID=$GATEWAY_PID)"
echo "  Logs: /tmp/gateway.log"
if [ -n "${token}" ]; then
  echo "  UI:   http://127.0.0.1:18789/?token=${token}"
else
  echo "  UI:   http://127.0.0.1:18789/"
fi
echo ""

exec bash
