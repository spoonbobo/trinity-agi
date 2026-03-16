export default function InstallationPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          SETUP
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Installation
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Docker Compose for single-machine development, Helm chart for Kubernetes deployments.
        </p>
      </div>

      <div className="mt-8 rounded-xl border border-[#2a2a2a] bg-[#0d1f17] p-6">
        <h3 className="mb-4 font-sans text-lg font-semibold text-[#6ee7b7]">
          Why Self-Host?
        </h3>
        <ul className="space-y-2 font-sans text-sm text-[#8b8b8b]">
          {[
            "Complete data privacy -- conversations, memory, and secrets never leave your infrastructure",
            "Full RBAC control -- manage users, roles, and permissions through the admin panel",
            "No usage limits -- run unlimited agent turns with your own LLM API keys",
            "Customisable -- MIT licensed, modify any service to fit your needs",
            "Your own SSO -- federate Keycloak with your existing LDAP, Active Directory, or OIDC provider",
          ].map((reason) => (
            <li key={reason} className="flex items-start gap-3">
              <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#6ee7b7]" />
              <span>{reason}</span>
            </li>
          ))}
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          System Requirements
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <ul className="space-y-3 font-sans text-sm text-[#8b8b8b]">
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">CPU:</span>
              4+ cores recommended
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">RAM:</span>
              8 GB minimum (15 containers run concurrently)
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">Storage:</span>
              10 GB for images + volumes (PostgreSQL, Loki, Grafana, Vault)
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">Docker:</span>
              Engine 24+, Compose v2
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">K8s (optional):</span>
              Kubernetes 1.27+, Helm 3.12+, Ingress controller
            </li>
          </ul>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Docker Compose
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          The <code className="text-[#6ee7b7]">app/docker-compose.yml</code> file defines
          the full 15-service stack. Nginx listens on port 80 and reverse-proxies
          all backend services.
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# 1. Create .env with required secrets (see Configuration docs)
cp app/.env.example app/.env

# 2. Build Flutter frontend
docker compose -f app/docker-compose.yml --profile build build --no-cache frontend-builder
docker compose -f app/docker-compose.yml --profile build run --rm frontend-builder

# 3. Start all services
docker compose -f app/docker-compose.yml up -d

# 4. Verify
docker compose -f app/docker-compose.yml ps   # all containers should be healthy
curl http://localhost                          # should return the Flutter SPA`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Kubernetes (Helm)
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          The Helm chart at <code className="text-[#6ee7b7]">k8s/charts/trinity-platform/</code> deploys
          all services into a Kubernetes cluster with proper health probes, resource limits, and
          optional HPA for the gateway proxy.
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Build container images first
docker build -t trinity-frontend:latest app/frontend/
docker build -t trinity-auth-service:latest app/auth-service/
docker build -t trinity-terminal-proxy:latest app/terminal-proxy/
docker build -t trinity-gateway-orchestrator:latest app/gateway-orchestrator/
docker build -t trinity-gateway-proxy:latest app/gateway-proxy/
docker build -t trinity-site:latest site/

# Install with the Minikube example values
helm install trinity k8s/charts/trinity-platform \\
  -n trinity --create-namespace \\
  -f k8s/charts/trinity-platform/values.minikube.yaml \\
  --set secrets.supabaseJwtSecret=<secret> \\
  --set secrets.supabasePostgresPassword=<password>

# Install with your own cluster override
helm install trinity k8s/charts/trinity-platform \\
  -n trinity --create-namespace \\
  -f my-values.yaml \\
  --set secrets.supabaseJwtSecret=<secret> \\
  --set secrets.supabasePostgresPassword=<password>`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Minikube
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          For local Kubernetes testing, use the one-command setup script:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`./k8s/minikube-setup.sh all`}</code>
          </pre>
        </div>
        <p className="mt-4 font-sans text-sm text-[#8b8b8b]">
          See the{" "}
          <a href="/docs/minikube" className="text-[#6ee7b7] underline hover:text-[#a7f3d0]">
            Minikube guide
          </a>{" "}
          for details and available subcommands.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Service Map
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 overflow-x-auto">
          <table className="w-full font-mono text-xs text-[#8b8b8b]">
            <thead>
              <tr className="border-b border-[#2a2a2a] text-left text-[#6ee7b7]">
                <th className="pb-3 pr-4">Service</th>
                <th className="pb-3 pr-4">Port</th>
                <th className="pb-3">Purpose</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#1a1a1a]">
              {[
                ["nginx", "80", "Reverse proxy + Flutter SPA host"],
                ["openclaw-gateway", "18789", "AI backbone (chat, tools, agents)"],
                ["gateway-orchestrator", "18801", "Per-user OpenClaw instance lifecycle"],
                ["gateway-proxy", "18800", "Routes requests to user-specific gateways"],
                ["auth-service", "18791", "RBAC + JWT resolution"],
                ["terminal-proxy", "18790", "WebSocket bridge for CLI commands"],
                ["supabase-db", "5432", "PostgreSQL (RBAC schema + GoTrue)"],
                ["supabase-auth", "9999", "GoTrue (email/password + OIDC)"],
                ["keycloak", "8080", "IdP broker (SSO federation)"],
                ["vault", "8200", "Secret management"],
                ["grafana", "3000", "Monitoring dashboards"],
                ["loki", "3100", "Log aggregation"],
                ["copilot", "-", "OpenCode copilot service"],
                ["lightrag", "18803", "Knowledge graph RAG sidecar"],
                ["fluentd", "24224", "Log collection"],
              ].map(([svc, port, purpose]) => (
                <tr key={svc}>
                  <td className="py-2 pr-4 text-[#e5e5e5]">{svc}</td>
                  <td className="py-2 pr-4">{port}</td>
                  <td className="py-2">{purpose}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Production Checklist
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <ul className="space-y-3 font-sans text-sm text-[#8b8b8b]">
            {[
              "Disable Vault dev mode (vault.devMode: false in Helm values)",
              "Set strong, unique secrets for all services (JWT, Postgres, Keycloak, gateway tokens)",
              "Enable TLS on ingress (ingress.tls.enabled: true, provide cert secrets)",
              "Configure Keycloak SSO federation with your identity provider",
              "Set up regular PostgreSQL backups (supabase-db volume)",
              "Monitor via Grafana -- check the RBAC Security dashboard for anomalies",
              "Review and restrict the superadmin allowlist (superadmin.allowlist)",
              "Scale gateway-proxy replicas and enable HPA for production load",
            ].map((item) => (
              <li key={item} className="flex items-center gap-3">
                <span className="font-mono text-[#6ee7b7]">&rarr;</span>
                {item}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
