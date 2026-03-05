export const locales = ["en", "zh-TW", "zh-CN"] as const;
export type Locale = (typeof locales)[number];

export const localeLabels: Record<Locale, string> = {
  en: "EN",
  "zh-TW": "\u7e41\u9ad4",
  "zh-CN": "\u7b80\u4f53",
};

type Pillar = { icon: string; label: string; desc: string };
type Step = { num: string; title: string; desc: string };
type Arch = { label: string; detail: string };
type Card = { icon: string; title: string; desc: string };

type TranslationStrings = {
  hero: {
    h1a: string;
    h1b: string;
    desc: string;
    cta: string;
    tagline: string;
    pillars: Pillar[];
  };
  how: {
    label: string;
    h2a: string;
    h2b: string;
    steps: Step[];
    archLabel: string;
    arch: Arch[];
  };
  why: {
    label: string;
    h2a: string;
    h2b: string;
    subtitle: string;
    cards: Card[];
    quote: string;
  };
};

export const translations: Record<Locale, TranslationStrings> = {
  en: {
    hero: {
      h1a: "Nothing ships.",
      h1b: "Everything emerges.",
      desc: "A blank screen. One shared intelligence for your team. Every person who connects teaches it something new \u2014 and it builds what anyone needs, the moment they ask.",
      cta: "SEE HOW IT WORKS",
      tagline: "PRIVATE CONVERSATIONS. COLLECTIVE INTELLIGENCE.",
      pillars: [
        {
          icon: "\u25A1",
          label: "EMPTY BY DESIGN",
          desc: "No dashboards. No menus. The blank canvas is the product. The agent renders what you need, when you need it.",
        },
        {
          icon: "\u2666",
          label: "REAL UI, NOT TEXT",
          desc: "The agent doesn\u2019t just type back. It generates live, interactive interfaces on the canvas \u2014 forms, dashboards, data views \u2014 in real time.",
        },
        {
          icon: "\u2731",
          label: "SMARTER WITH EVERY USER",
          desc: "Every team member\u2019s conversation makes the agent sharper. Shared memory, shared skills, shared context \u2014 one brain that compounds.",
        },
      ],
    },
    how: {
      label: "HOW IT WORKS",
      h2a: "One intelligence.",
      h2b: "Many minds.",
      steps: [
        {
          num: "01",
          title: "You open a blank screen.",
          desc: "No dashboard. No sidebar. No onboarding wizard. Just a dark canvas and a prompt bar. The emptiness is the point.",
        },
        {
          num: "02",
          title: "You speak. It materializes.",
          desc: "Ask for anything \u2014 a tracker, a workflow, a tool. The agent renders real interactive widgets on the canvas. Not screenshots. Not markdown. Live, working interfaces you can click, fill in, and export.",
        },
        {
          num: "03",
          title: "Everyone feeds the same brain.",
          desc: "Every team member has private conversations. But the knowledge \u2014 memory, skills, decisions \u2014 accumulates in one place. The more people use it, the smarter it gets for everyone.",
        },
      ],
      archLabel: "ARCHITECTURE",
      arch: [
        {
          label: "Shared Team Brain",
          detail: "One agent per team \u2014 persistent memory, skills, and automations that grow with every conversation from every member",
        },
        {
          label: "Interactive Canvas",
          detail: "Agent-generated interfaces rendered in real time \u2014 forms, dashboards, code editors, interactive data views",
        },
        {
          label: "Any Channel In",
          detail: "Web shell, WhatsApp, Telegram, Discord, Slack \u2014 all feeding the same brain",
        },
      ],
    },
    why: {
      label: "WHY IT MATTERS",
      h2a: "Every fixed product is",
      h2b: "a cage.",
      subtitle: "Software today is someone else\u2019s opinion of what you need, frozen in code, behind a subscription. Trinity flips that entirely.",
      cards: [
        {
          icon: "\u2716",
          title: "Kills the feature roadmap",
          desc: "No team debates what to build next. Every user gets a different workspace shaped by their own needs. There\u2019s no one-size-fits-all because there\u2019s no fixed mold at all.",
        },
        {
          icon: "\u2261",
          title: "Replaces your tool stack",
          desc: "WhatsApp, Notion, GitHub, Slack, Telegram, image generation, browser automation, web search, document processing \u2014 a growing library of skills. Every tool is a prompt away.",
        },
        {
          icon: "\u25A0",
          title: "A canvas, not a chatbox",
          desc: "The agent doesn\u2019t just type back. It renders live, interactive interfaces \u2014 dashboards, forms, code editors, tabs \u2014 right in the browser. Real widgets you can click, fill in, and export.",
        },
        {
          icon: "\u2690",
          title: "Collective knowledge",
          desc: "Every teammate\u2019s conversation teaches the agent something new. The knowledge compounds \u2014 what one person asks makes the answer better for the next. You don\u2019t search a wiki. You ask the brain.",
        },
        {
          icon: "\u2263",
          title: "Governed by design",
          desc: "The agent can\u2019t silently break things. High-risk actions go through approval gates. Role-based access control, tiered permissions, and full audit logging are built in from day one.",
        },
        {
          icon: "\u2302",
          title: "Self-hosted. Your data.",
          desc: "Runs entirely on your infrastructure with one command. SSO federation, secret management, and monitoring built in. No vendor lock-in. MIT licensed. You own the brain.",
        },
      ],
      quote: "\u201COnce you internalize this model, every fixed product feels like an unnecessary constraint. Why accept someone else\u2019s limits when you can describe what you want and watch it materialize?\u201D",
    },
  },

  "zh-TW": {
    hero: {
      h1a: "\u4e0d\u767c\u4f48\u4efb\u4f55\u6771\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73fe\u3002",
      desc: "\u4e00\u584a\u7a7a\u767d\u7684\u87a2\u5e55\u3002\u4e00\u500b\u5718\u968a\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u500b\u9023\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u6771\u897f\u2014\u2014\u800c\u5b83\u70ba\u4efb\u4f55\u4eba\u5373\u6642\u5efa\u9020\u6240\u9700\u3002",
      cta: "\u770b\u770b\u600e\u9ebc\u904b\u4f5c",
      tagline: "\u79c1\u5bc6\u5c0d\u8a71\u3002\u96c6\u9ad4\u667a\u6167\u3002",
      pillars: [
        {
          icon: "\u25A1",
          label: "\u7a7a\u767d\u5373\u7522\u54c1",
          desc: "\u6c92\u6709\u5100\u8868\u677f\u3002\u6c92\u6709\u9078\u55ae\u3002\u7a7a\u767d\u756b\u5e03\u5c31\u662f\u7522\u54c1\u3002\u667a\u80fd\u9ad4\u5728\u4f60\u9700\u8981\u6642\u6e32\u67d3\u6240\u9700\u3002",
        },
        {
          icon: "\u2666",
          label: "\u771f\u5be6\u4ecb\u9762\uff0c\u975e\u6587\u5b57",
          desc: "\u667a\u80fd\u9ad4\u4e0d\u53ea\u662f\u56de\u8986\u6587\u5b57\u3002\u5b83\u5728\u756b\u5e03\u4e0a\u5373\u6642\u7522\u751f\u4e92\u52d5\u4ecb\u9762\u2014\u2014\u8868\u55ae\u3001\u5100\u8868\u677f\u3001\u8cc7\u6599\u6aa2\u8996\u3002",
        },
        {
          icon: "\u2731",
          label: "\u8d8a\u7528\u8d8a\u8070\u660e",
          desc: "\u6bcf\u500b\u5718\u968a\u6210\u54e1\u7684\u5c0d\u8a71\u90fd\u8b93\u667a\u80fd\u9ad4\u66f4\u9298\u92b3\u3002\u5171\u4eab\u8a18\u61b6\u3001\u5171\u4eab\u6280\u80fd\u3001\u5171\u4eab\u4e0a\u4e0b\u6587\u2014\u2014\u4e00\u500b\u4e0d\u65b7\u7d2f\u7a4d\u7684\u5927\u8166\u3002",
        },
      ],
    },
    how: {
      label: "\u904b\u4f5c\u65b9\u5f0f",
      h2a: "\u4e00\u500b\u667a\u80fd\u3002",
      h2b: "\u8a31\u591a\u5fc3\u667a\u3002",
      steps: [
        {
          num: "01",
          title: "\u4f60\u6253\u958b\u4e00\u584a\u7a7a\u767d\u87a2\u5e55\u3002",
          desc: "\u6c92\u6709\u5100\u8868\u677f\u3001\u6c92\u6709\u5074\u6b04\u3001\u6c92\u6709\u5f15\u5c0e\u7cbe\u9748\u3002\u53ea\u6709\u9ed1\u6697\u7684\u756b\u5e03\u548c\u4e00\u500b\u63d0\u793a\u5217\u3002\u7a7a\u767d\u5c31\u662f\u91cd\u9ede\u3002",
        },
        {
          num: "02",
          title: "\u4f60\u8aaa\u8a71\u3002\u5b83\u5efa\u9020\u3002",
          desc: "\u8981\u6c42\u4efb\u4f55\u6771\u897f\u2014\u2014\u8ffd\u8e64\u5668\u3001\u5de5\u4f5c\u6d41\u3001\u5de5\u5177\u3002\u667a\u80fd\u9ad4\u5728\u756b\u5e03\u4e0a\u6e32\u67d3\u771f\u5be6\u4e92\u52d5\u5143\u4ef6\u3002\u4e0d\u662f\u622a\u5716\u3002\u4e0d\u662f\u7d14\u6587\u5b57\u3002\u662f\u53ef\u9ede\u64ca\u3001\u53ef\u586b\u5beb\u3001\u53ef\u532f\u51fa\u7684\u5373\u6642\u4ecb\u9762\u3002",
        },
        {
          num: "03",
          title: "\u6bcf\u500b\u4eba\u990a\u540c\u4e00\u500b\u5927\u8166\u3002",
          desc: "\u6bcf\u500b\u5718\u968a\u6210\u54e1\u6709\u79c1\u4eba\u5c0d\u8a71\u3002\u4f46\u77e5\u8b58\u2014\u2014\u8a18\u61b6\u3001\u6280\u80fd\u3001\u6c7a\u7b56\u2014\u2014\u7d2f\u7a4d\u5728\u540c\u4e00\u8655\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u5c0d\u6bcf\u500b\u4eba\u8d8a\u8070\u660e\u3002",
        },
      ],
      archLabel: "\u67b6\u69cb",
      arch: [
        {
          label: "\u5718\u968a\u5171\u4eab\u5927\u8166",
          detail: "\u6bcf\u500b\u5718\u968a\u4e00\u500b\u667a\u80fd\u9ad4\u2014\u2014\u6301\u4e45\u8a18\u61b6\u3001\u6280\u80fd\u548c\u81ea\u52d5\u5316\uff0c\u96a8\u6bcf\u4f4d\u6210\u54e1\u7684\u6bcf\u6b21\u5c0d\u8a71\u6210\u9577",
        },
        {
          label: "\u4e92\u52d5\u756b\u5e03",
          detail: "\u667a\u80fd\u9ad4\u5373\u6642\u7522\u751f\u7684\u4ecb\u9762\u2014\u2014\u8868\u55ae\u3001\u5100\u8868\u677f\u3001\u7a0b\u5f0f\u78bc\u7de8\u8f2f\u5668\u3001\u4e92\u52d5\u8cc7\u6599\u6aa2\u8996",
        },
        {
          label: "\u4efb\u4f55\u983b\u9053\u63a5\u5165",
          detail: "\u7db2\u9801\u7d42\u7aef\u3001WhatsApp\u3001Telegram\u3001Discord\u3001Slack\u2014\u2014\u5168\u90e8\u9935\u5165\u540c\u4e00\u500b\u5927\u8166",
        },
      ],
    },
    why: {
      label: "\u70ba\u4ec0\u9ebc\u91cd\u8981",
      h2a: "\u6bcf\u500b\u5176\u4ed6\u61c9\u7528\u90fd\u662f",
      h2b: "\u4e00\u500b\u7c60\u5b50\u3002",
      subtitle: "\u4eca\u5929\u7684\u8edf\u9ad4\u662f\u5225\u4eba\u5c0d\u4f60\u9700\u6c42\u7684\u770b\u6cd5\uff0c\u51cd\u7d50\u5728\u7a0b\u5f0f\u78bc\u88e1\uff0c\u85cf\u5728\u8a02\u95b1\u5236\u5f8c\u9762\u3002Trinity \u5b8c\u5168\u7ffb\u8f49\u4e86\u9019\u4e00\u5207\u3002",
      cards: [
        {
          icon: "\u2716",
          title: "\u6bba\u6b7b\u529f\u80fd\u8def\u7dda\u5716",
          desc: "\u6c92\u6709\u5718\u968a\u7232\u4e0b\u4e00\u6b65\u5efa\u4ec0\u9ebc\u800c\u722d\u8ad6\u3002\u6bcf\u500b\u4f7f\u7528\u8005\u5f97\u5230\u4e00\u500b\u7531\u81ea\u5df1\u9700\u6c42\u5851\u9020\u7684\u4e0d\u540c\u5de5\u4f5c\u7a7a\u9593\u3002",
        },
        {
          icon: "\u2261",
          title: "\u53d6\u4ee3\u4f60\u7684\u5de5\u5177\u5806\u758a",
          desc: "WhatsApp\u3001Notion\u3001GitHub\u3001Slack\u3001Telegram\u3001\u5716\u50cf\u751f\u6210\u3001\u700f\u89bd\u5668\u81ea\u52d5\u5316\u3001\u7db2\u8def\u641c\u5c0b\u3001\u6587\u4ef6\u8655\u7406\u2014\u2014\u6301\u7e8c\u589e\u9577\u7684\u6280\u80fd\u5eab\u3002\u6bcf\u500b\u5de5\u5177\u90fd\u53ea\u662f\u4e00\u53e5\u63d0\u793a\u3002",
        },
        {
          icon: "\u25A0",
          title: "\u756b\u5e03\uff0c\u4e0d\u662f\u804a\u5929\u6846",
          desc: "\u667a\u80fd\u9ad4\u4e0d\u53ea\u662f\u56de\u8986\u6587\u5b57\u3002\u5b83\u6e32\u67d3\u5373\u6642\u4e92\u52d5\u4ecb\u9762\u2014\u2014\u5100\u8868\u677f\u3001\u8868\u55ae\u3001\u7a0b\u5f0f\u78bc\u7de8\u8f2f\u5668\u3001\u5206\u9801\u2014\u2014\u76f4\u63a5\u5728\u700f\u89bd\u5668\u4e2d\u3002\u53ef\u9ede\u64ca\u3001\u53ef\u586b\u5beb\u3001\u53ef\u532f\u51fa\u7684\u771f\u5be6\u5143\u4ef6\u3002",
        },
        {
          icon: "\u2690",
          title: "\u96c6\u9ad4\u77e5\u8b58",
          desc: "\u6bcf\u500b\u5718\u968a\u6210\u54e1\u7684\u5c0d\u8a71\u90fd\u5728\u6559\u667a\u80fd\u9ad4\u65b0\u6771\u897f\u3002\u77e5\u8b58\u4e0d\u65b7\u7d2f\u7a4d\u2014\u2014\u4e00\u500b\u4eba\u554f\u7684\u554f\u984c\uff0c\u8b93\u4e0b\u4e00\u500b\u4eba\u7684\u7b54\u6848\u66f4\u597d\u3002\u4f60\u4e0d\u7528\u641c\u5c0b wiki\u3002\u4f60\u76f4\u63a5\u554f\u5927\u8166\u3002",
        },
        {
          icon: "\u2263",
          title: "\u5167\u5efa\u6cbb\u7406",
          desc: "\u667a\u80fd\u9ad4\u4e0d\u80fd\u9748\u9ed8\u5730\u7834\u58de\u6771\u897f\u3002\u9ad8\u98a8\u96aa\u64cd\u4f5c\u901a\u904e\u5be9\u6279\u9580\u3002\u5167\u5efa\u89d2\u8272\u5b58\u53d6\u63a7\u5236\u3001\u5206\u5c64\u6b0a\u9650\u548c\u5b8c\u6574\u7a3d\u6838\u65e5\u8a8c\u3002",
        },
        {
          icon: "\u2302",
          title: "\u81ea\u67b6\u3002\u4f60\u7684\u8cc7\u6599\u3002",
          desc: "\u4e00\u884c\u6307\u4ee4\u5728\u4f60\u7684\u57fa\u790e\u8a2d\u65bd\u4e0a\u57f7\u884c\u3002\u5167\u5efa\u55ae\u4e00\u767b\u5165\u3001\u5bc6\u9470\u7ba1\u7406\u548c\u76e3\u63a7\u3002\u7121\u4f9b\u61c9\u5546\u9396\u5b9a\u3002MIT \u6388\u6b0a\u3002\u4f60\u64c1\u6709\u5927\u8166\u3002",
        },
      ],
      quote: "\u300c\u4e00\u65e6\u4f60\u5167\u5316\u4e86\u9019\u500b\u6a21\u5f0f\uff0c\u6bcf\u500b\u50b3\u7d71\u61c9\u7528\u90fd\u611f\u89ba\u50cf\u4e0d\u5fc5\u8981\u7684\u675f\u7e1b\u3002\u70ba\u4ec0\u9ebc\u8981\u7528\u5225\u4eba\u7684\u9650\u5236\u6253\u9020\u7684\u5de5\u5177\uff0c\u800c\u4e0d\u662f\u63cf\u8ff0\u4f60\u8981\u7684\uff0c\u8b93\u5b83\u5be6\u9ad4\u5316\uff1f\u300d",
    },
  },

  "zh-CN": {
    hero: {
      h1a: "\u4e0d\u53d1\u5e03\u4efb\u4f55\u4e1c\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73b0\u3002",
      desc: "\u4e00\u5757\u7a7a\u767d\u7684\u5c4f\u5e55\u3002\u4e00\u4e2a\u56e2\u961f\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u4e2a\u8fde\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u4e1c\u897f\u2014\u2014\u800c\u5b83\u4e3a\u4efb\u4f55\u4eba\u5b9e\u65f6\u5efa\u9020\u6240\u9700\u3002",
      cta: "\u770b\u770b\u600e\u4e48\u8fd0\u4f5c",
      tagline: "\u79c1\u5bc6\u5bf9\u8bdd\u3002\u96c6\u4f53\u667a\u6167\u3002",
      pillars: [
        {
          icon: "\u25A1",
          label: "\u7a7a\u767d\u5373\u4ea7\u54c1",
          desc: "\u6ca1\u6709\u4eea\u8868\u76d8\u3002\u6ca1\u6709\u83dc\u5355\u3002\u7a7a\u767d\u753b\u5e03\u5c31\u662f\u4ea7\u54c1\u3002\u667a\u80fd\u4f53\u5728\u4f60\u9700\u8981\u65f6\u6e32\u67d3\u6240\u9700\u3002",
        },
        {
          icon: "\u2666",
          label: "\u771f\u5b9e\u754c\u9762\uff0c\u975e\u6587\u5b57",
          desc: "\u667a\u80fd\u4f53\u4e0d\u53ea\u662f\u56de\u590d\u6587\u5b57\u3002\u5b83\u5728\u753b\u5e03\u4e0a\u5b9e\u65f6\u751f\u6210\u4e92\u52a8\u754c\u9762\u2014\u2014\u8868\u5355\u3001\u4eea\u8868\u76d8\u3001\u6570\u636e\u89c6\u56fe\u3002",
        },
        {
          icon: "\u2731",
          label: "\u8d8a\u7528\u8d8a\u806a\u660e",
          desc: "\u6bcf\u4e2a\u56e2\u961f\u6210\u5458\u7684\u5bf9\u8bdd\u90fd\u8ba9\u667a\u80fd\u4f53\u66f4\u654f\u9510\u3002\u5171\u4eab\u8bb0\u5fc6\u3001\u5171\u4eab\u6280\u80fd\u3001\u5171\u4eab\u4e0a\u4e0b\u6587\u2014\u2014\u4e00\u4e2a\u4e0d\u65ad\u7d2f\u79ef\u7684\u5927\u8111\u3002",
        },
      ],
    },
    how: {
      label: "\u8fd0\u4f5c\u65b9\u5f0f",
      h2a: "\u4e00\u4e2a\u667a\u80fd\u3002",
      h2b: "\u8bb8\u591a\u5fc3\u667a\u3002",
      steps: [
        {
          num: "01",
          title: "\u4f60\u6253\u5f00\u4e00\u5757\u7a7a\u767d\u5c4f\u5e55\u3002",
          desc: "\u6ca1\u6709\u4eea\u8868\u76d8\u3001\u6ca1\u6709\u4fa7\u680f\u3001\u6ca1\u6709\u5f15\u5bfc\u7cbe\u7075\u3002\u53ea\u6709\u9ed1\u6697\u7684\u753b\u5e03\u548c\u4e00\u4e2a\u63d0\u793a\u680f\u3002\u7a7a\u767d\u5c31\u662f\u91cd\u70b9\u3002",
        },
        {
          num: "02",
          title: "\u4f60\u8bf4\u8bdd\u3002\u5b83\u5efa\u9020\u3002",
          desc: "\u8981\u6c42\u4efb\u4f55\u4e1c\u897f\u2014\u2014\u8ddf\u8e2a\u5668\u3001\u5de5\u4f5c\u6d41\u3001\u5de5\u5177\u3002\u667a\u80fd\u4f53\u5728\u753b\u5e03\u4e0a\u6e32\u67d3\u771f\u5b9e\u4e92\u52a8\u7ec4\u4ef6\u3002\u4e0d\u662f\u622a\u56fe\u3002\u4e0d\u662f\u7eaf\u6587\u5b57\u3002\u662f\u53ef\u70b9\u51fb\u3001\u53ef\u586b\u5199\u3001\u53ef\u5bfc\u51fa\u7684\u5b9e\u65f6\u754c\u9762\u3002",
        },
        {
          num: "03",
          title: "\u6bcf\u4e2a\u4eba\u517b\u540c\u4e00\u4e2a\u5927\u8111\u3002",
          desc: "\u6bcf\u4e2a\u56e2\u961f\u6210\u5458\u6709\u79c1\u4eba\u5bf9\u8bdd\u3002\u4f46\u77e5\u8bc6\u2014\u2014\u8bb0\u5fc6\u3001\u6280\u80fd\u3001\u51b3\u7b56\u2014\u2014\u7d2f\u79ef\u5728\u540c\u4e00\u5904\u3002\u4f7f\u7528\u7684\u4eba\u8d8a\u591a\uff0c\u5b83\u5c31\u5bf9\u6bcf\u4e2a\u4eba\u8d8a\u806a\u660e\u3002",
        },
      ],
      archLabel: "\u67b6\u6784",
      arch: [
        {
          label: "\u56e2\u961f\u5171\u4eab\u5927\u8111",
          detail: "\u6bcf\u4e2a\u56e2\u961f\u4e00\u4e2a\u667a\u80fd\u4f53\u2014\u2014\u6301\u4e45\u8bb0\u5fc6\u3001\u6280\u80fd\u548c\u81ea\u52a8\u5316\uff0c\u968f\u6bcf\u4f4d\u6210\u5458\u7684\u6bcf\u6b21\u5bf9\u8bdd\u6210\u957f",
        },
        {
          label: "\u4e92\u52a8\u753b\u5e03",
          detail: "\u667a\u80fd\u4f53\u5b9e\u65f6\u751f\u6210\u7684\u754c\u9762\u2014\u2014\u8868\u5355\u3001\u4eea\u8868\u76d8\u3001\u4ee3\u7801\u7f16\u8f91\u5668\u3001\u4e92\u52a8\u6570\u636e\u89c6\u56fe",
        },
        {
          label: "\u4efb\u4f55\u9891\u9053\u63a5\u5165",
          detail: "\u7f51\u9875\u7ec8\u7aef\u3001WhatsApp\u3001Telegram\u3001Discord\u3001Slack\u2014\u2014\u5168\u90e8\u9a71\u5165\u540c\u4e00\u4e2a\u5927\u8111",
        },
      ],
    },
    why: {
      label: "\u4e3a\u4ec0\u4e48\u91cd\u8981",
      h2a: "\u6bcf\u4e2a\u5176\u4ed6\u5e94\u7528\u90fd\u662f",
      h2b: "\u4e00\u4e2a\u7b3c\u5b50\u3002",
      subtitle: "\u4eca\u5929\u7684\u8f6f\u4ef6\u662f\u522b\u4eba\u5bf9\u4f60\u9700\u6c42\u7684\u770b\u6cd5\uff0c\u51bb\u7ed3\u5728\u4ee3\u7801\u91cc\uff0c\u85cf\u5728\u8ba2\u9605\u5236\u540e\u9762\u3002Trinity \u5b8c\u5168\u7ffb\u8f6c\u4e86\u8fd9\u4e00\u5207\u3002",
      cards: [
        {
          icon: "\u2716",
          title: "\u6740\u6b7b\u529f\u80fd\u8def\u7ebf\u56fe",
          desc: "\u6ca1\u6709\u56e2\u961f\u4e3a\u4e0b\u4e00\u6b65\u5efa\u4ec0\u4e48\u800c\u4e89\u8bba\u3002\u6bcf\u4e2a\u7528\u6237\u5f97\u5230\u4e00\u4e2a\u7531\u81ea\u5df1\u9700\u6c42\u5851\u9020\u7684\u4e0d\u540c\u5de5\u4f5c\u7a7a\u95f4\u3002",
        },
        {
          icon: "\u2261",
          title: "\u53d6\u4ee3\u4f60\u7684\u5de5\u5177\u5806\u53e0",
          desc: "WhatsApp\u3001Notion\u3001GitHub\u3001Slack\u3001Telegram\u3001\u56fe\u50cf\u751f\u6210\u3001\u6d4f\u89c8\u5668\u81ea\u52a8\u5316\u3001\u7f51\u7edc\u641c\u7d22\u3001\u6587\u6863\u5904\u7406\u2014\u2014\u6301\u7eed\u589e\u957f\u7684\u6280\u80fd\u5e93\u3002\u6bcf\u4e2a\u5de5\u5177\u90fd\u53ea\u662f\u4e00\u53e5\u63d0\u793a\u3002",
        },
        {
          icon: "\u25A0",
          title: "\u753b\u5e03\uff0c\u4e0d\u662f\u804a\u5929\u6846",
          desc: "\u667a\u80fd\u4f53\u4e0d\u53ea\u662f\u56de\u590d\u6587\u5b57\u3002\u5b83\u6e32\u67d3\u5b9e\u65f6\u4e92\u52a8\u754c\u9762\u2014\u2014\u4eea\u8868\u76d8\u3001\u8868\u5355\u3001\u4ee3\u7801\u7f16\u8f91\u5668\u3001\u5206\u9875\u2014\u2014\u76f4\u63a5\u5728\u6d4f\u89c8\u5668\u4e2d\u3002\u53ef\u70b9\u51fb\u3001\u53ef\u586b\u5199\u3001\u53ef\u5bfc\u51fa\u7684\u771f\u5b9e\u7ec4\u4ef6\u3002",
        },
        {
          icon: "\u2690",
          title: "\u96c6\u4f53\u77e5\u8bc6",
          desc: "\u6bcf\u4e2a\u56e2\u961f\u6210\u5458\u7684\u5bf9\u8bdd\u90fd\u5728\u6559\u667a\u80fd\u4f53\u65b0\u4e1c\u897f\u3002\u77e5\u8bc6\u4e0d\u65ad\u7d2f\u79ef\u2014\u2014\u4e00\u4e2a\u4eba\u95ee\u7684\u95ee\u9898\uff0c\u8ba9\u4e0b\u4e00\u4e2a\u4eba\u7684\u7b54\u6848\u66f4\u597d\u3002\u4f60\u4e0d\u7528\u641c\u7d22 wiki\u3002\u4f60\u76f4\u63a5\u95ee\u5927\u8111\u3002",
        },
        {
          icon: "\u2263",
          title: "\u5185\u5efa\u6cbb\u7406",
          desc: "\u667a\u80fd\u4f53\u4e0d\u80fd\u9759\u9ed8\u5730\u7834\u574f\u4e1c\u897f\u3002\u9ad8\u98ce\u9669\u64cd\u4f5c\u901a\u8fc7\u5ba1\u6279\u95e8\u3002\u5185\u5efa\u89d2\u8272\u8bbf\u95ee\u63a7\u5236\u3001\u5206\u5c42\u6743\u9650\u548c\u5b8c\u6574\u5ba1\u8ba1\u65e5\u5fd7\u3002",
        },
        {
          icon: "\u2302",
          title: "\u81ea\u67b6\u3002\u4f60\u7684\u6570\u636e\u3002",
          desc: "\u4e00\u884c\u6307\u4ee4\u5728\u4f60\u7684\u57fa\u7840\u8bbe\u65bd\u4e0a\u8fd0\u884c\u3002\u5185\u5efa\u5355\u4e00\u767b\u5f55\u3001\u5bc6\u94a5\u7ba1\u7406\u548c\u76d1\u63a7\u3002\u65e0\u4f9b\u5e94\u5546\u9501\u5b9a\u3002MIT \u6388\u6743\u3002\u4f60\u62e5\u6709\u5927\u8111\u3002",
        },
      ],
      quote: "\u201c\u4e00\u65e6\u4f60\u5185\u5316\u4e86\u8fd9\u4e2a\u6a21\u5f0f\uff0c\u6bcf\u4e2a\u4f20\u7edf\u5e94\u7528\u90fd\u611f\u89c9\u50cf\u4e0d\u5fc5\u8981\u7684\u675f\u7f1a\u3002\u4e3a\u4ec0\u4e48\u8981\u7528\u522b\u4eba\u7684\u9650\u5236\u6253\u9020\u7684\u5de5\u5177\uff0c\u800c\u4e0d\u662f\u63cf\u8ff0\u4f60\u8981\u7684\uff0c\u8ba9\u5b83\u5b9e\u4f53\u5316\uff1f\u201d",
    },
  },
};
