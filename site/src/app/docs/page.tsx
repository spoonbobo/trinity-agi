import Link from "next/link";

export default function DocsPage() {
  return (
    <div className="prose prose-invert max-w-none">
      <div className="mb-8">
        <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6ee7b7]">
          DOCUMENTATION
        </span>
        <h1 className="mb-4 font-sans text-4xl font-bold tracking-tight text-[#e5e5e5]">
          Introduction
        </h1>
        <p className="font-sans text-lg text-[#8b8b8b]">
          Welcome to Trinity AGI documentation. One brain. Every user teaches it.
          Everyone benefits.
        </p>
      </div>

      <div className="mt-12 rounded-2xl border border-[#2a2a2a] bg-[#141414] p-8">
        <h2 className="mb-4 font-sans text-xl font-semibold text-[#e5e5e5]">
          What is Trinity AGI?
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Trinity AGI is a collective intelligence system where the screen is never blank because the 
          intelligence isn't. Every user interaction teaches the brain, and everyone benefits from 
          what any user teaches it.
        </p>
        <p className="font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Unlike traditional AI assistants that start fresh each session, Trinity AGI maintains a 
          persistent collective memory that grows smarter with every conversation.
        </p>
      </div>

      <div className="mt-12 grid gap-6 sm:grid-cols-2">
        <Link
          href="/docs/quick-start"
          className="group rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 transition hover:border-[#6ee7b7]/40"
        >
          <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
            QUICK START
          </h3>
          <p className="font-sans text-sm text-[#8b8b8b]">
            Get up and running in minutes with our quick start guide.
          </p>
        </Link>
        <Link
          href="/docs/installation"
          className="group rounded-xl border border-[#2a2a2a] bg-[#141414] p-6 transition hover:border-[#6ee7b7]/40"
        >
          <h3 className="mb-2 font-mono text-xs tracking-[2px] text-[#6ee7b7]">
            INSTALLATION
          </h3>
          <p className="font-sans text-sm text-[#8b8b8b]">
            Learn how to install and configure Trinity AGI.
          </p>
        </Link>
      </div>

      <div className="mt-16 border-t border-[#2a2a2a] pt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Key Features
        </h2>
        <ul className="space-y-4">
          {[
            {
              title: "Collective Memory",
              desc: "One brain that learns from every user interaction",
            },
            {
              title: "Self-Hosted",
              desc: "Run your own instance with full control over your data",
            },
            {
              title: "Multi-Channel",
              desc: "Connect via web shell, messaging platforms, or API",
            },
            {
              title: "Open Source",
              desc: "MIT licensed, transparent, and extensible",
            },
          ].map((feature) => (
            <li
              key={feature.title}
              className="flex items-start gap-4 rounded-lg border border-[#2a2a2a] bg-[#0a0a0a] p-4"
            >
              <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-[#6ee7b7]" />
              <div>
                <h3 className="font-sans font-medium text-[#e5e5e5]">{feature.title}</h3>
                <p className="font-sans text-sm text-[#6b6b6b]">{feature.desc}</p>
              </div>
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
