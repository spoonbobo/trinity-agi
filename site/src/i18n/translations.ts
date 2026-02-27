export const locales = ["en", "zh-TW", "zh-CN"] as const;
export type Locale = (typeof locales)[number];

export const localeLabels: Record<Locale, string> = {
  en: "EN",
  "zh-TW": "繁體",
  "zh-CN": "简体",
};

type TranslationStrings = {
  hero: {
    h1a: string;
    h1b: string;
    desc: string;
    cta: string;
    tagline: string;
  };
  terminal: {
    lines: { type: string; text: string }[];
  };
};

export const translations: Record<Locale, TranslationStrings> = {
  en: {
    hero: {
      h1a: "Nothing ships.",
      h1b: "Everything emerges.",
      desc: "An empty screen. A single intelligence. Every person who connects teaches it something new. The app doesn\u2019t exist until you speak.",
      cta: "JOIN THE BRAIN",
      tagline: "PRIVATE CONVERSATIONS. COLLECTIVE WISDOM.",
    },
    terminal: {
      lines: [
        { type: "user", text: "> Show me what the team logged yesterday" },
        { type: "agent", text: "Searching shared memory..." },
        { type: "tool", text: "[memory] 3 entries from 2 contributors" },
        { type: "agent", text: "Rod deployed the API. Mia filed the compliance doc. Alex fixed the auth bug." },
        { type: "gap", text: "" },
        { type: "user", text: "> Build me a project tracker based on that" },
        { type: "agent", text: "Generating tracker from collective context..." },
        { type: "tool", text: "[canvas] Rendering UI surface" },
        { type: "agent", text: "Done. Live on your canvas \u2014 pre-filled with what everyone contributed." },
        { type: "gap", text: "" },
        { type: "user", text: "> Remember: deployments need sign-off from Rod" },
        { type: "agent", text: "Written to shared memory. All users will know." },
      ],
    },
  },
  "zh-TW": {
    hero: {
      h1a: "\u4e0d\u767c\u4f48\u4efb\u4f55\u6771\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73fe\u3002",
      desc: "\u4e00\u584a\u7a7a\u767d\u7684\u87a2\u5e55\u3002\u4e00\u500b\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u500b\u9023\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u6771\u897f\u3002\u5728\u4f60\u958b\u53e3\u4e4b\u524d\uff0c\u61c9\u7528\u4e26\u4e0d\u5b58\u5728\u3002",
      cta: "\u52a0\u5165\u5927\u8166",
      tagline: "\u79c1\u5bc6\u5c0d\u8a71\u3002\u96c6\u9ad4\u667a\u6167\u3002",
    },
    terminal: {
      lines: [
        { type: "user", text: "> \u986f\u793a\u5718\u968a\u6628\u5929\u7684\u7d00\u9304" },
        { type: "agent", text: "\u6b63\u5728\u641c\u5c0b\u5171\u4eab\u8a18\u61b6..." },
        { type: "tool", text: "[memory] \u4f86\u81ea 2 \u4f4d\u8ca2\u737b\u8005\u7684 3 \u7b46\u7d00\u9304" },
        { type: "agent", text: "Rod \u90e8\u7f72\u4e86 API\u3002Mia \u63d0\u4ea4\u4e86\u5408\u898f\u6587\u4ef6\u3002Alex \u4fee\u5fa9\u4e86\u8a8d\u8b49\u7f3a\u9677\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u57fa\u65bc\u9019\u4e9b\u5efa\u4e00\u500b\u5c08\u6848\u8ffd\u8e64\u5668" },
        { type: "agent", text: "\u6b63\u5728\u5f9e\u96c6\u9ad4\u4e0a\u4e0b\u6587\u7522\u751f..." },
        { type: "tool", text: "[canvas] \u6e32\u67d3 UI \u4ecb\u9762" },
        { type: "agent", text: "\u5b8c\u6210\u3002\u5df2\u5728\u4f60\u7684\u756b\u5e03\u4e0a\u2014\u2014\u9810\u586b\u4e86\u6240\u6709\u4eba\u7684\u8ca2\u737b\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u8a18\u4f4f\uff1a\u90e8\u7f72\u9700\u8981 Rod \u7c3d\u5b57" },
        { type: "agent", text: "\u5df2\u5beb\u5165\u5171\u4eab\u8a18\u61b6\u3002\u6240\u6709\u4f7f\u7528\u8005\u90fd\u6703\u77e5\u9053\u3002" },
      ],
    },
  },
  "zh-CN": {
    hero: {
      h1a: "\u4e0d\u53d1\u5e03\u4efb\u4f55\u4e1c\u897f\u3002",
      h1b: "\u4e00\u5207\u81ea\u7136\u6d8c\u73b0\u3002",
      desc: "\u4e00\u5757\u7a7a\u767d\u7684\u5c4f\u5e55\u3002\u4e00\u4e2a\u5171\u4eab\u7684\u667a\u80fd\u3002\u6bcf\u4e2a\u8fde\u63a5\u7684\u4eba\u90fd\u5728\u6559\u5b83\u65b0\u4e1c\u897f\u3002\u5728\u4f60\u5f00\u53e3\u4e4b\u524d\uff0c\u5e94\u7528\u5e76\u4e0d\u5b58\u5728\u3002",
      cta: "\u52a0\u5165\u5927\u8111",
      tagline: "\u79c1\u5bc6\u5bf9\u8bdd\u3002\u96c6\u4f53\u667a\u6167\u3002",
    },
    terminal: {
      lines: [
        { type: "user", text: "> \u663e\u793a\u56e2\u961f\u6628\u5929\u7684\u8bb0\u5f55" },
        { type: "agent", text: "\u6b63\u5728\u641c\u7d22\u5171\u4eab\u8bb0\u5fc6..." },
        { type: "tool", text: "[memory] \u6765\u81ea 2 \u4f4d\u8d21\u732e\u8005\u7684 3 \u6761\u8bb0\u5f55" },
        { type: "agent", text: "Rod \u90e8\u7f72\u4e86 API\u3002Mia \u63d0\u4ea4\u4e86\u5408\u89c4\u6587\u6863\u3002Alex \u4fee\u590d\u4e86\u8ba4\u8bc1\u7f3a\u9677\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u57fa\u4e8e\u8fd9\u4e9b\u5efa\u4e00\u4e2a\u9879\u76ee\u8ddf\u8e2a\u5668" },
        { type: "agent", text: "\u6b63\u5728\u4ece\u96c6\u4f53\u4e0a\u4e0b\u6587\u751f\u6210..." },
        { type: "tool", text: "[canvas] \u6e32\u67d3 UI \u754c\u9762" },
        { type: "agent", text: "\u5b8c\u6210\u3002\u5df2\u5728\u4f60\u7684\u753b\u5e03\u4e0a\u2014\u2014\u9884\u586b\u4e86\u6240\u6709\u4eba\u7684\u8d21\u732e\u3002" },
        { type: "gap", text: "" },
        { type: "user", text: "> \u8bb0\u4f4f\uff1a\u90e8\u7f72\u9700\u8981 Rod \u7b7e\u5b57" },
        { type: "agent", text: "\u5df2\u5199\u5165\u5171\u4eab\u8bb0\u5fc6\u3002\u6240\u6709\u7528\u6237\u90fd\u4f1a\u77e5\u9053\u3002" },
      ],
    },
  },
};
