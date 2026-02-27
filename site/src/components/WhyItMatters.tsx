"use client";

import { useI18n } from "@/i18n/context";

export default function WhyItMatters() {
  const { t } = useI18n();

  return (
    <section id="why" className="border-t border-[#2a2a2a] px-6 py-24 sm:py-32">
      <div className="mx-auto max-w-5xl">
        <div className="mb-16 text-center">
          <span className="mb-4 inline-block font-mono text-[10px] tracking-[3px] text-[#6b6b6b]">
            {t.why.label}
          </span>
          <h2 className="font-sans text-3xl font-bold tracking-tight sm:text-4xl">
            {t.why.h2a} <span className="text-[#6ee7b7]">{t.why.h2b}</span>
          </h2>
          <p className="mx-auto mt-4 max-w-2xl font-sans text-sm leading-relaxed text-[#6b6b6b]">
            {t.why.subtitle}
          </p>
        </div>

        <div className="grid gap-6 sm:grid-cols-2">
          {t.why.cards.map((card, i) => (
            <div
              key={i}
              className="group rounded-2xl border border-[#2a2a2a] bg-[#141414] p-8 transition hover:border-[#3a3a3a] hover:bg-[#1a1a1a]"
            >
              <div className="mb-4 flex items-center gap-3">
                <span className="flex h-10 w-10 items-center justify-center rounded-xl border border-[#2a2a2a] bg-[#0a0a0a] text-lg">
                  {card.icon}
                </span>
                <h3 className="font-sans text-base font-semibold">
                  {card.title}
                </h3>
              </div>
              <p className="font-sans text-sm leading-relaxed text-[#6b6b6b]">
                {card.desc}
              </p>
            </div>
          ))}
        </div>

        <div className="mt-16 rounded-2xl border border-[#2a2a2a] bg-[#0f0f0f] p-8 text-center sm:p-12">
          <p className="mx-auto max-w-2xl font-sans text-lg leading-relaxed text-[#8b8b8b]">
            {t.why.quote}
          </p>
        </div>
      </div>
    </section>
  );
}
