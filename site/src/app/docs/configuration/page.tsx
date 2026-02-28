export default function ConfigurationPage() {
  return (
    <div className="prose prose-inverse max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          GUIDES
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Configuration
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Customize Trinity AGI to fit your needs.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Environment Variables
        </h2>
        
        <div className="space-y-6">
          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
              REQUIRED
            </h3>
            <div className="font-mono text-sm text-[#e5e5e5]">OPENAI_API_KEY</div>
            <p className="mt-1 font-sans text-xs text-[#6b6b6b]">
              Your OpenAI API key for LLM access
            </p>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
              SERVER
            </h3>
            <div className="space-y-3">
              <div>
                <div className="font-mono text-sm text-[#e5e5e5]">PORT</div>
                <p className="font-sans text-xs text-[#6b6b6b]">Default: 3000</p>
              </div>
              <div>
                <div className="font-mono text-sm text-[#e5e5e5]">LOG_LEVEL</div>
                <p className="font-sans text-xs text-[#6b6b6b]">Options: debug, info, warn, error. Default: info</p>
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
              CHANNELS
            </h3>
            <div className="space-y-3">
              <div>
                <div className="font-mono text-sm text-[#e5e5e5]">CHANNELS</div>
                <p className="font-sans text-xs text-[#6b6b6b]">Comma-separated: web,api,websocket,telegram,discord</p>
              </div>
            </div>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
              MEMORY
            </h3>
            <div className="space-y-3">
              <div>
                <div className="font-mono text-sm text-[#e5e5e5]">MEMORY_PATH</div>
                <p className="font-sans text-xs text-[#6b6b6b]">Path to memory storage. Default: ./data/memory.json</p>
              </div>
              <div>
                <div className="font-mono text-sm text-[#e5e5e5]">MAX_MEMORIES</div>
                <p className="font-sans text-xs text-[#6b6b6b]">Maximum memories to store. Default: 10000</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Model Configuration
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`# Use a different model
LLM_MODEL=gpt-4

# Custom endpoint (for Azure OpenAI, local models, etc.)
LLM_BASE_URL=https://api.openai.com/v1
LLM_API_KEY=...

# Configure model parameters
LLM_TEMPERATURE=0.7
LLM_MAX_TOKENS=2000`}</code>
          </pre>
        </div>
      </div>
    </div>
  );
}
