import { i18n } from "@lingui/core";
import { en, zh } from "make-plural/plurals";

export type SupportedLocale = "en" | "zh-HK" | "zh-CN" | "zh-TW";

// Configure plurals for each locale
i18n.loadLocaleData({
  en: { plurals: en },
  "zh-HK": { plurals: zh },
  "zh-CN": { plurals: zh },
  "zh-TW": { plurals: zh },
});

/**
 * Load message catalog for a given locale
 */
export async function loadCatalog(locale: SupportedLocale) {
  const { messages } = await import(`../locales/${locale}/messages.js`);
  return messages;
}

/**
 * Activate a locale by loading its catalog and setting it as active
 */
export async function activateLocale(locale: SupportedLocale) {
  const messages = await loadCatalog(locale);
  i18n.load(locale, messages);
  i18n.activate(locale);
}

/**
 * Get the default locale from browser preferences or fallback to English
 */
export function getDefaultLocale(): SupportedLocale {
  // Check localStorage first
  const stored = localStorage.getItem("lingui-locale");
  if (stored && isValidLocale(stored)) {
    return stored as SupportedLocale;
  }

  // Check browser language
  const browserLang = navigator.language;
  const supportedLocales: SupportedLocale[] = ["en", "zh-HK", "zh-CN", "zh-TW"];

  // Direct match
  if (supportedLocales.includes(browserLang as SupportedLocale)) {
    return browserLang as SupportedLocale;
  }

  // Language code match (e.g., "zh" -> "zh-CN")
  const langCode = browserLang.split("-")[0];
  if (langCode === "zh") {
    // Default to simplified Chinese for generic "zh"
    return "zh-CN";
  }

  // Fallback to English
  return "en";
}

/**
 * Check if a locale string is valid
 */
function isValidLocale(locale: string): boolean {
  return ["en", "zh-HK", "zh-CN", "zh-TW"].includes(locale);
}

/**
 * Set locale and persist to localStorage
 */
export async function setLocale(locale: SupportedLocale) {
  await activateLocale(locale);
  localStorage.setItem("lingui-locale", locale);
}

/**
 * Get current active locale
 */
export function getCurrentLocale(): SupportedLocale {
  return (i18n.locale as SupportedLocale) || "en";
}

/**
 * Get all supported locales
 */
export function getSupportedLocales(): SupportedLocale[] {
  return ["en", "zh-HK", "zh-CN", "zh-TW"];
}

/**
 * Get human-readable name for a locale
 */
export function getLocaleName(locale: SupportedLocale): string {
  const names: Record<SupportedLocale, string> = {
    en: "English",
    "zh-CN": "简体中文",
    "zh-HK": "繁體中文 (香港)",
    "zh-TW": "繁體中文 (台灣)",
  };
  return names[locale];
}

// Initialize with default locale
const defaultLocale = getDefaultLocale();
activateLocale(defaultLocale).catch(console.error);

export { i18n };
