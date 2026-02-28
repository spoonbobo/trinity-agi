export default function Footer() {
  return (
    <footer className="border-t border-[#2a2a2a] px-6 py-16">
      <div className="mx-auto max-w-5xl">
        <div className="grid gap-12 sm:grid-cols-4">
          {/* Brand */}
          <div className="sm:col-span-2">
            <div className="mb-4 flex items-center gap-2 font-mono text-sm tracking-widest text-[#6ee7b7]">
              <span className="inline-block h-2 w-2 rounded-full bg-[#6ee7b7]" />
              TRINITY AGI
            </div>
            <p className="max-w-xs font-sans text-sm leading-relaxed text-[#6b6b6b]">
              One brain. Every user teaches it. Everyone benefits.
              The screen is blank because the intelligence isn&apos;t.
            </p>
            <div className="mt-6 flex items-center gap-3">
              <a
                href="https://github.com/spoonbobo/trinity-agi/"
                target="_blank"
                rel="noopener noreferrer"
                className="flex h-8 w-8 items-center justify-center rounded-lg border border-[#2a2a2a] bg-[#141414] transition hover:border-[#3a3a3a]"
                aria-label="GitHub"
              >
                <svg width="16" height="16" viewBox="0 0 16 16" fill="#6b6b6b">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
                </svg>
              </a>
              <span className="rounded-full border border-[#2a2a2a] bg-[#141414] px-3 py-1 font-mono text-[9px] tracking-widest text-[#3a3a3a]">
                MIT LICENSE
              </span>
            </div>
          </div>

          {/* Links */}
          <div>
            <h4 className="mb-4 font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
              PRODUCT
            </h4>
            <ul className="space-y-2">
              <li>
                <a href="#how" className="font-sans text-sm text-[#6b6b6b] transition hover:text-[#e5e5e5]">
                  How It Works
                </a>
              </li>
              <li>
                <a href="/docs" className="font-sans text-sm text-[#6b6b6b] transition hover:text-[#e5e5e5]">
                  Documentation
                </a>
              </li>
              <li>
                <a href="https://docs.openclaw.ai" target="_blank" rel="noopener noreferrer" className="font-sans text-sm text-[#6b6b6b] transition hover:text-[#e5e5e5]">
                  OpenClaw Docs
                </a>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="mb-4 font-mono text-[10px] tracking-[2px] text-[#6b6b6b]">
              LEGAL
            </h4>
            <ul className="space-y-2">
              <li>
                <a href="#" className="font-sans text-sm text-[#6b6b6b] transition hover:text-[#e5e5e5]">
                  Privacy
                </a>
              </li>
              <li>
                <a href="#" className="font-sans text-sm text-[#6b6b6b] transition hover:text-[#e5e5e5]">
                  Terms
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-12 border-t border-[#1a1a1a] pt-6">
          <p className="font-mono text-[10px] tracking-wide text-[#2a2a2a]">
            &copy; {new Date().getFullYear()} TRINITY AGI. ONE BRAIN. NO
            FEATURES. INFINITE POTENTIAL.
          </p>
        </div>
      </div>
    </footer>
  );
}
