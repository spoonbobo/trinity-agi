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
          Connect to Trinity AGI through multiple interfaces.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Available Channels
        </h2>
        
        <div className="space-y-4">
          {[
            {
              name: "Web Shell",
              icon: "🌐",
              desc: "Browser-based chat interface. The primary way to interact with Trinity AGI.",
            },
            {
              name: "REST API",
              icon: "🔌",
              desc: "HTTP endpoints for programmatic access. Perfect for building custom integrations.",
            },
            {
              name: "WebSocket",
              icon: "⚡",
              desc: "Real-time bidirectional communication. Supports streaming responses.",
            },
            {
              name: "Telegram",
              icon: "✈️",
              desc: "Connect via Telegram bot. Bring the brain to your messaging app.",
            },
            {
              name: "Discord",
              icon: "🎮",
              desc: "Add Trinity AGI as a Discord bot. Works with your existing server.",
            },
          ].map((channel) => (
            <div
              key={channel.name}
              className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6"
            >
              <div className="flex items-center gap-3 mb-2">
                <span className="text-xl">{channel.icon}</span>
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
          Enabling Channels
        </h2>
        <p className="mb-6 font-sans text-sm text-[#8b8b8b]">
          Configure which channels to enable in your environment:
        </p>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# .env configuration
CHANNELS=web,api,websocket,telegram,discord

# Telegram bot
TELEGRAM_BOT_TOKEN=...

# Discord bot
DISCORD_BOT_TOKEN=...`}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
