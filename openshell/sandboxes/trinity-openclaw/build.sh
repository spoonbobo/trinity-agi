#!/usr/bin/env bash
# Build the Trinity OpenClaw sandbox image for OpenShell.
# Run from the trinity repo root: ./openshell/sandboxes/trinity-openclaw/build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
BUILD_CTX="$SCRIPT_DIR/.build-context"

echo "[build] Preparing build context..."
rm -rf "$BUILD_CTX"
mkdir -p "$BUILD_CTX"

cp "$SCRIPT_DIR/Dockerfile" "$BUILD_CTX/"
cp "$SCRIPT_DIR/bootstrap-trinity.sh" "$BUILD_CTX/"
cp "$SCRIPT_DIR/policy.yaml" "$BUILD_CTX/"

cp -a "$REPO_ROOT/src/extensions" "$BUILD_CTX/extensions"
cp -a "$REPO_ROOT/src/skills" "$BUILD_CTX/skills"
cp -a "$REPO_ROOT/src/cron-templates" "$BUILD_CTX/cron-templates"
cp -a "$REPO_ROOT/src/workspace-seed" "$BUILD_CTX/workspace-seed"

echo "[build] Building trinity-openclaw-sandbox image..."
docker build -t trinity-openclaw-sandbox:latest "$BUILD_CTX"

rm -rf "$BUILD_CTX"
echo "[build] Done. Image: trinity-openclaw-sandbox:latest"
