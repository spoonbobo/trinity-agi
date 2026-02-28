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
          Understanding how Trinity AGI's collective intelligence works.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Overview
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Trinity AGI is built on a simple but powerful premise: the screen should never be blank 
          because the intelligence isn't. It maintains a persistent brain that accumulates knowledge 
          from every user interaction.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          System Components
        </h2>
        
        <div className="space-y-4">
          {[
            {
              title: "The Brain",
              desc: "A persistent memory system that stores learned information from all users. Uses semantic search to retrieve relevant context for each conversation.",
            },
            {
              title: "Channel Manager",
              desc: "Manages multiple interaction channels (web shell, messaging, API). Each channel routes requests to the brain and returns responses.",
            },
            {
              title: "Learning Engine",
              desc: "Processes user interactions and extracts knowledge to store in the brain. Handles deduplication and relevance scoring.",
            },
            {
              title: "LLM Gateway",
              desc: "Abstraction layer for connecting to language models. Supports OpenAI, Anthropic, and other compatible endpoints.",
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
          Data Flow
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`User Input → Channel → Context Retrieval
                           ↓
                     The Brain (semantic search)
                           ↓
                     LLM Gateway (with context)
                           ↓
                     Response → Channel → User

Follow-up: Learning Engine extracts
new knowledge → The Brain`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Key Design Principles
        </h2>
        <ul className="space-y-3">
          {[
            "One brain per instance - shared across all users",
            "Self-hosted by default - your data stays with you",
            "Transparent memory - you can inspect what the brain has learned",
            "Graceful degradation - works even without external API calls for cached knowledge",
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
