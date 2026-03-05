export default function QuickStartPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GETTING STARTED
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Quick Start
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Get the full Trinity AGI stack running locally with Docker Compose.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Prerequisites
        </h2>
        <ul className="mb-8 list-disc space-y-2 pl-6 font-sans text-sm text-[#8b8b8b]">
          <li>Docker Engine 24+ and Docker Compose v2</li>
          <li>At least 8 GB RAM available for Docker</li>
          <li>An LLM API key (OpenAI, Anthropic, or any OpenAI-compatible endpoint)</li>
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          1. Clone and Configure
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`git clone https://github.com/spoonbobo/trinity-agi/
cd trinity-agi/web

# Copy the example env and fill in your secrets
cp .env.example .env

# Required variables in .env:
#   SUPABASE_POSTGRES_PASSWORD=<choose-a-password>
#   SUPABASE_JWT_SECRET=<generate-a-jwt-secret>
#   SUPABASE_ANON_KEY=<your-supabase-anon-key>
#   OPENCLAW_GATEWAY_TOKEN=<your-gateway-token>
#   KEYCLOAK_ADMIN_PASSWORD=<choose-a-password>
#   KEYCLOAK_CLIENT_SECRET=<generate-a-secret>`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          2. Build the Frontend
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Build the Flutter web shell (runs as a Docker build profile)
docker compose --profile build build frontend-builder
docker compose --profile build run --rm frontend-builder`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          3. Start the Stack
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`docker compose up -d

# This starts 14 services:
#   supabase-db, vault, supabase-auth, keycloak,
#   auth-service, openclaw-gateway, terminal-proxy,
#   nginx, grafana, loki, fluentd, and init jobs

# The web shell is available at:
#   http://localhost`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          4. First Login
        </h2>
        <p className="mb-4 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Open <code className="text-[#6ee7b7]">http://localhost</code> in your browser.
          You can log in with the default superadmin credentials:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`Email:    admin@trinity.local
Password: admin`}</code>
          </pre>
        </div>
        <p className="mt-4 font-sans text-sm text-[#8b8b8b]">
          Or click <strong>Continue as Guest</strong> to explore with read-only permissions.
        </p>
      </div>

      <div className="mt-12 rounded-xl border border-[#6ee7b7]/20 bg-[#0a1a10] p-6">
        <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
          NEXT STEPS
        </h3>
        <p className="font-sans text-sm text-[#8b8b8b]">
          Read the <a href="/docs/architecture" className="text-[#6ee7b7] underline">Architecture</a> guide
          to understand the service topology, or jump to{" "}
          <a href="/docs/configuration" className="text-[#6ee7b7] underline">Configuration</a> to
          customise secrets, RBAC, and LLM providers.
        </p>
      </div>
    </div>
  );
}
