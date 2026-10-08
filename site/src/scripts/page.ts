/* Page-wide motion: sticky nav, section reveals, the film and the closing dial. */
import { gsap, ScrollTrigger, reduce, $, $$ } from "./motion";
import { mountDial, RINGS } from "./dial";
import "./release";

const nav = $("[data-nav]")!;
const onScroll = () => nav.classList.toggle("is-stuck", scrollY > 24);
addEventListener("scroll", onScroll, { passive: true });
onScroll();

const closeHost = $("[data-dial='close']");
const close = closeHost && mountDial(closeHost);

if (reduce) {
  close?.state.forEach((s) => (s.base = 0));
} else {
  $$("[data-reveal-group]").forEach((el) => {
    gsap.from(el.children, { y: 34, autoAlpha: 0, duration: 1.1, stagger: 0.09, ease: "expo.out", scrollTrigger: { trigger: el, start: "top 80%" } });
  });
  $$("[data-rise]").forEach((el) => gsap.from(el, { y: 60, autoAlpha: 0, duration: 1.2, ease: "expo.out", scrollTrigger: { trigger: el, start: "top 85%" } }));
  gsap.fromTo("[data-film]", { scale: 0.9, borderRadius: 48 }, { scale: 1, borderRadius: 24, ease: "none", scrollTrigger: { trigger: "[data-film]", start: "top bottom", end: "top 25%", scrub: 0.6 } });

  if (close) {
    ScrollTrigger.create({
      trigger: "#close", start: "top bottom", end: "center center", scrub: 0.8,
      onUpdate: (st) => close.state.forEach((s, i) => (s.base = RINGS[i].apart * (1 - st.progress) * (i === 1 ? 2.2 : 1.6))),
    });
    if (close.bezel) gsap.to(close.bezel, { rotate: 90, svgOrigin: "512 512", ease: "none", scrollTrigger: { trigger: "#close", start: "top bottom", end: "bottom top", scrub: true } });
  }

  // Film: play once it is mostly in view, pause when it leaves.
  const video = $<HTMLVideoElement>("[data-film] video");
  if (video) {
    video.muted = true;
    new IntersectionObserver((es) => es.forEach((e) => {
      if (e.isIntersecting && e.intersectionRatio > 0.6) video.play().catch(() => {});
      else if (!e.isIntersecting) video.pause();
    }), { threshold: [0, 0.6] }).observe(video);
  }
}

// Copy buttons: [data-copy-text] holds the text; an inner [data-copy-label] (or the button) shows feedback.
$$("[data-copy-text]").forEach((btn) => btn.addEventListener("click", async () => {
  const label = $("[data-copy-label]", btn) ?? btn;
  const idle = label.textContent;
  try { await navigator.clipboard.writeText(btn.dataset.copyText!); label.textContent = btn.dataset.copyDone ?? ""; } catch { label.textContent = btn.dataset.copyFail ?? ""; }
  setTimeout(() => (label.textContent = idle), 1400);
}));

// Speed numbers count up the first time they scroll into view.
if (!reduce) $$("[data-count]").forEach((el) => {
  const to = Number(el.dataset.count), digits = Number(el.dataset.digits ?? 0), o = { v: 0 };
  el.textContent = (0).toFixed(digits);
  gsap.to(o, { v: to, duration: 1.6, ease: "expo.out", scrollTrigger: { trigger: el, start: "top 85%" }, onUpdate: () => (el.textContent = o.v.toFixed(digits)) });
});

// FAQ answers slide open (a closed <details> isn't rendered, so CSS alone can't animate it).
$$<HTMLDetailsElement>("details.faq").forEach((d) => d.addEventListener("toggle", () => {
  if (d.open && !reduce) gsap.from($("[data-faq-body]", d), { height: 0, autoAlpha: 0, duration: 0.55, ease: "expo.out", clearProps: "height" });
}));
