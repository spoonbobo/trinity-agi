export default function TheBrainPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          CORE CONCEPTS
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          The Brain
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          The persistent memory system that makes collective intelligence possible.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          How It Works
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          The brain is a semantic memory store that accumulates knowledge from every user 
          interaction. When a user asks a question, the system searches the brain for 
          relevant context before generating a response.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Memory Structure
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <pre className="overflow-x-auto font-mono text-sm text-[#8b8b8b]">
            <code>{`{
  "id": "memory_001",
  "content": "User taught: the project uses TypeScript",
  "embedding": [0.12, -0.34, ...],
  "source": "conversation_2024_01_15",
  "timestamp": "2024-01-15T10:30:00Z",
  "importance": 0.8
}`}</code>
          </pre>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Operations
        </h2>
        <div className="space-y-4">
          {[
            { name: "Store", desc: "Save new knowledge from user interactions" },
            { name: "Retrieve", desc: "Find relevant memories using semantic search" },
            { name: "Update", desc: "Refine or merge similar memories" },
            { name: "Forget", desc: "Remove outdated or incorrect memories" },
          ].map((op) => (
            <div
              key={op.name}
              className="rounded-lg border border-[#2a2a2a] bg-[#141414] p-4"
            >
              <h3 className="mb-1 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
                {op.name.toUpperCase()}
              </h3>
              <p className="font-sans text-sm text-[#8b8b8b]">{op.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
