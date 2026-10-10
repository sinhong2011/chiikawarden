import { getLocale } from "./paraglide/runtime.js";

/** The site's five languages. `path` is the URL prefix under the deploy base. */
export const LOCALES = [
  { id: "en", lang: "en", code: "EN", label: "English", sub: "International", path: "" },
  { id: "zh-hant", lang: "zh-Hant-TW", code: "TW", label: "繁體中文", sub: "Traditional Chinese · Taiwan", path: "zh-hant/" },
  { id: "zh-hk", lang: "zh-Hant-HK", code: "HK", label: "繁體中文", sub: "Traditional Chinese · Hong Kong", path: "zh-hk/" },
  { id: "zh-hans", lang: "zh-Hans", code: "CN", label: "简体中文", sub: "Simplified Chinese", path: "zh-hans/" },
  { id: "ja", lang: "ja", code: "JA", label: "日本語", sub: "Japanese", path: "ja/" },
] as const;

export type Locale = (typeof LOCALES)[number];

export const currentLocale = (): Locale => LOCALES.find((l) => l.id === getLocale()) ?? LOCALES[0];

/** A page in a given language, under the deploy base: `localeHref(l)` is the home page, `localeHref(l, "guides/ssh-agent/")` a guide. */
export const localeHref = (l: Locale, page = "") => `${import.meta.env.BASE_URL.replace(/\/$/, "")}/${l.path}${page}`;
