"use client";

import { useState } from "react";

export default function Navbar() {
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-[#2a2a2a] bg-[#0a0a0a]/90 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <a href="#" className="flex items-center gap-2 font-mono text-sm tracking-widest text-[#6ee7b7]">
          <span className="inline-block h-2 w-2 rounded-full bg-[#6ee7b7]" />
          TRINITY
        </a>

        <div className="hidden items-center gap-8 md:flex">
          <a href="#how" className="font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:text-[#e5e5e5]">
            HOW IT WORKS
          </a>
          <a href="/docs" className="font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:text-[#e5e5e5]">
            DOCS
          </a>
          <a
            href="https://github.com/spoonbobo/trinity/"
            target="_blank"
            rel="noopener noreferrer"
            className="font-mono text-xs tracking-wide text-[#6b6b6b] transition hover:text-[#e5e5e5]"
          >
            GITHUB
          </a>
          <a
            href="/docs"
            className="rounded-lg border border-[#6ee7b7] bg-[#6ee7b7]/10 px-4 py-1.5 font-mono text-xs tracking-wide text-[#6ee7b7] transition hover:bg-[#6ee7b7]/20"
          >
            GET STARTED
          </a>
        </div>

        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          className="flex h-8 w-8 items-center justify-center rounded md:hidden"
          aria-label="Toggle menu"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
            {mobileOpen ? (
              <path d="M4 4L14 14M14 4L4 14" stroke="#6ee7b7" strokeWidth="1.5" />
            ) : (
              <>
                <path d="M2 5H16" stroke="#6b6b6b" strokeWidth="1.5" />
                <path d="M2 9H16" stroke="#6b6b6b" strokeWidth="1.5" />
                <path d="M2 13H16" stroke="#6b6b6b" strokeWidth="1.5" />
              </>
            )}
          </svg>
        </button>
      </div>

      {mobileOpen && (
        <div className="border-t border-[#2a2a2a] bg-[#0a0a0a] px-6 py-4 md:hidden">
          <div className="flex flex-col gap-4">
            <a href="#how" onClick={() => setMobileOpen(false)} className="font-mono text-xs tracking-wide text-[#6b6b6b]">HOW IT WORKS</a>
            <a href="/docs" onClick={() => setMobileOpen(false)} className="font-mono text-xs tracking-wide text-[#6b6b6b]">DOCS</a>
            <a href="https://github.com/spoonbobo/trinity/" target="_blank" rel="noopener noreferrer" className="font-mono text-xs tracking-wide text-[#6b6b6b]">GITHUB</a>
            <a href="/docs" onClick={() => setMobileOpen(false)} className="rounded-lg border border-[#6ee7b7] bg-[#6ee7b7]/10 px-4 py-2 text-center font-mono text-xs tracking-wide text-[#6ee7b7]">GET STARTED</a>
          </div>
        </div>
      )}
    </nav>
  );
}
