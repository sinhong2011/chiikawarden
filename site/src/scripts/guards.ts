import { gsap, ScrollTrigger, $, $$, reduce } from "./motion";
import { mountDial, RINGS } from "./dial";

// The security section: four cards (three locks, then the door open) beside the dial. The card in focus turns the dial
// to it; while the section is in view and nobody is pointing at a card, it steps through them every few seconds.
const host = $("[data-dial='guards']");
if (host) {
  const dial = mountDial(host, { bezel: false });
  const steps = $$("[data-step]");
  let active = -1;
  let held = false; // a card is hovered or focused: stay on it
  let timer: ReturnType<typeof setInterval> | undefined;

  const setStep = (n: number) => {
    if (n === active) return;
    active = n;
    steps.forEach((el, i) => el.classList.toggle("is-on", i === n));
    const t = reduce ? 0 : 1;
    dial.rings.forEach((el, i) => {
      const aligned = n === 3 || i <= n;
      gsap.to(dial.state[i], { base: aligned ? 0 : RINGS[i].apart, duration: 1.2 * t, ease: "expo.inOut" });
      gsap.to(el, { opacity: n === 3 || i === n ? 1 : aligned ? 0.55 : 0.18, duration: 0.6 * t });
    });
    gsap.to(dial.hub, { scale: n === 3 ? 1.12 : 1, opacity: n === 3 ? 1 : 0.35, svgOrigin: "512 540", duration: 0.8 * t, ease: "expo.out" });
  };

  const stop = () => { clearInterval(timer); timer = undefined; };
  const play = () => {
    if (reduce || timer) return;
    timer = setInterval(() => { if (!held) setStep((active + 1) % steps.length); }, 3200);
  };

  gsap.set(dial.hub, { opacity: 0.35 });
  dial.rings.forEach((el) => gsap.set(el, { opacity: 0.18 }));
  steps.forEach((el, i) => {
    const hold = () => { held = true; setStep(i); };
    const release = () => { held = false; };
    el.addEventListener("pointerenter", hold);
    el.addEventListener("pointerleave", release);
    el.addEventListener("focus", hold);
    el.addEventListener("blur", release);
  });
  ScrollTrigger.create({
    trigger: "#security", start: "top 70%", end: "bottom 30%",
    onToggle: (st) => { if (st.isActive) { if (active < 0) setStep(0); play(); } else stop(); },
  });
}
