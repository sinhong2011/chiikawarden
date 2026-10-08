/* SSH agent guide: the flow diagram's request and signature travelling between ssh, the agent, Triwarden and you. */
import { gsap, reduce, $ } from "./motion";

const flow = $("[data-flow]");
if (flow && !reduce) {
  const req = $<SVGCircleElement>("[data-flow-req]", flow)!;
  const sig = $<SVGCircleElement>("[data-flow-sig]", flow)!;
  const you = $(".flow__node--you", flow);
  const app = $(".flow__node--app", flow);
  gsap.set([req, sig], { autoAlpha: 0 });
  const tl = gsap.timeline({ repeat: -1, repeatDelay: 0.8, paused: true });
  tl.set(req, { attr: { cx: 180, cy: 92 }, autoAlpha: 1 })
    .to(req, { attr: { cx: 880 }, duration: 1.6, ease: "power2.inOut" })
    .to(req, { autoAlpha: 0, duration: 0.15 })
    .fromTo(you, { scale: 1 }, { scale: 1.06, svgOrigin: "950 130", duration: 0.2, yoyo: true, repeat: 1, ease: "power2.out" }, "<")
    .fromTo(app, { scale: 1 }, { scale: 1.05, svgOrigin: "670 130", duration: 0.2, yoyo: true, repeat: 1, ease: "power2.out" }, ">.15")
    .set(sig, { attr: { cx: 880, cy: 168 }, autoAlpha: 1 })
    .to(sig, { attr: { cx: 180 }, duration: 1.6, ease: "power2.inOut" })
    .to(sig, { autoAlpha: 0, duration: 0.15 });
  new IntersectionObserver(([e]) => (e.isIntersecting ? tl.play() : tl.pause()), { threshold: 0.3 }).observe(flow);
}
