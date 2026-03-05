export default function SelfHostedPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GUIDES
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Self-Hosted Setup
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Run Trinity AGI on your own infrastructure with Docker Compose or Kubernetes.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Why Self-Host?
        </h2>
        <ul className="mb-8 space-y-3">
          {[
            "Complete data privacy -- conversations, memory, and secrets never leave your infrastructure",
            "Full RBAC control -- manage users, roles, and permissions through the admin panel",
            "No usage limits -- run unlimited agent turns with your own LLM API keys",
            "Customisable -- MIT licensed, modify any service to fit your needs",
            "Your own SSO -- federate Keycloak with your existing LDAP, Active Directory, or OIDC provider",
          ].map((reason) => (
            <li
              key={reason}
              className="flex items-start gap-3 rounded-lg border border-[#2a2a2a] bg-[#141414] p-4"
            >
              <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#6ee7b7]" />
              <span className="font-sans text-sm text-[#8b8b8b]">{reason}</span>
            </li>
          ))}
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Docker Compose
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          The standard deployment method. All 14 services are defined in{" "}
          <code className="text-[#6ee7b7]">web/docker-compose.yml</code> with a production
          overlay at <code className="text-[#6ee7b7]">web/docker-compose.prod.yml</code>.
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`cd web

# Build frontend
docker compose --profile build build --no-cache frontend-builder
docker compose --profile build run --rm frontend-builder

# Start the stack
docker compose up -d

# Production mode (stricter security, TLS)
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Kubernetes (Helm)
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          For production K8s clusters. The Helm chart supports dev and prod value overlays,
          per-user OpenClaw pod orchestration, HPA for gateway-proxy, and separate ingresses
          for the app and marketing site.
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Dev (minikube)
helm install trinity k8s/charts/trinity-platform \\
  -n trinity --create-namespace \\
  -f k8s/charts/trinity-platform/values.dev.yaml

# Production
helm install trinity k8s/charts/trinity-platform \\
  -n trinity --create-namespace \\
  -f k8s/charts/trinity-platform/values.prod.yaml

# Access locally
# App:  via Ingress or kubectl port-forward svc/nginx 80:80
# Site: via NodePort or kubectl port-forward svc/site 3001:3000`}</code>
          </pre>
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
