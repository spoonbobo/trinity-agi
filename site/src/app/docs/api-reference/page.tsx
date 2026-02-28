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
          Programmatic access to Trinity AGI.
        </p>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Base URL
        </h2>
        <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
          <code className="font-mono text-sm text-[#6ee7b7]">http://localhost:3000/api</code>
        </div>
      </div>

      <div className="mt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Endpoints
        </h2>

        <div className="space-y-8">
          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <div className="flex items-center gap-3 mb-4">
              <span className="rounded bg-[#6ee7b7]/20 px-2 py-1 font-mono text-xs text-[#6ee7b7]">POST</span>
              <code className="font-mono text-sm text-[#e5e5e5]">/chat</code>
            </div>
            <p className="mb-4 font-sans text-sm text-[#8b8b8b]">Send a message to the brain.</p>
            <pre className="overflow-x-auto font-mono text-xs text-[#6b6b6b]">
              <code>{`// Request
{ "message": "Hello, what do you know about me?" }

// Response
{ "response": "Based on our conversations...", "memory_used": 3 }`}</code>
            </pre>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <div className="flex items-center gap-3 mb-4">
              <span className="rounded bg-[#6ee7b7]/20 px-2 py-1 font-mono text-xs text-[#6ee7b7]">GET</span>
              <code className="font-mono text-sm text-[#e5e5e5]">/brain</code>
            </div>
            <p className="mb-4 font-sans text-sm text-[#8b8b8b]">Get all memories from the brain.</p>
            <pre className="overflow-x-auto font-mono text-xs text-[#6b6b6b]">
              <code>{`// Response
{
  "memories": [
    { "id": "1", "content": "...", "importance": 0.8 }
  ],
  "total": 42
}`}</code>
            </pre>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <div className="flex items-center gap-3 mb-4">
              <span className="rounded bg-[#ef4444]/20 px-2 py-1 font-mono text-xs text-[#ef4444]">DELETE</span>
              <code className="font-mono text-sm text-[#e5e5e5]">/brain/:id</code>
            </div>
            <p className="mb-4 font-sans text-sm text-[#8b8b8b]">Delete a specific memory.</p>
          </div>

          <div className="rounded-xl border border-[#2a2a2a] bg-[#141414] p-6">
            <div className="flex items-center gap-3 mb-4">
              <span className="rounded bg-[#6ee7b7]/20 px-2 py-1 font-mono text-xs text-[#6ee7b7]">GET</span>
              <code className="font-mono text-sm text-[#e5e5e5]">/health</code>
            </div>
            <p className="mb-4 font-sans text-sm text-[#8b8b8b]">Check service health.</p>
            <pre className="overflow-x-auto font-mono text-xs text-[#6b6b6b]">
              <code>{`// Response
{ "status": "healthy", "version": "0.1.0" }`}</code>
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
}
