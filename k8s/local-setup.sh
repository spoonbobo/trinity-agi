#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$SCRIPT_DIR/charts/trinity-platform"
VALUES_LOCAL="$CHART_DIR/values.local.yaml"
NAMESPACE="trinity-local"
RELEASE_NAME="trinity"

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-7168}"
MINIKUBE_DISK="${MINIKUBE_DISK:-40g}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ─── Step 1: Install Homebrew ──────────────────────────────────────────────
install_brew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew already installed"
    return
  fi
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if ! grep -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
  fi
  ok "Homebrew installed"
}

# ─── Step 2: Install required tools ───────────────────────────────────────
install_tools() {
  local tools=("docker" "minikube" "kubectl" "helm")
  local casks=("docker")
  local formulae=("minikube" "kubectl" "helm")

  for cask in "${casks[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
      ok "$cask (cask) already installed"
    else
      info "Installing $cask (cask)..."
      brew install --cask "$cask"
    fi
  done

  for formula in "${formulae[@]}"; do
    if brew list "$formula" &>/dev/null; then
      ok "$formula already installed"
    else
      info "Installing $formula..."
      brew install "$formula"
    fi
  done

  ok "All tools installed"
}

# ─── Step 3: Ensure Docker Desktop is running ─────────────────────────────
ensure_docker() {
  if docker info &>/dev/null; then
    ok "Docker Desktop is running"
    return
  fi

  info "Starting Docker Desktop..."
  open -a Docker
  local retries=0
  while ! docker info &>/dev/null; do
    retries=$((retries + 1))
    if [ $retries -gt 60 ]; then
      fail "Docker Desktop did not start within 2 minutes. Please start it manually and re-run."
    fi
    sleep 2
  done
  ok "Docker Desktop is running"
}

# ─── Step 4: Start minikube ───────────────────────────────────────────────
start_minikube() {
  if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    ok "Minikube is already running"
  else
    info "Starting minikube (cpus=$MINIKUBE_CPUS, memory=${MINIKUBE_MEMORY}MB, disk=$MINIKUBE_DISK)..."
    minikube start \
      --driver=docker \
      --cpus="$MINIKUBE_CPUS" \
      --memory="$MINIKUBE_MEMORY" \
      --disk-size="$MINIKUBE_DISK" \
      --kubernetes-version=stable
    ok "Minikube started"
  fi

  info "Enabling ingress addon..."
  minikube addons enable ingress 2>/dev/null || true
  ok "Ingress addon enabled"

  info "Enabling metrics-server addon..."
  minikube addons enable metrics-server 2>/dev/null || true
  ok "Metrics-server addon enabled"
}

# ─── Step 5: Build and load images into minikube ──────────────────────────
build_images() {
  info "Configuring shell to use minikube's Docker daemon..."
  eval "$(minikube docker-env)"

  local images=(
    "trinity-auth-service:latest|$PROJECT_ROOT/app/auth-service|$PROJECT_ROOT/app/auth-service/Dockerfile"
    "trinity-gateway-orchestrator:latest|$PROJECT_ROOT/app/gateway-orchestrator|$PROJECT_ROOT/app/gateway-orchestrator/Dockerfile"
    "trinity-gateway-proxy:latest|$PROJECT_ROOT/app/gateway-proxy|$PROJECT_ROOT/app/gateway-proxy/Dockerfile"
    "trinity-terminal-proxy:latest|$PROJECT_ROOT/app/terminal-proxy|$PROJECT_ROOT/app/terminal-proxy/Dockerfile"
    "trinity-copilot:latest|$PROJECT_ROOT|$PROJECT_ROOT/app/copilot/Dockerfile"
    "trinity-frontend:latest|$PROJECT_ROOT/app/frontend|$PROJECT_ROOT/app/frontend/Dockerfile"
    "trinity-site:latest|$PROJECT_ROOT/site|$PROJECT_ROOT/site/Dockerfile"
  )

  for entry in "${images[@]}"; do
    local img="${entry%%|*}"
    local rest="${entry#*|}"
    local ctx="${rest%%|*}"
    local dockerfile="${rest##*|}"

    if [ ! -f "$dockerfile" ]; then
      warn "Skipping $img -- no Dockerfile at $dockerfile"
      continue
    fi

    info "Building $img from $ctx..."
    docker build -t "$img" -f "$dockerfile" "$ctx" || {
      warn "Failed to build $img -- skipping (you can build it later)"
      continue
    }
    ok "Built $img"
  done

  if [ -f "$PROJECT_ROOT/app/Dockerfile.openclaw" ]; then
    info "Building openclaw:local..."
    docker build -t "openclaw:local" -f "$PROJECT_ROOT/app/Dockerfile.openclaw" "$PROJECT_ROOT/app" || {
      warn "Failed to build openclaw:local -- skipping"
    }
    ok "Built openclaw:local"
  fi

  eval "$(minikube docker-env --unset)"
  ok "All available images built inside minikube"
}

# ─── Step 6: Create namespace ─────────────────────────────────────────────
create_namespace() {
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    ok "Namespace $NAMESPACE already exists"
  else
    info "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
    ok "Namespace $NAMESPACE created"
  fi
}

# ─── Step 7: Helm install/upgrade ─────────────────────────────────────────
helm_deploy() {
  if [ ! -f "$VALUES_LOCAL" ]; then
    fail "Missing $VALUES_LOCAL -- run this script from the project root"
  fi

  info "Running helm dependency update..."
  helm dependency update "$CHART_DIR" 2>/dev/null || true

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    info "Upgrading existing release $RELEASE_NAME..."
    helm upgrade "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_LOCAL" \
      --no-hooks \
      --timeout 10m
  else
    info "Installing release $RELEASE_NAME..."
    helm install "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_LOCAL" \
      --create-namespace \
      --no-hooks \
      --timeout 10m
  fi
  ok "Helm release $RELEASE_NAME deployed in namespace $NAMESPACE"
}

# ─── Step 8: Fix ingress for minikube tunnel ──────────────────────────────
fix_ingress() {
  info "Patching ingress-nginx-controller to LoadBalancer for minikube tunnel..."
  kubectl patch svc ingress-nginx-controller -n ingress-nginx \
    -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
  ok "Ingress controller set to LoadBalancer"
}

# ─── Step 9: Run DB schemas + migrations ──────────────────────────────────
run_migrations() {
  local MIGRATIONS_DIR="$PROJECT_ROOT/app/supabase/migrations"
  local DB_PASSWORD
  DB_PASSWORD=$(kubectl get secret trinity-secrets -n "$NAMESPACE" -o jsonpath='{.data.SUPABASE_POSTGRES_PASSWORD}' | base64 -d 2>/dev/null || echo "local-pg-password-123")

  info "Waiting for supabase-db to be ready..."
  kubectl wait --for=condition=Ready pod/supabase-db-0 -n "$NAMESPACE" --timeout=120s 2>/dev/null || true

  info "Creating keycloak + rbac schemas with grants..."
  kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$DB_PASSWORD" psql -U supabase_admin -d supabase -c "
    CREATE SCHEMA IF NOT EXISTS keycloak AUTHORIZATION postgres;
    GRANT ALL ON SCHEMA keycloak TO postgres;
    ALTER DEFAULT PRIVILEGES IN SCHEMA keycloak GRANT ALL ON TABLES TO postgres;
    ALTER DEFAULT PRIVILEGES IN SCHEMA keycloak GRANT ALL ON SEQUENCES TO postgres;
    CREATE SCHEMA IF NOT EXISTS rbac AUTHORIZATION postgres;
    GRANT ALL ON SCHEMA rbac TO postgres;
    GRANT ALL ON SCHEMA auth TO postgres;
    GRANT ALL ON ALL TABLES IN SCHEMA auth TO postgres;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO postgres;
    GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO postgres;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON TABLES TO postgres;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO postgres;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO postgres;
    GRANT supabase_auth_admin TO postgres;
  " 2>&1 || warn "Schema grants failed (may already exist)"

  info "Running RBAC migrations..."
  for f in "$MIGRATIONS_DIR"/0*.sql; do
    [ -f "$f" ] || continue
    info "  $(basename "$f")"
    kubectl exec -i supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$DB_PASSWORD" psql -U postgres -d supabase < "$f" 2>&1 | tail -1 || true
  done
  ok "Migrations complete"
}

# ─── Step 10: Bootstrap admin user ────────────────────────────────────────
bootstrap_admin() {
  local ANON_KEY
  ANON_KEY=$(kubectl get secret trinity-secrets -n "$NAMESPACE" -o jsonpath='{.data.SUPABASE_ANON_KEY}' | base64 -d 2>/dev/null || echo "")

  if [ -z "$ANON_KEY" ]; then
    warn "Could not read SUPABASE_ANON_KEY -- skipping admin bootstrap"
    return
  fi

  info "Waiting for supabase-auth to be ready..."
  for i in $(seq 1 30); do
    if kubectl exec -n "$NAMESPACE" deploy/supabase-auth -- wget -qO- http://localhost:9999/health >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done

  info "Creating admin user (admin@trinity.local)..."
  local SIGNUP_URL="http://supabase-auth:9999/signup"
  kubectl exec -n "$NAMESPACE" deploy/supabase-auth -- wget -qO- \
    --post-data='{"email":"admin@trinity.local","password":"admin123"}' \
    --header="Content-Type: application/json" \
    --header="apikey: $ANON_KEY" \
    "$SIGNUP_URL" 2>/dev/null || true

  info "Assigning superadmin role..."
  local DB_PASSWORD
  DB_PASSWORD=$(kubectl get secret trinity-secrets -n "$NAMESPACE" -o jsonpath='{.data.SUPABASE_POSTGRES_PASSWORD}' | base64 -d 2>/dev/null || echo "local-pg-password-123")
  kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$DB_PASSWORD" psql -U postgres -d supabase -c "
    INSERT INTO rbac.user_roles (user_id, role_id)
    SELECT u.id, r.id FROM auth.users u, rbac.roles r
    WHERE u.email = 'admin@trinity.local' AND r.name = 'superadmin'
    ON CONFLICT DO NOTHING;
  " 2>&1 || true
  ok "Admin user bootstrapped"
}

# ─── Step 11: Print status ───────────────────────────────────────────────
print_status() {
  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Trinity Platform deployed on minikube!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${CYAN}Namespace:${NC}  $NAMESPACE"
  echo -e "  ${CYAN}Release:${NC}    $RELEASE_NAME"
  echo -e "  ${CYAN}URL:${NC}        http://localhost  (requires: minikube tunnel)"
  echo -e "  ${CYAN}Admin:${NC}      admin@trinity.local / admin123"
  echo -e "  ${CYAN}Keycloak:${NC}   http://localhost/keycloak (admin / local-kc-admin-123)"
  echo ""
  echo -e "  ${YELLOW}Start the tunnel (keep running in a separate terminal):${NC}"
  echo -e "    minikube tunnel"
  echo ""
  echo -e "  ${YELLOW}Useful commands:${NC}"
  echo -e "    kubectl get pods -n $NAMESPACE          # Check pod status"
  echo -e "    k9s -n $NAMESPACE                       # Interactive dashboard"
  echo -e "    kubectl logs -f <pod> -n $NAMESPACE     # Stream logs"
  echo -e "    helm upgrade trinity $CHART_DIR -n $NAMESPACE -f $VALUES_LOCAL --no-hooks"
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────
main() {
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  Trinity Platform - Local Minikube Setup     ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
  echo ""

  case "${1:-all}" in
    install-tools)
      install_brew
      install_tools
      ;;
    start)
      ensure_docker
      start_minikube
      ;;
    build)
      ensure_docker
      build_images
      ;;
    deploy)
      helm_deploy
      fix_ingress
      run_migrations
      bootstrap_admin
      print_status
      ;;
    status)
      kubectl get pods -n "$NAMESPACE"
      ;;
    teardown)
      info "Uninstalling helm release..."
      helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
      info "Deleting namespace..."
      kubectl delete namespace "$NAMESPACE" 2>/dev/null || true
      ok "Teardown complete"
      ;;
    all)
      install_brew
      install_tools
      ensure_docker
      start_minikube
      build_images
      helm_deploy
      fix_ingress
      run_migrations
      bootstrap_admin
      print_status
      ;;
    *)
      echo "Usage: $0 {all|install-tools|start|build|deploy|status|teardown}"
      exit 1
      ;;
  esac
}

main "$@"
