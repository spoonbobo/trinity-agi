export default function ConfigurationPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GUIDES
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Configuration
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Environment variables, secrets, RBAC, and deployment tuning.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Core Secrets
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          These must be set in <code className="text-[#6ee7b7]">web/.env</code> for Docker Compose,
          or via <code className="text-[#6ee7b7]">--set secrets.*</code> for Helm.
        </p>
        <div className="space-y-4">
          {[
            { name: "OPENCLAW_GATEWAY_TOKEN", services: "openclaw, auth-service, terminal-proxy, frontend", desc: "Gateway authentication token" },
            { name: "SUPABASE_JWT_SECRET", services: "supabase-auth, auth-service, terminal-proxy", desc: "JWT signing secret (shared)" },
            { name: "SUPABASE_ANON_KEY", services: "supabase-auth, auth-service, frontend", desc: "GoTrue anonymous API key" },
            { name: "SUPABASE_POSTGRES_PASSWORD", services: "supabase-db, auth-service, keycloak", desc: "PostgreSQL password" },
            { name: "KEYCLOAK_ADMIN_PASSWORD", services: "keycloak", desc: "Keycloak admin console password" },
            { name: "KEYCLOAK_CLIENT_SECRET", services: "supabase-auth", desc: "OIDC client secret for Keycloak" },
          ].map((secret) => (
            <div key={secret.name} className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-4">
              <div className="font-mono text-sm text-[#e5e5e5]">{secret.name}</div>
              <p className="mt-1 font-sans text-xs text-[#6b6b6b]">{secret.desc}</p>
              <p className="mt-1 font-mono text-[10px] text-[#3a3a3a]">Used by: {secret.services}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Auth &amp; Superadmin
        </h2>
        <div className="space-y-4">
          {[
            { name: "ENABLE_DEFAULT_SUPERADMIN", def: "true", desc: "Bootstrap a superadmin user on first startup" },
            { name: "DEFAULT_SUPERADMIN_EMAIL", def: "admin@trinity.local", desc: "Default superadmin email" },
            { name: "DEFAULT_SUPERADMIN_PASSWORD", def: "admin", desc: "Default superadmin password (change in production!)" },
            { name: "SUPERADMIN_ALLOWLIST", def: "(empty)", desc: "Comma-separated user IDs allowed superadmin access" },
          ].map((v) => (
            <div key={v.name} className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-4">
              <div className="flex items-baseline gap-3">
                <span className="font-mono text-sm text-[#e5e5e5]">{v.name}</span>
                <span className="font-mono text-xs text-[#3a3a3a]">default: {v.def}</span>
              </div>
              <p className="mt-1 font-sans text-xs text-[#6b6b6b]">{v.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          RBAC Role Hierarchy
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`superadmin (tier: privileged)  ── full platform access
  └─ admin (tier: privileged)  ── user/skill/rbac management
      └─ user (tier: standard) ── chat, memory, tools, automations
          └─ guest (tier: safe) ── read-only, safe terminal commands

22 granular permissions across domains:
  chat, canvas, memory, skills, crons, terminal,
  settings, governance, acp, users, audit`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Helm Values (Kubernetes)
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          Key configuration in <code className="text-[#6ee7b7]">values.yaml</code>:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Namespace & registry
global.namespace: trinity
global.imageRegistry: ""  # e.g. "ghcr.io/your-org/"

# Ingress (main app)
ingress.enabled: true
ingress.host: ""          # empty = match all (dev)
ingress.host: "app.trinity.ai"  # production

# Marketing site
site.enabled: true
site.host: ""              # empty = NodePort (dev)
site.host: "www.trinity.ai"  # production (creates Ingress)

# Vault
vault.devMode: true   # dev
vault.devMode: false  # production

# Gateway scaling
gatewayProxy.replicas: 2
gatewayOrchestrator.replicas: 1

# Overlays
# Dev:  values.dev.yaml  (small resources, single replicas)
# Prod: values.prod.yaml (HA, TLS, strict security)`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Frontend Compile-Time Constants
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 overflow-x-auto">
          <table className="w-full font-mono text-xs text-[#8b8b8b]">
            <thead>
              <tr className="border-b border-[#2a2a2a] text-left text-[#6ee7b7]">
                <th className="pb-3 pr-4">Constant</th>
                <th className="pb-3 pr-4">Default</th>
                <th className="pb-3">Purpose</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#1a1a1a]">
              {[
                ["GATEWAY_TOKEN", "(set in .env)", "Gateway auth"],
                ["GATEWAY_WS_URL", "ws://localhost:18789", "OpenClaw WebSocket"],
                ["TERMINAL_WS_URL", "ws://localhost/terminal/", "Terminal proxy"],
                ["AUTH_SERVICE_URL", "http://localhost", "Auth service (via nginx)"],
                ["SUPABASE_ANON_KEY", "(set in .env)", "GoTrue API key"],
              ].map(([name, def, purpose]) => (
                <tr key={name}>
                  <td className="py-2 pr-4 text-[#e5e5e5]">{name}</td>
                  <td className="py-2 pr-4">{def}</td>
                  <td className="py-2">{purpose}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
