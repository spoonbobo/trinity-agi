import Link from "next/link";
import { docsConfig } from "@/data/docs-config";

export default function DocsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="min-h-screen bg-[#0a0a0a]">
      <header className="sticky top-0 z-40 border-b border-[#2a2a2a] bg-[#0a0a0a]/95 backdrop-blur">
        <div className="mx-auto flex h-14 max-w-7xl items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-2 font-mono text-sm tracking-widest text-[#6ee7b7]">
            <span className="inline-block h-2 w-2 rounded-full bg-[#6ee7b7]" />
            TRINITY AGI
          </Link>
          <nav className="flex items-center gap-6">
            <Link href="/" className="font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:text-[#e5e5e5]">
              HOME
            </Link>
            <a
              href="https://github.com/spoonbobo/trinity-agi/"
              target="_blank"
              rel="noopener noreferrer"
              className="font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:text-[#e5e5e5]"
            >
              GITHUB
            </a>
          </nav>
        </div>
      </header>

      <div className="mx-auto max-w-7xl lg:flex">
        <aside className="hidden w-64 flex-col border-r border-[#2a2a2a] py-8 lg:flex">
          <nav className="space-y-8 px-6">
            {docsConfig.nav.map((section) => (
              <div key={section.title}>
                <h4 className="mb-3 font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
                  {section.title}
                </h4>
                <ul className="space-y-1">
                  {section.items.map((item) => (
                    <li key={item.href}>
                      <Link
                        href={item.href}
                        className="block font-sans text-sm text-[#8b8b8b] transition hover:text-[#e5e5e5]"
                      >
                        {item.title}
                      </Link>
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </nav>
        </aside>

        <main className="flex-1 px-6 py-8 lg:px-12">
          <div className="mx-auto max-w-3xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
