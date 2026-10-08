import { gsap, ScrollTrigger, reduce, $ } from "./motion";
import { mountDial, RINGS } from "./dial";

const host = $("[data-dial='hero']");
if (host) {
  const hero = mountDial(host);
  const readout = $("[data-readout]")!;
  gsap.ticker.add(() => {
    const r = hero.state.map((s) => ((((s.base + s.ptr + s.scroll) % 360) + 540) % 360 - 180).toFixed(1));
    readout.textContent = `ROTOR ${r[0]}° · ${r[1]}° · ${r[2]}°`;
  });

  if (reduce) {
    hero.state.forEach((s) => (s.base = 0));
  } else {
    const tl = gsap.timeline({ defaults: { ease: "expo.out" } });
    gsap.set(".hero-line > *", { yPercent: 110 });
    gsap.set("[data-reveal]", { y: 18, autoAlpha: 0 });
    gsap.set(hero.svg, { scale: 0.86, autoAlpha: 0, rotate: -8, transformOrigin: "50% 50%" });
    gsap.set(hero.paths, { attr: { "stroke-dasharray": "0 1" } });
    gsap.set(hero.hub, { scale: 0, svgOrigin: "512 540" });
    hero.state.forEach((s, i) => (s.base = RINGS[i].apart + [-200, 260, -160][i]));

    tl.to(".hero-line > *", { yPercent: 0, duration: 1.4, stagger: 0.12 }, 0.1)
      .to("[data-reveal]", { y: 0, autoAlpha: 1, duration: 1.1, stagger: 0.08 }, 0.45)
      .to(hero.svg, { scale: 1, autoAlpha: 1, rotate: 0, duration: 1.8 }, 0)
      .to(hero.paths, { attr: { "stroke-dasharray": "1 0" }, duration: 1.6, stagger: 0.12, ease: "power3.inOut" }, 0.2);
    hero.state.forEach((s, i) => tl.to(s, { base: RINGS[i].apart, duration: 1.9 }, 0.2 + i * 0.1));
    // The rings ratchet into line, inside first, each landing with a click of the hub.
    [2, 1, 0].forEach((i, k) => {
      const at = 2.3 + k * 0.55;
      tl.to(hero.state[i], { base: 0, duration: 0.9, ease: "power4.inOut" }, at);
      tl.fromTo(hero.hub, { scale: k === 0 ? 0 : 1 }, { scale: k === 0 ? 1 : 1.06, duration: 0.25, ease: "power2.out", yoyo: k !== 0, repeat: k !== 0 ? 1 : 0 }, at + 0.75);
    });
    if (hero.bezel) tl.to(hero.bezel, { rotate: 30, svgOrigin: "512 512", duration: 2.4, ease: "power3.inOut" }, 2.2);

    // The dial follows the pointer: each ring a little more than the one inside it.
    const ptr = hero.state.map((s, i) => gsap.quickTo(s, "ptr", { duration: 1.4 + i * 0.3, ease: "expo.out" }));
    addEventListener("pointermove", (e) => {
      if (scrollY > innerHeight) return;
      const a = (e.clientX / innerWidth - 0.5) * 26 + (e.clientY / innerHeight - 0.5) * 10;
      ptr[0](a); ptr[1](-a * 0.8); ptr[2](a * 0.6);
    }, { passive: true });

    // Scrolling away turns the rings apart again.
    ScrollTrigger.create({
      trigger: "#top", start: "top top", end: "bottom top", scrub: 0.6,
      onUpdate: ({ progress: p }) => {
        hero.state[0].scroll = p * -150; hero.state[1].scroll = p * 110; hero.state[2].scroll = p * -80;
      },
    });
    gsap.to(host, { yPercent: 18, ease: "none", scrollTrigger: { trigger: "#top", start: "top top", end: "bottom top", scrub: true } });
    gsap.to("[data-hero-copy]", { yPercent: -10, autoAlpha: 0.2, ease: "none", scrollTrigger: { trigger: "#top", start: "40% top", end: "bottom top", scrub: true } });
  }
}
