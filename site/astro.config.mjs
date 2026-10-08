// @ts-check
import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";
import sitemap from "@astrojs/sitemap";
import { paraglideVitePlugin } from "@inlang/paraglide-js";

// Keep in sync with project.inlang/settings.json and src/i18n.ts.
const locales = ["en", "zh-hant", "zh-hk", "zh-hans", "ja"];
// Their BCP 47 tags, as `lang` in src/i18n.ts (used for the sitemap's hreflang).
const LANGS = { en: "en", "zh-hant": "zh-Hant-TW", "zh-hk": "zh-Hant-HK", "zh-hans": "zh-Hans", ja: "ja" };
const isCloudflarePages = process.env.CF_PAGES === "1";
const cloudflarePagesHost = process.env.CF_PAGES_URL || "triwarden.pages.dev";
const siteUrl = isCloudflarePages ? `https://${cloudflarePagesHost}` : "https://sinhong2011.github.io";
const basePath = isCloudflarePages ? "/" : "/triwarden";

// The `shaders` library registers all ~200 of its effects up front (2.5 MB). The site uses a handful, so its
// registry module is swapped for one that lists only these; the rest are never bundled. Add a name here when
// a preset in src/scripts/shader.ts starts using a new component.
const SHADERS_USED = ["MeshGradient", "FlutedGlass", "CursorRipples", "FilmGrain"];

/** @returns {import("vite").Plugin} */
function slimShaderRegistry() {
  const id = "\0tw-shader-registry";
  return {
    name: "tw-slim-shader-registry",
    enforce: "pre",
    resolveId(source, importer) {
      if (importer?.includes("/shaders/dist/") && /(^|\/)shaderRegistry-[\w-]+\.js$/.test(source)) return id;
    },
    load(loaded) {
      if (loaded !== id) return;
      const imports = SHADERS_USED.map((n, i) => `import { componentDefinition as d${i} } from "shaders/core/${n}";`).join("\n");
      return `${imports}
const shaderRegistry = {};
for (const def of [${SHADERS_USED.map((_, i) => `d${i}`).join(", ")}]) shaderRegistry[def.name] = { name: def.name, fileName: def.name, category: def.category || "Uncategorized", definition: def, propsMetadata: {} };
const getAllShaders = () => Object.values(shaderRegistry);
const getShaderByName = (name) => shaderRegistry[name];
const getShadersByCategory = (c) => getAllShaders().filter((s) => s.category === c);
const getShaderCategories = () => [...new Set(getAllShaders().map((s) => s.category))].sort();
export { shaderRegistry as a, getShadersByCategory as i, getShaderByName as n, getShaderCategories as r, getAllShaders as t };`;
    },
  };
}

export default defineConfig({
  site: siteUrl,
  base: basePath,
  output: "static",
  devToolbar: { enabled: false },
  i18n: { defaultLocale: "en", locales, routing: { prefixDefaultLocale: false } },
  // sitemap-index.xml with every page and its language alternates (hreflang), for search engines.
  integrations: [sitemap({ i18n: { defaultLocale: "en", locales: Object.fromEntries(locales.map((l) => [l, LANGS[l]])) } })],
  vite: {
    // Pre-bundle these at dev start; discovered later, Vite re-optimises mid-session and old tabs get 504s for GSAP.
    optimizeDeps: { include: ["gsap", "gsap/ScrollTrigger", "shaders/js"] },
    plugins: [
      tailwindcss(),
      slimShaderRegistry(),
      // Static pages: the middleware sets the locale per page, so no URL or cookie strategy is needed at runtime.
      paraglideVitePlugin({ project: "./project.inlang", outdir: "./src/paraglide", strategy: ["globalVariable", "baseLocale"] }),
    ],
  },
});
