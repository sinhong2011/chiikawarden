/** Site-wide facts in one place. Paths from `asset()` respect the deploy base (GitHub Pages: /triwarden/). */
const repo = "https://github.com/sinhong2011/triwarden";

// Lemon Squeezy checkout. TEST MODE — confirm US$19.99 and replace with the live variant before release.
export const CHECKOUT_URL = "https://niskan516.lemonsqueezy.com/checkout/buy/3c30c6c1-6296-4fc0-b465-bd762aced135";

export const SITE = {
  name: "Triwarden",
  repo,
  version: "0.1.1",
  /** One-time License price shown on the site. Must match Lemon Squeezy before going live. */
  price: "US$19.99",
  // Fallback when the latest DMG can't be looked up (see release.ts).
  download: `${repo}/releases/latest`,
  api: "https://api.github.com/repos/sinhong2011/triwarden",
  // Always the newest DMG, once releases carry the stable-named copy (scripts/release.sh).
  latestDmg: `${repo}/releases/latest/download/Triwarden.dmg`,
  brew: "brew install --cask sinhong2011/tap/triwarden",
  security: `${repo}/blob/main/SECURITY.md`,
  /** Path under each locale; use `localeHref(locale, "pricing/")` in components. */
  pricingPath: "pricing/",
  privacyPath: "privacy/",
  licenseTermsPath: "license-terms/",
  checkout: CHECKOUT_URL,
  supportEmail: "triwarden@protonmail.com",
  support: "mailto:triwarden@protonmail.com",
  lemonPrivacy: "https://www.lemonsqueezy.com/privacy",
  googleFontsPrivacy: "https://policies.google.com/privacy",
  githubPrivacy: "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement",
  filmLength: "1:00",
};

export const asset = (path: string) => `${import.meta.env.BASE_URL.replace(/\/$/, "")}/${path.replace(/^\//, "")}`;
