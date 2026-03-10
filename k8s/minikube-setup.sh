#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$SCRIPT_DIR/charts/trinity-platform"
VALUES_MINIKUBE="$CHART_DIR/values.minikube.yaml"
NAMESPACE="${TRINITY_NAMESPACE:-trinity}"
RELEASE_NAME="${TRINITY_RELEASE_NAME:-trinity}"

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-7168}"
MINIKUBE_DISK="${MINIKUBE_DISK:-40g}"

DEFAULT_SUPERADMIN_EMAIL="${DEFAULT_SUPERADMIN_EMAIL:-admin@trinity.work}"
DEFAULT_SUPERADMIN_PASSWORD="${DEFAULT_SUPERADMIN_PASSWORD:-admin123}"
DEFAULT_KEYCLOAK_ADMIN_PASSWORD="${DEFAULT_KEYCLOAK_ADMIN_PASSWORD:-trinity-kc-admin-123}"
DEFAULT_DB_PASSWORD="${DEFAULT_DB_PASSWORD:-trinity-pg-password-123}"
BOOTSTRAP_SIGNUP_RETRIES="${BOOTSTRAP_SIGNUP_RETRIES:-5}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

read_secret_value() {
  local secret_name="$1"
  local secret_key="$2"
  local fallback="$3"
  kubectl get secret "$secret_name" -n "$NAMESPACE" -o "jsonpath={.data.${secret_key}}" \
    | base64 -d 2>/dev/null || echo "$fallback"
}

wait_for_supabase_db() {
  local db_password="$1"

  info "Waiting for supabase-db pod to be ready..."
  kubectl wait --for=condition=Ready pod/supabase-db-0 -n "$NAMESPACE" --timeout=180s >/dev/null

  info "Waiting for PostgreSQL to accept connections..."
  for _ in $(seq 1 60); do
    if kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" \
      psql -U supabase_admin -d supabase -tAc "select 1;" >/dev/null 2>&1; then
      ok "PostgreSQL is ready"
      return
    fi
    sleep 2
  done

  fail "PostgreSQL was not ready in time"
}

install_brew() {
  if command -v brew &>/dev/null; then
    ok "Homebrew already installed"
    return
  fi
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    if ! rg -q 'brew shellenv' ~/.zprofile 2>/dev/null; then
      echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
  fi
  ok "Homebrew installed"
}

install_tools() {
  local casks=("docker")
  local formulae=("minikube" "kubectl" "helm")

  for cask in "${casks[@]}"; do
    if brew list --cask "$cask" &>/dev/null || [ -d "/Applications/Docker.app" ]; then
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
    if [ "$retries" -gt 60 ]; then
      fail "Docker Desktop did not start within 2 minutes. Please start it manually and re-run."
    fi
    sleep 2
  done
  ok "Docker Desktop is running"
}

start_minikube() {
  if minikube status --format='{{.Host}}' 2>/dev/null | rg -q "Running"; then
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

build_images() {
  info "Configuring shell to use minikube's Docker daemon..."
  eval "$(minikube docker-env)"

  local images=(
    "trinity-auth-service:latest|$PROJECT_ROOT/app/auth-service|$PROJECT_ROOT/app/auth-service/Dockerfile"
    "trinity-gateway-orchestrator:latest|$PROJECT_ROOT/app/gateway-orchestrator|$PROJECT_ROOT/app/gateway-orchestrator/Dockerfile"
    "trinity-gateway-proxy:latest|$PROJECT_ROOT/app/gateway-proxy|$PROJECT_ROOT/app/gateway-proxy/Dockerfile"
    "trinity-terminal-proxy:latest|$PROJECT_ROOT/app/terminal-proxy|$PROJECT_ROOT/app/terminal-proxy/Dockerfile"
    "trinity-copilot:latest|$PROJECT_ROOT|$PROJECT_ROOT/app/copilot/Dockerfile"
    "trinity-lightrag:latest|$PROJECT_ROOT/app/lightrag|$PROJECT_ROOT/app/lightrag/Dockerfile"
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
    info "Building openclaw:trinity..."
    docker build -t "openclaw:trinity" -f "$PROJECT_ROOT/app/Dockerfile.openclaw" "$PROJECT_ROOT/app" || {
      warn "Failed to build openclaw:trinity -- skipping"
    }
    ok "Built openclaw:trinity"
  fi

  eval "$(minikube docker-env --unset)"
  ok "All available images built inside minikube"
}

create_namespace() {
  if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    ok "Namespace $NAMESPACE already exists"
  else
    info "Creating namespace $NAMESPACE..."
    kubectl create namespace "$NAMESPACE"
    ok "Namespace $NAMESPACE created"
  fi

  kubectl label namespace "$NAMESPACE" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
  kubectl annotate namespace "$NAMESPACE" \
    meta.helm.sh/release-name="$RELEASE_NAME" \
    meta.helm.sh/release-namespace="$NAMESPACE" \
    --overwrite >/dev/null 2>&1 || true
}

helm_deploy() {
  if [ ! -f "$VALUES_MINIKUBE" ]; then
    fail "Missing $VALUES_MINIKUBE -- run this script from the project root"
  fi

  info "Running helm dependency update..."
  helm dependency update "$CHART_DIR" 2>/dev/null || true

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    info "Upgrading existing release $RELEASE_NAME..."
    helm upgrade "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_MINIKUBE" \
      --no-hooks \
      --timeout 10m
  else
    info "Installing release $RELEASE_NAME..."
    helm install "$RELEASE_NAME" "$CHART_DIR" \
      -n "$NAMESPACE" \
      -f "$VALUES_MINIKUBE" \
      --create-namespace \
      --no-hooks \
      --timeout 10m
  fi
  ok "Helm release $RELEASE_NAME deployed in namespace $NAMESPACE"
}

fix_ingress() {
  info "Patching ingress-nginx-controller to LoadBalancer for minikube tunnel..."
  kubectl patch svc ingress-nginx-controller -n ingress-nginx \
    -p '{"spec":{"type":"LoadBalancer"}}' 2>/dev/null || true
  ok "Ingress controller set to LoadBalancer"
}

run_migrations() {
  local migrations_dir="$PROJECT_ROOT/app/supabase/migrations"
  local db_password
  local output
  db_password="$(read_secret_value trinity-secrets SUPABASE_POSTGRES_PASSWORD "$DEFAULT_DB_PASSWORD")"

  wait_for_supabase_db "$db_password"

  info "Creating keycloak + rbac schemas with grants..."
  kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" psql -v ON_ERROR_STOP=1 -U supabase_admin -d supabase -c "
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
    GRANT USAGE, CREATE ON SCHEMA auth TO supabase_auth_admin;
    GRANT ALL ON ALL TABLES IN SCHEMA auth TO supabase_auth_admin;
    GRANT ALL ON ALL SEQUENCES IN SCHEMA auth TO supabase_auth_admin;
    GRANT ALL ON ALL ROUTINES IN SCHEMA auth TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON TABLES TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON SEQUENCES TO supabase_auth_admin;
    ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA auth GRANT ALL ON ROUTINES TO supabase_auth_admin;
    GRANT supabase_auth_admin TO postgres;
  " >/dev/null
  ok "Schema grants complete"

  info "Running RBAC migrations..."
  for f in "$migrations_dir"/0*.sql; do
    [ -f "$f" ] || continue
    info "  $(basename "$f")"
    output="$(kubectl exec -i supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" \
      psql -v ON_ERROR_STOP=1 -U supabase_admin -d supabase < "$f" 2>&1)" || {
      if printf '%s\n' "$output" | rg -q '__SKIP_MIGRATION__'; then
        ok "  $(basename "$f") (already applied, skipped)"
        continue
      fi
      printf '%s\n' "$output"
      fail "Migration failed: $(basename "$f")"
    }
    printf '%s\n' "$output" | sed -n '$p'
  done
  ok "Migrations complete"
}

bootstrap_admin() {
  local anon_key
  local db_password
  local admin_email
  local admin_password
  local signup_response
  local user_count
  local role_count
  local attempt
  local auth_ready=0

  anon_key="$(read_secret_value trinity-secrets SUPABASE_ANON_KEY "")"
  db_password="$(read_secret_value trinity-secrets SUPABASE_POSTGRES_PASSWORD "$DEFAULT_DB_PASSWORD")"
  admin_email="$(read_secret_value trinity-superadmin DEFAULT_SUPERADMIN_EMAIL "$DEFAULT_SUPERADMIN_EMAIL")"
  admin_password="$(read_secret_value trinity-superadmin DEFAULT_SUPERADMIN_PASSWORD "$DEFAULT_SUPERADMIN_PASSWORD")"

  if [ -z "$anon_key" ]; then
    warn "Could not read SUPABASE_ANON_KEY -- skipping admin bootstrap"
    return
  fi

  info "Waiting for supabase-auth to be ready..."
  for _ in $(seq 1 30); do
    if kubectl exec -n "$NAMESPACE" deploy/supabase-auth -- wget -qO- http://localhost:9999/health >/dev/null 2>&1; then
      auth_ready=1
      break
    fi
    sleep 3
  done
  if [ "$auth_ready" != "1" ]; then
    fail "supabase-auth did not become ready before bootstrap"
  fi

  info "Creating admin user ($admin_email)..."
  local signup_url="http://supabase-auth:9999/signup"

  for attempt in $(seq 1 "$BOOTSTRAP_SIGNUP_RETRIES"); do
    signup_response="$(kubectl exec -n "$NAMESPACE" deploy/supabase-auth -- wget -qO- \
      --post-data="{\"email\":\"$admin_email\",\"password\":\"$admin_password\"}" \
      --header="Content-Type: application/json" \
      --header="apikey: $anon_key" \
      "$signup_url" 2>/dev/null || true)"

    if [ -n "$signup_response" ]; then
      info "Signup attempt $attempt/$BOOTSTRAP_SIGNUP_RETRIES: response received from GoTrue"
    else
      warn "Signup attempt $attempt/$BOOTSTRAP_SIGNUP_RETRIES: no response from GoTrue"
    fi

    for _ in $(seq 1 20); do
      user_count="$(kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" \
        psql -U supabase_admin -d supabase -tAc "select count(*) from auth.users where email = '$admin_email';" 2>/dev/null || echo 0)"
      user_count="$(printf '%s' "$user_count" | tr -d '[:space:]')"
      if [ "$user_count" = "1" ]; then
        break
      fi
      sleep 1
    done

    if [ "${user_count:-0}" = "1" ]; then
      break
    fi

    warn "Admin user not visible in auth.users yet; retrying signup"
    sleep 2
  done

  if [ "${user_count:-0}" != "1" ]; then
    fail "Admin user was not created in auth.users after $BOOTSTRAP_SIGNUP_RETRIES attempts"
  fi

  info "Assigning superadmin role..."
  kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" psql -v ON_ERROR_STOP=1 -U supabase_admin -d supabase -c "
    INSERT INTO rbac.user_roles (user_id, role_id)
    SELECT u.id, r.id FROM auth.users u, rbac.roles r
    WHERE u.email = '$admin_email' AND r.name = 'superadmin'
    ON CONFLICT DO NOTHING;
  " >/dev/null

  role_count="$(kubectl exec supabase-db-0 -n "$NAMESPACE" -- env PGPASSWORD="$db_password" \
    psql -U supabase_admin -d supabase -tAc "select count(*) from rbac.user_roles ur join auth.users u on u.id = ur.user_id join rbac.roles r on r.id = ur.role_id where u.email = '$admin_email' and r.name = 'superadmin';" 2>/dev/null || echo 0)"
  role_count="$(printf '%s' "$role_count" | tr -d '[:space:]')"
  if [ "${role_count:-0}" != "1" ]; then
    fail "Superadmin role assignment verification failed for $admin_email"
  fi

  ok "Admin user bootstrapped"
}

print_status() {
  local admin_email
  local admin_password
  local keycloak_admin_password

  admin_email="$(read_secret_value trinity-superadmin DEFAULT_SUPERADMIN_EMAIL "$DEFAULT_SUPERADMIN_EMAIL")"
  admin_password="$(read_secret_value trinity-superadmin DEFAULT_SUPERADMIN_PASSWORD "$DEFAULT_SUPERADMIN_PASSWORD")"
  keycloak_admin_password="$(read_secret_value trinity-secrets KEYCLOAK_ADMIN_PASSWORD "$DEFAULT_KEYCLOAK_ADMIN_PASSWORD")"

  echo ""
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Trinity Platform deployed on minikube!${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${CYAN}Namespace:${NC}  $NAMESPACE"
  echo -e "  ${CYAN}Release:${NC}    $RELEASE_NAME"
  echo -e "  ${CYAN}URL:${NC}        http://localhost  (requires: minikube tunnel)"
  echo -e "  ${CYAN}Admin:${NC}      $admin_email / $admin_password"
  echo -e "  ${CYAN}Keycloak:${NC}   http://localhost/keycloak (admin / $keycloak_admin_password)"
  echo ""
  echo -e "  ${YELLOW}Start the tunnel (keep running in a separate terminal):${NC}"
  echo -e "    minikube tunnel"
  echo ""
  echo -e "  ${YELLOW}Useful commands:${NC}"
  echo -e "    kubectl get pods -n $NAMESPACE          # Check pod status"
  echo -e "    k9s -n $NAMESPACE                       # Interactive dashboard"
  echo -e "    kubectl logs -f <pod> -n $NAMESPACE     # Stream logs"
  echo -e "    helm upgrade $RELEASE_NAME $CHART_DIR -n $NAMESPACE -f $VALUES_MINIKUBE --no-hooks"
  echo ""
}

main() {
  echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  Trinity Platform - Minikube Setup          ║${NC}"
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
      create_namespace
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
      create_namespace
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
