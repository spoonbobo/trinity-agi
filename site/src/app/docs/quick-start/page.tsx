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
          Get Trinity AGI running in under 5 minutes.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Prerequisites
        </h2>
        <ul className="mb-8 list-disc space-y-2 pl-6 font-sans text-sm text-[#8b8b8b]">
          <li>Node.js 18+ installed</li>
          <li>Docker (for containerized deployment)</li>
          <li>OpenAI API key or compatible LLM endpoint</li>
        </ul>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Option 1: Docker
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Clone the repository
git clone https://github.com/spoonbobo/trinity-agi/
cd trinity-agi

# Start with Docker
docker-compose up -d

# Access the web shell
# Open http://localhost:3000`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Option 2: Local Development
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Clone and install
git clone https://github.com/spoonbobo/trinity-agi/
cd trinity-agi

# Install dependencies
npm install

# Set up environment
cp .env.example .env
# Edit .env with your API keys

# Run the development server
cd site && npm run dev`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Environment Variables
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Required
OPENAI_API_KEY=sk-...

# Optional (defaults shown)
PORT=3000
LOG_LEVEL=info
MEMORY_PATH=./data/memory.json`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12 rounded-xl border border-[#6ee7b7]/20 bg-[#0a1a10] p-6">
        <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
          NEXT STEPS
        </h3>
        <p className="font-sans text-sm text-[#8b8b8b]">
          Head to the <a href="/docs/architecture" className="text-[#6ee7b7] underline">Architecture</a> guide to understand how Trinity AGI works, 
          or check out the <a href="/docs/configuration" className="text-[#6ee7b7] underline">Configuration</a> options to customize your instance.
        </p>
      </div>
    </div>
  );
}
