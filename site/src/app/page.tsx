"use client";

import { I18nProvider } from "@/i18n/context";
import Hero from "@/components/Hero";
import LangSwitch from "@/components/LangSwitch";

export default function Home() {
  return (
    <I18nProvider>
      <main>
        <Hero />
      </main>
      <LangSwitch />
    </I18nProvider>
  );
}
