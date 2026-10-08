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

/* ── GitHub stars, refreshed in the browser (cached for the session). ── */
const out = $("[data-stars]");
if (out) {
  const link = out.closest<HTMLElement>("a");
  const show = (n: number) => {
    out.textContent = n.toLocaleString(document.documentElement.lang);
    link?.setAttribute("aria-label", (link.dataset.starLabel ?? "").replace("{count}", String(n)));
  };
  let cached: string | null = null;
  try { cached = sessionStorage.getItem("stars"); } catch {}
  if (cached) show(+cached);
  else fetch("https://api.github.com/repos/sinhong2011/triwarden", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : null))
    .then((d) => {
      if (typeof d?.stargazers_count !== "number") return;
      show(d.stargazers_count);
      try { sessionStorage.setItem("stars", String(d.stargazers_count)); } catch {}
    })
    .catch(() => {});
}

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
  let current: HTMLAnchorElement | null = null;
  const moveTo = (a: HTMLAnchorElement | null) => {
    if (!a) { indicator.classList.remove("is-on"); return; }
    indicator.style.setProperty("--x", `${a.offsetLeft}px`);
    indicator.style.setProperty("--w", `${a.offsetWidth}px`);
    indicator.classList.add("is-on");
  };
  links.forEach((a) => a.addEventListener("pointerenter", () => moveTo(a)));
  linkBar.addEventListener("pointerleave", () => moveTo(current));

  // Which section is on screen: the last one whose top has passed a line a third of the way down.
  const sections = links.map((a) => document.querySelector<HTMLElement>(a.hash)).filter(Boolean) as HTMLElement[];
  const spy = () => {
    const line = innerHeight / 3;
    let active: HTMLAnchorElement | null = null;
    sections.forEach((sec, i) => { if (sec.getBoundingClientRect().top <= line && sec.getBoundingClientRect().bottom > 0) active = links[i]; });
    if (active === current) return;
    current = active;
    links.forEach((a) => (a === current ? a.setAttribute("aria-current", "true") : a.removeAttribute("aria-current")));
    if (!linkBar.matches(":hover")) moveTo(current);
  };
  addEventListener("scroll", spy, { passive: true });
  addEventListener("resize", () => moveTo(current));
  spy();
}

/* ── Reading progress: the bar's outline fills as you scroll. ── */
const progress = $("[data-nav-progress]");
if (progress) {
  const update = () => {
    const max = document.documentElement.scrollHeight - innerHeight;
    progress.style.setProperty("--progress", String(max > 0 ? Math.min(1, scrollY / max) : 0));
  };
  addEventListener("scroll", update, { passive: true });
  update();
}

/* ── Menu sheet on narrow screens. ── */
const menuButton = $<HTMLButtonElement>("[data-nav-menu]");
const sheet = $("[data-nav-sheet]");
if (menuButton && sheet) {
  const setOpen = (open: boolean, focusButton = false) => {
    menuButton.setAttribute("aria-expanded", String(open));
    menuButton.setAttribute("aria-label", (open ? menuButton.dataset.closeLabel : menuButton.dataset.openLabel) ?? "");
    if (open) {
      sheet.hidden = false;
      if (!reduce) {
        gsap.fromTo(sheet, { autoAlpha: 0, y: -10, scale: 0.98 }, { autoAlpha: 1, y: 0, scale: 1, duration: 0.45, ease: "expo.out", transformOrigin: "50% 0%" });
        gsap.fromTo(sheet.querySelectorAll("a"), { autoAlpha: 0, y: -6 }, { autoAlpha: 1, y: 0, duration: 0.35, stagger: 0.035, ease: "power2.out", delay: 0.05 });
      }
    } else if (reduce) {
      sheet.hidden = true;
    } else {
      gsap.to(sheet, { autoAlpha: 0, y: -6, duration: 0.2, ease: "power2.in", onComplete: () => { sheet.hidden = true; } });
    }
    if (focusButton) menuButton.focus();
  };
  menuButton.addEventListener("click", () => setOpen(menuButton.getAttribute("aria-expanded") !== "true"));
  sheet.addEventListener("click", (e) => { if ((e.target as Element).closest("a")) setOpen(false); });
  addEventListener("keydown", (e) => { if (e.key === "Escape" && menuButton.getAttribute("aria-expanded") === "true") setOpen(false, true); });
  matchMedia("(min-width: 1141px)").addEventListener("change", (e) => { if (e.matches) { sheet.hidden = true; menuButton.setAttribute("aria-expanded", "false"); } });
}
