"use client";

import { I18nProvider } from "@/i18n/context";
import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import HowItWorks from "@/components/HowItWorks";
import WhyItMatters from "@/components/WhyItMatters";
import Footer from "@/components/Footer";
import LangSwitch from "@/components/LangSwitch";

export default function Home() {
  return (
    <I18nProvider>
      <Navbar />
      <main>
        <Hero />
        <HowItWorks />
        <WhyItMatters />
      </main>
      <Footer />
      <LangSwitch />
    </I18nProvider>
  );
}
