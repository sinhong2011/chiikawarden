import { getLocale } from "./paraglide/runtime.js";

/** The site's languages — the same five the app ships. `path` is the URL prefix under the deploy base.
    `serif` is the headline face (Google Fonts family) paired with Instrument Serif; body text uses the system's own
    CJK sans (PingFang, Hiragino), which every Mac already has. */
export const LOCALES = [
  { id: "en", lang: "en", code: "EN", label: "English", sub: "International", path: "", serif: null },
  { id: "zh-hant", lang: "zh-Hant-TW", code: "TW", label: "繁體中文", sub: "Traditional Chinese · Taiwan", path: "zh-hant/", serif: "Noto+Serif+TC" },  // Ming, Taiwan character forms
  { id: "zh-hk", lang: "zh-Hant-HK", code: "HK", label: "繁體中文", sub: "Traditional Chinese · Hong Kong", path: "zh-hk/", serif: "Chiron+Sung+HK" },
  { id: "zh-hans", lang: "zh-Hans", code: "CN", label: "简体中文", sub: "Simplified Chinese", path: "zh-hans/", serif: "Noto+Serif+SC" },
  { id: "ja", lang: "ja", code: "JA", label: "日本語", sub: "Japanese", path: "ja/", serif: "Shippori+Mincho" },
] as const;

export type Locale = (typeof LOCALES)[number];

export const currentLocale = (): Locale => LOCALES.find((l) => l.id === getLocale()) ?? LOCALES[0];

/** A page in a given language, under the deploy base: `localeHref(l)` is the home page, `localeHref(l, "guides/ssh-agent/")` a guide. */
export const localeHref = (l: Locale, page = "") => `${import.meta.env.BASE_URL.replace(/\/$/, "")}/${l.path}${page}`;
