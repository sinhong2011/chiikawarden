import { gsap, reduce, $, $$ } from "./motion";

const root = $("[data-screens]");
if (root) {
  const tabs = $$<HTMLButtonElement>("[data-tab]", root);
  const shots = $$("[data-shot]", root);
  const caption = $("[data-screens-caption]", root)!;
  const captions: string[] = JSON.parse($("[data-screens-captions]", root)!.textContent!);
  let current = 0, auto: ReturnType<typeof setInterval> | undefined, userPicked = false;

  const show = (next: number, focus = false) => {
    if (next === current) return;
    const from = shots[current], to = shots[next];
    tabs.forEach((t, i) => { t.setAttribute("aria-selected", String(i === next)); t.tabIndex = i === next ? 0 : -1; });
    if (focus) tabs[next].focus();
    // Keep the chosen tab visible in the strip without ever scrolling the page.
    const strip = tabs[next].parentElement!, t = tabs[next];
    if (t.offsetLeft < strip.scrollLeft || t.offsetLeft + t.offsetWidth > strip.scrollLeft + strip.clientWidth)
      strip.scrollTo({ left: t.offsetLeft - 8, behavior: reduce ? "auto" : "smooth" });
    caption.textContent = captions[next];
    if (reduce) {
      gsap.set(from, { autoAlpha: 0 });
      gsap.set(to, { autoAlpha: 1, scale: 1 });
    } else {
      gsap.to(from, { autoAlpha: 0, scale: 0.985, duration: 0.45, ease: "power2.out" });
      gsap.fromTo(to, { autoAlpha: 0, scale: 1.02 }, { autoAlpha: 1, scale: 1, duration: 0.8, ease: "expo.out" });
      gsap.fromTo(caption, { y: 8, autoAlpha: 0 }, { y: 0, autoAlpha: 1, duration: 0.6, ease: "expo.out" });
    }
    current = next;
  };

  const stop = () => { userPicked = true; clearInterval(auto); };
  tabs.forEach((t, i) => t.addEventListener("click", () => { stop(); show(i); }));
  root.addEventListener("keydown", (e) => {
    if (!(e.target as Element).matches("[data-tab]")) return;
    const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
    if (!step) return;
    e.preventDefault(); stop();
    show((current + step + tabs.length) % tabs.length, true);
  });

  // Tour the screens while they're on screen, until someone picks one.
  if (!reduce) {
    new IntersectionObserver(([e]) => {
      clearInterval(auto);
      if (e.isIntersecting && !userPicked) auto = setInterval(() => show((current + 1) % tabs.length), 4200);
    }, { threshold: 0.4 }).observe(root);
    gsap.from($("[data-screens-stage]", root), { y: 70, scale: 0.94, autoAlpha: 0, duration: 1.3, ease: "expo.out", scrollTrigger: { trigger: root, start: "top 80%" } });
  }
}
