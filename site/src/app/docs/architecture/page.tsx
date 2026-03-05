export default function ArchitecturePage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          CORE CONCEPTS
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Architecture
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          A 14-service stack behind nginx, with per-user AI agents and a blank-canvas frontend.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Overview
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Trinity AGI runs as a Docker Compose stack (or Kubernetes Helm chart) with nginx as the
          single entry point on port 80. The Flutter web shell connects via WebSocket to per-user
          OpenClaw gateway instances that are spun up on demand by the gateway orchestrator. All
          authentication flows through Supabase GoTrue and Keycloak, with RBAC enforced by the
          auth service.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          System Components
        </h2>
        <div className="space-y-4">
          {[
            {
              title: "Nginx",
              desc: "Reverse proxy and SPA host. Serves the Flutter build and routes /ws, /auth/, /terminal/, /__openclaw__/, /v1/, /tools/ to backend services.",
            },
            {
              title: "OpenClaw Gateway",
              desc: "The AI backbone. Each user gets a dedicated instance with its own memory, skills, and session state. Handles chat, tool execution, and A2UI surface generation.",
            },
            {
              title: "Gateway Orchestrator",
              desc: "Go microservice that manages the lifecycle of per-user OpenClaw instances. Creates, monitors, and tears down gateway pods/containers on demand.",
            },
            {
              title: "Gateway Proxy",
              desc: "Go reverse proxy that routes incoming WebSocket/HTTP requests to the correct user-specific OpenClaw instance. Includes a resolver cache for low-latency routing.",
            },
            {
              title: "Auth Service",
              desc: "Node.js service handling JWT verification, RBAC role resolution, guest token issuance, and user management. Enforces the 4-tier role hierarchy and 22-permission matrix.",
            },
            {
              title: "Terminal Proxy",
              desc: "WebSocket bridge that lets the frontend execute OpenClaw CLI commands (status, doctor, config, etc.) with tier-based permission gating.",
            },
            {
              title: "Supabase (DB + Auth)",
              desc: "PostgreSQL stores the RBAC schema (roles, permissions, user_roles, audit_log). GoTrue handles email/password signup and OIDC federation with Keycloak.",
            },
            {
              title: "Keycloak",
              desc: "Identity provider broker for SSO. Federates LDAP, Active Directory, Authentik, or any OIDC provider into the Supabase auth flow.",
            },
            {
              title: "Vault",
              desc: "HashiCorp Vault for secret management. Stores API keys, tokens, and credentials. Runs in dev mode locally, production mode in K8s.",
            },
            {
              title: "Grafana + Loki + Fluentd",
              desc: "Full observability stack. Fluentd collects logs from all containers, ships to Loki, visualised in Grafana dashboards (RBAC security, login rates, permission denials).",
            },
          ].map((component) => (
            <div
              key={component.title}
              className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6"
            >
              <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
                {component.title.toUpperCase()}
              </h3>
              <p className="font-sans text-sm text-[#8b8b8b]">{component.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Request Flow
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`Browser (Flutter SPA)
  │
  ├─ GET /           → nginx → static Flutter build
  ├─ POST /auth/me   → nginx → auth-service (JWT + RBAC)
  ├─ WS /ws          → nginx → gateway-proxy → user's OpenClaw instance
  ├─ WS /terminal/   → nginx → terminal-proxy → docker exec openclaw CLI
  ├─ /supabase/auth/ → nginx → supabase-auth (GoTrue)
  └─ /keycloak/      → nginx → keycloak (SSO)

K8s variant:
  Browser → Ingress → nginx (same routing)
                    → gateway-proxy → orchestrator-managed OpenClaw pods`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Key Design Principles
        </h2>
        <ul className="space-y-3">
          {[
            "Per-user agent instances -- private memory and context, no cross-user leakage",
            "Empty shell philosophy -- the Flutter frontend renders only what the agent produces",
            "Self-hosted by default -- your data stays on your infrastructure, MIT licensed",
            "Multi-tenant orchestration -- gateway-orchestrator spins up/down OpenClaw pods per user in K8s",
            "Defense in depth -- Supabase JWT + Keycloak SSO + auth-service RBAC + terminal command tiers",
          ].map((principle) => (
            <li
              key={principle}
              className="flex items-start gap-3 rounded-lg border border-[#2a2a2a] bg-[#0a0a0a] p-4"
            >
              <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#6ee7b7]" />
              <span className="font-sans text-sm text-[#8b8b8b]">{principle}</span>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
