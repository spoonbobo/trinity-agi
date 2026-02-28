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
          Run Trinity AGI on your own infrastructure for full control.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Why Self-Host?
        </h2>
        <ul className="space-y-3 mb-8">
          {[
            "Complete data privacy - your conversations never leave your infrastructure",
            "Full control over the brain - inspect, modify, or reset memory",
            "No usage limits - unlimited agent turns",
            "Custom integrations - modify the code to fit your needs",
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
          Docker Compose Setup
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 overflow-x-auto">
          <code className="font-mono text-sm text-[#8b8b8b] whitespace-pre"># docker-compose.yml
version: '3.8'
services:
  trinity:
    image: spoonbobo/trinity-agi:latest
    ports:
      - "3000:3000"
    environment:
      - OPENAI_API_KEY={"${"}OPENAI_API_KEY}
      - LOG_LEVEL=info
    volumes:
      - ./data:/app/data
    restart: unless-stopped</code>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Production Considerations
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <ul className="space-y-3 font-sans text-sm text-[#8b8b8b]">
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">→</span>
              Use a reverse proxy (nginx, caddy) for TLS
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">→</span>
              Set up regular backups of /app/data
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">→</span>
              Monitor memory usage for large brains
            </li>
            <li className="flex items-center gap-3">
              <span className="font-mono text-[#6ee7b7]">→</span>
              Consider rate limiting the API endpoint
            </li>
          </ul>
        </div>
      </div>
    </div>
  );
}
