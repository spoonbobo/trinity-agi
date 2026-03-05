export default function TheBrainPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          CORE CONCEPTS
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          The Brain (OpenClaw)
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Each user gets a dedicated AI agent instance powered by OpenClaw &mdash;
          the engine behind chat, tool execution, memory, and A2UI surface generation.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          How It Works
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          OpenClaw is a full-featured AI gateway that manages sessions, tools, skills, cron jobs,
          hooks, and memory. In Docker Compose, a single shared instance runs on port 18789.
          In Kubernetes, the <strong>gateway-orchestrator</strong> provisions a dedicated OpenClaw pod
          per user, and the <strong>gateway-proxy</strong> routes each user&apos;s WebSocket connection
          to their specific instance.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Capabilities
        </h2>
        <div className="space-y-4">
          {[
            {
              name: "Chat & Streaming",
              desc: "Real-time conversational AI with streaming token delivery via WebSocket. Supports chat.send, chat.history, chat.abort.",
            },
            {
              name: "Tool Execution",
              desc: "Extensible tool system -- the agent can call external APIs, run code, browse the web, generate images, and more.",
            },
            {
              name: "A2UI Surface Generation",
              desc: "Agents produce JSONL-encoded A2UI surfaces (dashboards, forms, data views) that the Flutter shell renders in real time on the canvas.",
            },
            {
              name: "Memory",
              desc: "Persistent memory per agent instance. The agent remembers context across sessions. Inspectable via the Memory dialog in the shell.",
            },
            {
              name: "Skills",
              desc: "Installable skill packs that extend the agent's capabilities. Managed via the CLI (skills list, skills install) or the Skills dialog.",
            },
            {
              name: "Automations",
              desc: "Cron jobs (scheduled tasks), hooks (event-driven), webhooks (HTTP triggers), and polls (messaging channel interactions).",
            },
            {
              name: "Governance",
              desc: "High-risk actions trigger approval gates. The agent pauses and waits for human approval before executing sensitive operations.",
            },
          ].map((cap) => (
            <div
              key={cap.name}
              className="rounded-lg border border-[#2a2a2a] bg-[#141414] p-4"
            >
              <h3 className="mb-1 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
                {cap.name.toUpperCase()}
              </h3>
              <p className="font-sans text-sm text-[#8b8b8b]">{cap.desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          WebSocket Protocol
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Connection handshake (via /ws)
1. Server → connect.challenge (nonce)
2. Client → connect (token, device, scopes)
3. Server → hello-ok

# Key methods (client → server)
chat.send, chat.history, chat.abort,
exec.approval.resolve, status, health,
sessions.list, tools.catalog

# Key events (server → client)
chat (delta/final), agent (lifecycle/tool_call/tool_result),
exec.approval.requested`}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
