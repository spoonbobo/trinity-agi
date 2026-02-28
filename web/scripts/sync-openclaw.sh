#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  sync-openclaw.sh — bidirectional sync between the
#  trinity-openclaw container and the host web/ directory.
#
#  Usage:
#    ./scripts/sync-openclaw.sh pull          # container → host
#    ./scripts/sync-openclaw.sh push          # host → container
#    ./scripts/sync-openclaw.sh pull skills   # pull only skills/
#    ./scripts/sync-openclaw.sh push workspace # push only workspace/
#    ./scripts/sync-openclaw.sh diff          # show what differs
#
#  Supported targets: skills, cron-templates, workspace, extensions, all (default)
# ─────────────────────────────────────────────────────────────
set -euo pipefail

CONTAINER="${OPENCLAW_CONTAINER_NAME:-trinity-openclaw}"
REMOTE_ROOT="/home/node/.openclaw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Mapping: target → container-path : host-path
declare -A DIR_MAP=(
  [skills]="$REMOTE_ROOT/skills:$HOST_ROOT/skills"
  [cron-templates]="$REMOTE_ROOT/cron-templates:$HOST_ROOT/cron-templates"
  [workspace]="$REMOTE_ROOT/workspace:$HOST_ROOT/workspace-seed"
  [extensions]="$REMOTE_ROOT/extensions:$HOST_ROOT/extensions"
)

TARGETS=("skills" "cron-templates" "workspace" "extensions")

# ── helpers ──────────────────────────────────────────────────

usage() {
  echo "Usage: $0 <pull|push|diff> [target]"
  echo ""
  echo "Directions:"
  echo "  pull   Copy data from the container to the host"
  echo "  push   Copy data from the host into the container"
  echo "  diff   Show a summary of differences"
  echo ""
  echo "Targets (optional — defaults to all):"
  echo "  skills | cron-templates | workspace | extensions | all"
  exit 1
}

require_container() {
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "[sync] ERROR: Container '$CONTAINER' not found. Is it running?"
    exit 1
  fi
}

parse_map() {
  local target="$1"
  IFS=':' read -r REMOTE_PATH HOST_PATH <<< "${DIR_MAP[$target]}"
}

# ── pull (container → host) ──────────────────────────────────

do_pull() {
  local target="$1"
  parse_map "$target"

  echo "[sync] pull  $target: $CONTAINER:$REMOTE_PATH → $HOST_PATH"

  # Check if the source dir exists inside the container
  if ! docker exec "$CONTAINER" test -d "$REMOTE_PATH"; then
    echo "[sync]   SKIP — $REMOTE_PATH does not exist in container"
    return
  fi

  mkdir -p "$HOST_PATH"

  # Use a temp dir so we can do an atomic-ish replacement
  local tmp
  tmp="$(mktemp -d)"
  docker cp "$CONTAINER:$REMOTE_PATH/." "$tmp/"

  # Sync: mirror the container content into the host directory.
  # We use rsync if available (preserves permissions, gives nice output),
  # otherwise fall back to cp.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$tmp/" "$HOST_PATH/"
  else
    rm -rf "${HOST_PATH:?}/"*
    cp -a "$tmp/." "$HOST_PATH/"
  fi

  rm -rf "$tmp"
  echo "[sync]   OK"
}

# ── push (host → container) ──────────────────────────────────

do_push() {
  local target="$1"
  parse_map "$target"

  echo "[sync] push  $target: $HOST_PATH → $CONTAINER:$REMOTE_PATH"

  if [ ! -d "$HOST_PATH" ]; then
    echo "[sync]   SKIP — $HOST_PATH does not exist on host"
    return
  fi

  # Ensure target dir exists in the container
  docker exec "$CONTAINER" mkdir -p "$REMOTE_PATH"

  # docker cp overwrites the target directory contents
  docker cp "$HOST_PATH/." "$CONTAINER:$REMOTE_PATH/"

  # Fix ownership (container runs as node:node, uid 1000)
  docker exec "$CONTAINER" chown -R node:node "$REMOTE_PATH"

  echo "[sync]   OK"
}

# ── diff ─────────────────────────────────────────────────────

do_diff() {
  local target="$1"
  parse_map "$target"

  echo "[sync] diff  $target"

  if [ ! -d "$HOST_PATH" ]; then
    echo "[sync]   Host path $HOST_PATH does not exist"
    return
  fi

  if ! docker exec "$CONTAINER" test -d "$REMOTE_PATH"; then
    echo "[sync]   Container path $REMOTE_PATH does not exist"
    return
  fi

  # Pull container listing into a temp dir and diff the trees
  local tmp
  tmp="$(mktemp -d)"
  docker cp "$CONTAINER:$REMOTE_PATH/." "$tmp/"

  # Compare file trees
  if command -v diff >/dev/null 2>&1; then
    echo "--- container ($REMOTE_PATH)"
    echo "+++ host      ($HOST_PATH)"
    diff -rq "$tmp" "$HOST_PATH" 2>/dev/null | sed 's|'"$tmp"'|[container]|g; s|'"$HOST_PATH"'|[host]|g' || true
  else
    echo "[sync]   diff not available; listing both sides"
    echo "  Container files:"
    docker exec "$CONTAINER" find "$REMOTE_PATH" -type f | sort | sed "s|$REMOTE_PATH/||"
    echo "  Host files:"
    find "$HOST_PATH" -type f | sort | sed "s|$HOST_PATH/||"
  fi

  rm -rf "$tmp"
}

# ── main ─────────────────────────────────────────────────────

ACTION="${1:-}"
TARGET="${2:-all}"

if [ -z "$ACTION" ]; then
  usage
fi

require_container

# Resolve target list
if [ "$TARGET" = "all" ]; then
  selected_targets=("${TARGETS[@]}")
else
  if [ -z "${DIR_MAP[$TARGET]+x}" ]; then
    echo "[sync] ERROR: Unknown target '$TARGET'"
    echo "[sync] Valid targets: ${TARGETS[*]} all"
    exit 1
  fi
  selected_targets=("$TARGET")
fi

case "$ACTION" in
  pull)
    echo "[sync] ═══ Pulling from container '$CONTAINER' ═══"
    for t in "${selected_targets[@]}"; do do_pull "$t"; done
    echo "[sync] ═══ Pull complete ═══"
    ;;
  push)
    echo "[sync] ═══ Pushing to container '$CONTAINER' ═══"
    for t in "${selected_targets[@]}"; do do_push "$t"; done
    echo "[sync] ═══ Push complete ═══"
    ;;
  diff)
    echo "[sync] ═══ Diff: container vs host ═══"
    for t in "${selected_targets[@]}"; do do_diff "$t"; done
    echo "[sync] ═══ Diff complete ═══"
    ;;
  *)
    usage
    ;;
esac
