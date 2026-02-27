"use client";

import { createContext, useContext, useState, useEffect, useCallback } from "react";
import { translations, type Locale } from "./translations";

type I18nContextValue = {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: (typeof translations)["en"];
};

const I18nContext = createContext<I18nContextValue | null>(null);

function detectLocale(): Locale {
  if (typeof window === "undefined") return "en";
  const saved = localStorage.getItem("locale");
  if (saved && saved in translations) return saved as Locale;
  const lang = navigator.language;
  if (lang.startsWith("zh")) {
    const region = lang.toLowerCase();
    if (region === "zh-tw" || region === "zh-hk" || region === "zh-mo")
      return "zh-TW";
    return "zh-CN";
  }
  return "en";
}

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>("en");
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setLocaleState(detectLocale());
    setMounted(true);
  }, []);

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l);
    localStorage.setItem("locale", l);
    document.documentElement.lang = l;
  }, []);

  if (!mounted) return null;

  return (
    <I18nContext.Provider value={{ locale, setLocale, t: translations[locale] }}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  const ctx = useContext(I18nContext);
  if (!ctx) throw new Error("useI18n must be used within I18nProvider");
  return ctx;
}
