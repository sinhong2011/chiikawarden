import { gsap, reduce, $, $$ } from "./motion";

/* ── Light / dark: the toggle flips away from whatever is showing now and remembers it. ── */
const root = document.documentElement;
const toggle = $<HTMLButtonElement>("[data-theme-toggle]");
const isDark = () => root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
const label = () => toggle?.setAttribute("aria-label", (isDark() ? toggle.dataset.toLight : toggle.dataset.toDark) ?? "");
label();
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", label);
toggle?.addEventListener("click", () => {
  const next = isDark() ? "light" : "dark";
  root.classList.add("theme-switching");
  root.dataset.theme = next;
  try { localStorage.setItem("theme", next); } catch {}
  label();
  setTimeout(() => root.classList.remove("theme-switching"), 450);
});

/* One shared request updates both desktop and narrow-screen star counts. */
const starLinks = $$<HTMLAnchorElement>("[data-star-link]");
const showStars = (count: number) => {
  $$("[data-stars]").forEach((node) => { node.textContent = count.toLocaleString(document.documentElement.lang); });
  starLinks.forEach((link) => link.setAttribute("aria-label", (link.dataset.starLabel ?? "").replace("{count}", String(count))));
};
let cachedStars: string | null = null;
try { cachedStars = sessionStorage.getItem("stars"); } catch {}
if (cachedStars !== null && Number.isFinite(Number(cachedStars))) showStars(Number(cachedStars));
else if (starLinks.length) fetch("https://api.github.com/repos/sinhong2011/triwarden", { headers: { Accept: "application/vnd.github+json" } })
  .then((response) => response.ok ? response.json() : null)
  .then((data) => {
    if (typeof data?.stargazers_count !== "number") return;
    showStars(data.stargazers_count);
    try { sessionStorage.setItem("stars", String(data.stargazers_count)); } catch {}
  }).catch(() => {});

/* ── Language menu: pops open from the button, fades away on close; outside click or Escape closes it. ── */
const lang = $<HTMLDetailsElement>("[data-lang]");
if (lang) {
  const summary = lang.querySelector("summary")!;
  const menu = lang.querySelector<HTMLElement>(".lang__menu")!;
  const items = [...menu.querySelectorAll("li")];
  let closing: gsap.core.Timeline | null = null;

  const open = () => {
    closing?.kill(); closing = null;
    lang.open = true;
    summary.setAttribute("aria-expanded", "true");
    if (reduce) return;
    gsap.fromTo(menu, { autoAlpha: 0, scale: 0.94, y: -8 }, { autoAlpha: 1, scale: 1, y: 0, duration: 0.42, ease: "expo.out", transformOrigin: "100% 0%", overwrite: true });
    gsap.fromTo(items, { autoAlpha: 0, y: -4 }, { autoAlpha: 1, y: 0, duration: 0.3, ease: "power2.out", stagger: 0.03, delay: 0.04, overwrite: true });
  };
  const close = (focus = false) => {
    if (!lang.open || closing) return;
    summary.setAttribute("aria-expanded", "false");
    if (focus) summary.focus();
    if (reduce) { lang.open = false; return; }
    closing = gsap.timeline({ onComplete: () => { lang.open = false; closing = null; gsap.set([menu, ...items], { clearProps: "all" }); } })
      .to(menu, { autoAlpha: 0, scale: 0.97, y: -4, duration: 0.18, ease: "power2.in", transformOrigin: "100% 0%" });
  };

  summary.setAttribute("aria-expanded", "false");
  summary.addEventListener("click", (e) => { e.preventDefault(); lang.open && !closing ? close() : open(); });
  addEventListener("click", (e) => { if (lang.open && !lang.contains(e.target as Node)) close(); });
  addEventListener("keydown", (e) => { if (e.key === "Escape" && lang.open) close(true); });
}

/* ── Section links: one highlight that follows the pointer and rests on the section you're reading. ── */
const linkBar = $("[data-nav-links]");
const indicator = $("[data-nav-indicator]");
if (linkBar && indicator) {
  const links = $$<HTMLAnchorElement>("[data-nav-link]", linkBar);
  let current: HTMLAnchorElement | null = links.find((a) => a.getAttribute("aria-current") === "page") ?? null;
  const pageLink = current;
  const moveTo = (a: HTMLAnchorElement | null) => {
    if (!a) { indicator.classList.remove("is-on"); return; }
    indicator.style.setProperty("--x", `${a.offsetLeft}px`);
    indicator.style.setProperty("--w", `${a.offsetWidth}px`);
    indicator.classList.add("is-on");
  };
  links.forEach((a) => a.addEventListener("pointerenter", () => moveTo(a)));
  linkBar.addEventListener("pointerleave", () => moveTo(current));

  // Which section is on screen: the last one whose top has passed a line a third of the way down.
  const sections = links.flatMap((a) => {
    if (!a.hash || a.pathname !== location.pathname) return [];
    const section = document.getElementById(a.hash.slice(1));
    return section ? [{ section, link: a }] : [];
  });
  const spy = () => {
    const line = innerHeight / 3;
    let active: HTMLAnchorElement | null = pageLink;
    sections.forEach(({ section, link }) => { if (section.getBoundingClientRect().top <= line && section.getBoundingClientRect().bottom > 0) active = link; });
    if (active === current) return;
    current = active;
    links.forEach((a) => (a === current ? a.setAttribute("aria-current", a === pageLink ? "page" : "location") : a.removeAttribute("aria-current")));
    if (!linkBar.matches(":hover")) moveTo(current);
  };
  addEventListener("scroll", spy, { passive: true });
  addEventListener("resize", () => moveTo(current));
  spy();
  moveTo(current);
}

/* ── Menu sheet on narrow screens. ── */
const menuButton = $<HTMLButtonElement>("[data-nav-menu]");
const sheet = $("[data-nav-sheet]");
if (menuButton && sheet) {
  const setOpen = (open: boolean, focusButton = false) => {
    gsap.killTweensOf([sheet, ...sheet.querySelectorAll("a")]);
    menuButton.setAttribute("aria-expanded", String(open));
    menuButton.setAttribute("aria-label", (open ? menuButton.dataset.closeLabel : menuButton.dataset.openLabel) ?? "");
    if (open) {
      if (lang) { lang.open = false; lang.querySelector("summary")?.setAttribute("aria-expanded", "false"); }
      sheet.inert = false;
      sheet.hidden = false;
      if (!reduce) {
        gsap.fromTo(sheet, { autoAlpha: 0, y: -10, scale: 0.98 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.45, ease: "expo.out", transformOrigin: "50% 0%" });
        gsap.fromTo(sheet.querySelectorAll("a"), { autoAlpha: 0, y: -6 }, { autoAlpha: 1, y: 0, duration: 0.35, stagger: 0.035, ease: "power2.out", delay: 0.05 });
      }
    } else if (reduce) {
      sheet.inert = true;
      sheet.hidden = true;
    } else {
      sheet.inert = true;
      gsap.to(sheet, { autoAlpha: 0, y: -6, duration: 0.2, ease: "power2.in", onComplete: () => { sheet.hidden = true; } });
    }
    if (focusButton) menuButton.focus();
  };
  menuButton.addEventListener("click", () => setOpen(menuButton.getAttribute("aria-expanded") !== "true"));
  sheet.addEventListener("click", (e) => { if ((e.target as Element).closest("a")) setOpen(false); });
  addEventListener("keydown", (e) => { if (e.key === "Escape" && menuButton.getAttribute("aria-expanded") === "true") setOpen(false, true); });
  addEventListener("click", (e) => { if (menuButton.getAttribute("aria-expanded") === "true" && !sheet.contains(e.target as Node) && !menuButton.contains(e.target as Node)) setOpen(false); });
  matchMedia("(min-width: 1141px)").addEventListener("change", (e) => { if (e.matches) setOpen(false); });
}
