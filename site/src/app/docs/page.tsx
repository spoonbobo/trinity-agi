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
          Welcome to Trinity documentation. A featureless command center
          where AI agents build the interface on demand.
        </p>
      </div>

      <div className="mt-12 rounded-2xl border border-[#2a2a2a] bg-[#141414] p-8">
        <h2 className="mb-4 font-sans text-xl font-semibold text-[#e5e5e5]">
          What is Trinity?
        </h2>
        <p className="mb-6 font-sans text-sm leading-relaxed text-[#8b8b8b]">
          Trinity is a self-hosted AI platform built around the idea that software should not
          ship features &mdash; it should emerge them. You start with an empty screen, a prompt bar,
          and a per-user AI agent powered by{" "}
          <a href="https://docs.openclaw.ai" target="_blank" rel="noopener noreferrer" className="text-[#6ee7b7] underline">
            OpenClaw
          </a>
          . The agent generates interfaces, executes tasks, and learns from every interaction.
        </p>
        <p className="font-sans text-sm leading-relaxed text-[#8b8b8b]">
          The platform runs as a Docker Compose stack (or Kubernetes Helm chart) with
          a Flutter web shell, Go microservices for multi-tenant gateway orchestration, full RBAC,
          Supabase for auth and storage, Keycloak for SSO federation, knowledge-graph RAG, and
          Grafana/Loki for observability.
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
            Clone, configure secrets, and run the full stack with Docker Compose in minutes.
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
            Detailed requirements, Docker Compose setup, and Kubernetes (Helm) deployment.
          </p>
        </Link>
      </div>

      <div className="mt-16 border-t border-[#2a2a2a] pt-12">
        <h2 className="mb-6 font-sans text-2xl font-semibold text-[#e5e5e5]">
          Key Capabilities
        </h2>
        <ul className="space-y-4">
          {[
            {
              title: "Per-User AI Agent",
              desc: "Each user gets a dedicated OpenClaw instance with private memory and context, orchestrated on demand",
            },
            {
              title: "Canvas UI (A2UI)",
              desc: "Agents render real-time Flutter surfaces via the A2UI protocol -- dashboards, forms, tools -- all generated on the fly",
            },
            {
              title: "Multi-Channel",
              desc: "Connect via the web shell, WhatsApp, Telegram, Discord, or programmatic API -- all feeding the same agent",
            },
            {
              title: "Full RBAC",
              desc: "NIST-level role hierarchy (guest/user/admin/superadmin), 22 granular permissions, tiered terminal command access",
            },
            {
              title: "Self-Hosted",
              desc: "MIT licensed, runs on your infrastructure -- Docker Compose for dev, Helm chart for Kubernetes production",
            },
            {
              title: "Observability",
              desc: "Grafana dashboards, Loki log aggregation, and Fluentd collection built in from day one",
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
