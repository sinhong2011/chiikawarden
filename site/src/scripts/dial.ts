/* The three-ring dial — same geometry as Design/AppIcon/generate.py: rings of radius 270 / 202 / 134, stroke 40, one
   notch each. Rotation 0 puts a notch at 6 o'clock, under the keyhole, all three in line; `apart` is the icon's resting angle. */
import { gsap, $, $$ } from "./motion";

const C = 512, STROKE = 40, GAP = 30;
export const RINGS = [
  // Colours come from --dial-<name>-0/1 in global.css (light, and the icon's dark palette).
  { name: "outer", r: 270, apart: -135 },
  { name: "middle", r: 202, apart: 75 },
  { name: "inner", r: 134, apart: -30 },
] as const;

export type RingState = { base: number; ptr: number; scroll: number };
export type Dial = {
  svg: SVGSVGElement;
  rings: SVGGElement[];
  paths: SVGPathElement[];
  state: RingState[];
  hub: SVGGElement;
  bezel: SVGGElement | null;
};

let uid = 0;
const live: Dial[] = [];

function ringPath(r: number) {
  const half = Math.asin((GAP + STROKE) / 2 / r);
  const a0 = Math.PI / 2 + half, a1 = Math.PI / 2 - half + 2 * Math.PI;
  const p = (a: number) => `${(C + r * Math.cos(a)).toFixed(1)} ${(C + r * Math.sin(a)).toFixed(1)}`;
  return `M${p(a0)} A${r} ${r} 0 1 1 ${p(a1)}`;
}

function render(d: Dial) {
  d.rings.forEach((el, i) => {
    const s = d.state[i];
    el.setAttribute("transform", `rotate(${(s.base + s.ptr + s.scroll).toFixed(2)} 512 512)`);
  });
}

/** Draws a dial into `host` and keeps it rendered from its ring state on every GSAP tick. */
export function mountDial(host: HTMLElement, { bezel = true, door = true } = {}): Dial {
  const id = `d${uid++}`;
  let s = `<svg class="dial" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg"><defs>`;
  s += `<linearGradient id="${id}door" x1="0" y1="0" x2="0" y2="1"><stop offset="0" style="stop-color:var(--dial-door-0)"/><stop offset="1" style="stop-color:var(--dial-door-1)"/></linearGradient>`;
  s += `<linearGradient id="${id}bez" x1="0" y1="0" x2="1" y2="1"><stop offset="0" style="stop-color:var(--dial-bez-0)"/><stop offset=".5" style="stop-color:var(--dial-bez-1)"/><stop offset="1" style="stop-color:var(--dial-bez-2)"/></linearGradient>`;
  s += `<linearGradient id="${id}hub" gradientUnits="userSpaceOnUse" x1="0" y1="440" x2="0" y2="600"><stop offset="0" style="stop-color:var(--dial-hub-0)"/><stop offset="1" style="stop-color:var(--dial-hub-1)"/></linearGradient>`;
  s += `<filter id="${id}sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="28" stdDeviation="34" style="flood-color:var(--dial-shadow)" flood-opacity=".22"/></filter>`;
  RINGS.forEach((g, i) => {
    s += `<linearGradient id="${id}r${i}" gradientUnits="userSpaceOnUse" x1="0" y1="${C - g.r}" x2="0" y2="${C + g.r}"><stop offset="0" style="stop-color:var(--dial-${g.name}-0)"/><stop offset="1" style="stop-color:var(--dial-${g.name}-1)"/></linearGradient>`;
  });
  s += `</defs>`;
  if (bezel) {
    s += `<g class="bezel"><circle cx="512" cy="512" r="470" fill="url(#${id}bez)" filter="url(#${id}sh)"/>`;
    s += `<circle cx="512" cy="512" r="470" fill="none" style="stroke:var(--dial-tick)" stroke-opacity=".08" stroke-width="2"/>`;
    s += `<circle cx="512" cy="512" r="384" fill="none" style="stroke:var(--dial-tick)" stroke-opacity=".08" stroke-width="2"/>`;
    for (let i = 0; i < 120; i++) {
      const a = (i / 120) * Math.PI * 2 - Math.PI / 2;
      const major = i % 10 === 0, mid = i % 5 === 0;
      const r1 = major ? 420 : mid ? 430 : 440;
      s += `<line x1="${(C + 452 * Math.cos(a)).toFixed(1)}" y1="${(C + 452 * Math.sin(a)).toFixed(1)}" x2="${(C + r1 * Math.cos(a)).toFixed(1)}" y2="${(C + r1 * Math.sin(a)).toFixed(1)}" style="stroke:var(--dial-tick)" stroke-opacity="${major ? 0.55 : 0.22}" stroke-width="${major ? 3 : 1.6}" stroke-linecap="round"/>`;
    }
    s += `</g><path d="M512 26 l-12 -20 h24 z" style="fill:var(--dial-tick)" fill-opacity=".7"/>`;
  }
  if (door) {
    s += `<circle cx="512" cy="512" r="344" fill="url(#${id}door)" ${bezel ? "" : `filter="url(#${id}sh)"`}/>`;
    s += `<circle cx="512" cy="512" r="336" fill="none" style="stroke:var(--dial-rim)" stroke-opacity=".10" stroke-width="12"/>`;
  }
  RINGS.forEach((g, i) => {
    s += `<g class="ring"><path d="${ringPath(g.r)}" pathLength="1" fill="none" stroke="url(#${id}r${i})" stroke-width="${STROKE}" stroke-linecap="round"/></g>`;
  });
  s += `<g class="hub"><circle cx="512" cy="488" r="46" fill="url(#${id}hub)"/><path d="M494 500 L530 500 L540 592 Q541 604 529 604 L495 604 Q483 604 484 592 Z" fill="url(#${id}hub)"/></g></svg>`;
  host.innerHTML = s;

  const svg = host.firstElementChild as SVGSVGElement;
  const rings = $$<SVGGElement>(".ring", svg);
  const d: Dial = {
    svg,
    rings,
    paths: rings.map((r) => r.firstElementChild as SVGPathElement),
    state: RINGS.map((g) => ({ base: g.apart, ptr: 0, scroll: 0 })),
    hub: $<SVGGElement>(".hub", svg)!,
    bezel: $<SVGGElement>(".bezel", svg),
  };
  render(d);
  if (!live.length) gsap.ticker.add(() => live.forEach(render));
  live.push(d);
  return d;
}
