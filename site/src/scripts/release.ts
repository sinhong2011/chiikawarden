/* Keeps direct-download links on the newest release's DMG when the page was built before releases carried the
   fixed Triwarden.dmg (see src/release.ts). Links carry [data-dmg]; version and size text carry [data-dmg-version]
   and [data-dmg-size]. */
import { $$ } from "./motion";

type Rel = { version: string; dmg: string; size: number; notes: string };

const apply = (r: Rel) => {
  $$<HTMLAnchorElement>("[data-dmg]").forEach((a) => (a.href = r.dmg));
  $$<HTMLAnchorElement>("[data-dmg-notes]").forEach((a) => (a.href = r.notes));
  $$("[data-dmg-version]").forEach((el) => (el.textContent = r.version));
  $$("[data-dmg-size]").forEach((el) => (el.textContent = `${(r.size / 1_000_000).toFixed(1)} MB`));
  $$("[data-dmg-mb]").forEach((el) => { el.dataset.count = String(r.size / 1_000_000); el.textContent = (r.size / 1_000_000).toFixed(1); });
};

if ($$("[data-dmg]").length) {
  let cached: string | null = null;
  try { cached = sessionStorage.getItem("release"); } catch {}
  if (cached) apply(JSON.parse(cached));
  else fetch("https://api.github.com/repos/sinhong2011/triwarden/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((res) => (res.ok ? res.json() : null))
    .then((d) => {
      const assets: { name: string; browser_download_url: string; size: number }[] = d?.assets ?? [];
      const fixed = assets.find((x) => x.name === "Triwarden.dmg");
      const dmg = fixed ?? assets.find((x) => /\.dmg$/i.test(x.name));
      if (!dmg) return;
      const url = fixed ? "https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg" : dmg.browser_download_url;
      const r: Rel = { version: String(d.tag_name).replace(/^v/, ""), dmg: url, size: dmg.size, notes: d.html_url };
      apply(r);
      try { sessionStorage.setItem("release", JSON.stringify(r)); } catch {}
    })
    .catch(() => {});
}
