import { gsap, reduce, $, $$ } from "./motion";
import { tickCodes } from "./totp";

tickCodes();

if (!reduce) {
  $$("[data-row]").forEach((row) => {
    const tl = gsap.timeline({ scrollTrigger: { trigger: row, start: "top 78%" } });
    tl.from($(".row__no", row), { y: 30, autoAlpha: 0, duration: 0.9, ease: "expo.out" })
      .from($(".row__text", row), { y: 24, autoAlpha: 0, duration: 0.9, ease: "expo.out" }, "<.08")
      .from($(".row__demo", row), { y: 40, autoAlpha: 0, scale: 0.97, duration: 1.1, ease: "expo.out" }, "<.08");
    const lines = $$(".term p", row);
    if (lines.length) tl.from(lines, { autoAlpha: 0, x: -8, duration: 0.35, stagger: 0.45, ease: "power2.out" }, "<.4");
    const keys = $$(".keys__row", row);
    if (keys.length) tl.from(keys, { autoAlpha: 0, x: -10, duration: 0.5, stagger: 0.08, ease: "expo.out" }, "<.3");
  });
}
