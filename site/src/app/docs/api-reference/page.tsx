export default function APIReferencePage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GUIDES
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          API Reference
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Endpoints exposed by the Trinity AGI stack via nginx.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Auth Service
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          All auth endpoints are at <code className="text-[#6ee7b7]">/auth/</code>,
          proxied to the auth-service on port 18791.
        </p>
        <div className="space-y-4">
          {[
            { method: "GET", path: "/auth/health", auth: "none", desc: "Health check" },
            { method: "GET", path: "/auth/me", auth: "Bearer JWT", desc: "Current user info, role, and permissions" },
            { method: "GET", path: "/auth/permissions", auth: "Bearer JWT", desc: "Flat list of user's effective permissions" },
            { method: "POST", path: "/auth/session", auth: "Bearer JWT", desc: "Exchange JWT for a gateway session token" },
            { method: "POST", path: "/auth/guest", auth: "none", desc: "Issue a guest JWT (1hr, role=guest, safe permissions)" },
            { method: "GET", path: "/auth/users", auth: "users.list", desc: "List all users with roles" },
            { method: "POST", path: "/auth/users/:id/role", auth: "users.manage", desc: "Assign role (guest/user/admin)" },
            { method: "GET", path: "/auth/users/audit", auth: "audit.read", desc: "Paginated audit log" },
            { method: "GET", path: "/auth/users/roles/permissions", auth: "users.list", desc: "Full role-permission matrix" },
            { method: "PUT", path: "/auth/users/roles/:role/permissions", auth: "users.manage", desc: "Update role permissions" },
          ].map((ep) => (
            <div key={ep.path + ep.method} className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-4">
              <div className="mb-2 flex items-center gap-3">
                <span className={`rounded px-2 py-0.5 font-mono text-xs ${
                  ep.method === "POST" ? "bg-[#3b82f6]/20 text-[#3b82f6]" :
                  ep.method === "PUT" ? "bg-[#fbbf24]/20 text-[#fbbf24]" :
                  "bg-[#6ee7b7]/20 text-[#6ee7b7]"
                }`}>
                  {ep.method}
                </span>
                <code className="font-mono text-sm text-[#e5e5e5]">{ep.path}</code>
                <span className="ml-auto font-mono text-[10px] text-[#3a3a3a]">{ep.auth}</span>
              </div>
              <p className="font-sans text-sm text-[#8b8b8b]">{ep.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          OpenClaw Gateway
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          The AI gateway is accessed primarily via WebSocket at{" "}
          <code className="text-[#6ee7b7]">/ws</code>. HTTP endpoints are also available:
        </p>
        <div className="space-y-4">
          {[
            { method: "WS", path: "/ws", desc: "Primary WebSocket -- chat, tools, A2UI, governance" },
            { method: "GET", path: "/__openclaw__/health", desc: "Gateway health check" },
            { method: "GET", path: "/__openclaw__/status", desc: "Gateway status (sessions, uptime)" },
            { method: "ANY", path: "/v1/chat/completions", desc: "OpenAI-compatible chat completions API" },
            { method: "GET", path: "/tools/catalog", desc: "List available tools" },
            { method: "POST", path: "/__openclaw__/webhook/wake", desc: "Wake the agent with a message" },
            { method: "POST", path: "/__openclaw__/webhook/agent", desc: "Send directly to agent" },
          ].map((ep) => (
            <div key={ep.path} className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-4">
              <div className="mb-2 flex items-center gap-3">
                <span className={`rounded px-2 py-0.5 font-mono text-xs ${
                  ep.method === "WS" ? "bg-[#a78bfa]/20 text-[#a78bfa]" :
                  ep.method === "POST" ? "bg-[#3b82f6]/20 text-[#3b82f6]" :
                  "bg-[#6ee7b7]/20 text-[#6ee7b7]"
                }`}>
                  {ep.method}
                </span>
                <code className="font-mono text-sm text-[#e5e5e5]">{ep.path}</code>
              </div>
              <p className="font-sans text-sm text-[#8b8b8b]">{ep.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Terminal Proxy
        </h2>
        <p className="mb-4 font-sans text-sm text-[#8b8b8b]">
          WebSocket endpoint at <code className="text-[#6ee7b7]">/terminal/</code> for
          executing OpenClaw CLI commands with RBAC tier gating.
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Client messages
{ type: "auth",   token, role }
{ type: "exec",   command }
{ type: "cancel" }

# Server messages
{ type: "auth",   status: "ok" | "error" }
{ type: "stdout", data }
{ type: "stderr", data }
{ type: "exit",   code }

# Command tiers (RBAC)
safe:       status, health, models, skills list, crons list
standard:   doctor, skills, cron, hooks, sessions, logs, memory
privileged: doctor --fix, configure, onboard, dashboard, config set`}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
