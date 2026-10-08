/** Site-wide facts in one place. Paths from `asset()` respect the deploy base (GitHub Pages: /triwarden/). */
const repo = "https://github.com/sinhong2011/triwarden";

// Lemon Squeezy checkout. TEST MODE — this link changes when the store goes live; change it here only.
export const CHECKOUT_URL = "https://niskan516.lemonsqueezy.com/checkout/buy/3c30c6c1-6296-4fc0-b465-bd762aced135";

export const SITE = {
  name: "Triwarden",
  repo,
  version: "0.1.1",
  price: "$19.99",
  // Fallback when the latest DMG can't be looked up (see release.ts).
  download: `${repo}/releases/latest`,
  api: "https://api.github.com/repos/sinhong2011/triwarden",
  // Always the newest DMG, once releases carry the stable-named copy (scripts/release.sh).
  latestDmg: `${repo}/releases/latest/download/Triwarden.dmg`,
  brew: "brew install --cask sinhong2011/tap/triwarden",
  security: `${repo}/blob/main/SECURITY.md`,
  checkout: CHECKOUT_URL,
  filmLength: "1:00",
};

export const asset = (path: string) => `${import.meta.env.BASE_URL.replace(/\/$/, "")}/${path.replace(/^\//, "")}`;
