export default function ChannelsPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          CORE CONCEPTS
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Channels
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Multiple interfaces feed the same agent &mdash; web shell, messaging platforms, and API.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Available Channels
        </h2>
        <div className="space-y-4">
          {[
            {
              name: "Web Shell (Flutter)",
              icon: "~",
              desc: "The primary interface. A blank canvas with a prompt bar, chat stream, A2UI canvas panel, session management, command palette (Ctrl+K), and admin panel. Connects to the agent via WebSocket.",
            },
            {
              name: "WebSocket API",
              icon: ">",
              desc: "Direct WebSocket connection to the OpenClaw gateway on /ws. Supports the full protocol: chat, tool execution, streaming, A2UI surfaces, governance approvals.",
            },
            {
              name: "REST / OpenAI-compatible API",
              icon: "/",
              desc: "HTTP endpoints at /v1/ provide OpenAI-compatible chat completions. Use any OpenAI SDK or HTTP client to interact with the agent programmatically.",
            },
            {
              name: "Terminal Proxy",
              icon: "$",
              desc: "WebSocket bridge at /terminal/ for executing OpenClaw CLI commands. Supports status, doctor, config, skills, cron, hooks, and more -- with RBAC tier gating.",
            },
            {
              name: "Webhooks",
              icon: "!",
              desc: "HTTP endpoints that external services can call to trigger agent actions. Wake endpoint (POST /__openclaw__/webhook/wake), agent endpoint, and custom mapped webhooks.",
            },
            {
              name: "Messaging Platforms",
              icon: "@",
              desc: "WhatsApp, Telegram, Discord -- connect via OpenClaw channel skills. All messaging feeds the same agent brain. Supports polls and interactive messages.",
            },
          ].map((channel) => (
            <div
              key={channel.name}
              className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6"
            >
              <div className="mb-2 flex items-center gap-3">
                <span className="flex h-8 w-8 items-center justify-center rounded border border-[#2a2a2a] bg-[#0a0a0a] font-mono text-sm text-[#6ee7b7]">
                  {channel.icon}
                </span>
                <h3 className="font-mono text-xs tracking-[2px] text-[#6ee7b7]">
                  {channel.name.toUpperCase()}
                </h3>
              </div>
              <p className="font-sans text-sm text-[#8b8b8b]">{channel.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Nginx Route Map
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 overflow-x-auto">
          <table className="w-full font-mono text-xs text-[#8b8b8b]">
            <thead>
              <tr className="border-b border-[#2a2a2a] text-left text-[#6ee7b7]">
                <th className="pb-3 pr-4">Route</th>
                <th className="pb-3 pr-4">Backend</th>
                <th className="pb-3">Protocol</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#1a1a1a]">
              {[
                ["/", "Flutter SPA (static)", "HTTP"],
                ["/ws", "OpenClaw gateway", "WebSocket"],
                ["/terminal/", "terminal-proxy", "WebSocket"],
                ["/auth/", "auth-service", "HTTP"],
                ["/supabase/auth/", "supabase-auth (GoTrue)", "HTTP"],
                ["/keycloak/", "keycloak", "HTTP"],
                ["/__openclaw__/", "OpenClaw gateway", "HTTP/WS"],
                ["/v1/", "OpenClaw gateway", "HTTP"],
                ["/tools/", "OpenClaw gateway", "HTTP"],
              ].map(([route, backend, proto]) => (
                <tr key={route}>
                  <td className="py-2 pr-4 text-[#e5e5e5]">{route}</td>
                  <td className="py-2 pr-4">{backend}</td>
                  <td className="py-2">{proto}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
