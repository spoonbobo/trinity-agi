// @ts-nocheck
// Pricing component is not currently rendered on the landing page.
// Kept for potential future use.
"use client";

import { useI18n } from "@/i18n/context";

const CTA_STYLES = [
  "border border-[#2a2a2a] bg-[#141414] text-[#e5e5e5] hover:bg-[#1a1a1a]",
  "bg-[#6ee7b7] text-[#0a0a0a] hover:bg-[#5dd4a6]",
  "border border-[#3b82f6] bg-[#3b82f6]/10 text-[#3b82f6] hover:bg-[#3b82f6]/20",
  "border border-[#2a2a2a] bg-[#141414] text-[#e5e5e5] hover:bg-[#1a1a1a]",
];

const HIGHLIGHTS = [false, true, false, false];

export default function Pricing() {
  const { t } = useI18n();

  return (
    <section id="pricing" className="border-t border-[#2a2a2a] px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl">
        <div className="mb-16 text-center">
          <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6b6b6b]">
            {t.pricing.label}
          </span>
          <h2 className="font-sans text-3xl font-bold tracking-tight sm:text-4xl">
            {t.pricing.h2a} <span className="text-[#6ee7b7]">{t.pricing.h2b}</span>
          </h2>
          <p className="mx-auto mt-4 max-w-xl font-sans text-sm text-[#6b6b6b]">
            {t.pricing.subtitle}
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
          {t.pricing.tiers.map((tier, i) => (
            <div
              key={tier.name}
              className={`relative flex flex-col rounded-2xl border p-6 transition ${
                HIGHLIGHTS[i]
                  ? "border-[#6ee7b7]/40 bg-[#0a1a10]"
                  : "border-[#2a2a2a] bg-[#141414] hover:border-[#3a3a3a]"
              }`}
            >
              {HIGHLIGHTS[i] && (
                <span className="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-[#6ee7b7] px-3 py-0.5 font-mono text-[9px] font-bold tracking-widest text-[#0a0a0a]">
                  POPULAR
                </span>
              )}

              <div className="mb-4">
                <h3 className="font-mono text-xs tracking-[2px] text-[#6b6b6b]">
                  {tier.name.toUpperCase()}
                </h3>
              </div>

              <div className="mb-2 flex items-baseline gap-1">
                <span className="font-sans text-3xl font-bold">{tier.price}</span>
                {tier.period !== "forever" && tier.period !== "\u6c38\u4e45" && (
                  <span className="font-sans text-sm text-[#6b6b6b]">
                    {tier.period}
                  </span>
                )}
              </div>

              <p className="mb-6 font-sans text-xs text-[#6b6b6b]">{tier.desc}</p>

              <ul className="mb-8 flex-1 space-y-3">
                {tier.features.map((f) => (
                  <li key={f} className="flex items-start gap-2 text-sm">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 16 16"
                      fill="none"
                      className="mt-0.5 shrink-0"
                    >
                      <path
                        d="M4 8L7 11L12 5"
                        stroke={HIGHLIGHTS[i] ? "#6ee7b7" : "#3a3a3a"}
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      />
                    </svg>
                    <span className="font-sans text-[#8b8b8b]">{f}</span>
                  </li>
                ))}
              </ul>

              <a
                href="#"
                className={`block rounded-xl py-2.5 text-center font-mono text-xs tracking-wide transition ${CTA_STYLES[i]}`}
              >
                {tier.cta}
              </a>
            </div>
          ))}
        </div>

        <p className="mt-8 text-center font-mono text-[10px] tracking-wide text-[#3a3a3a]">
          {t.pricing.footnote}
        </p>
      </div>
    </section>
  );
}
