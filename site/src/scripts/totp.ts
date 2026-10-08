/* Demo one-time codes: deterministic per item name and 30-second step, so every widget agrees. */
import { $$ } from "./motion";

function hash(str: string) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}

export const totp = (name: string, t = Date.now()) => String(hash(`${name}:${Math.floor(t / 30000)}`) % 1e6).padStart(6, "0");
export const fmt = (c: string) => `${c.slice(0, 3)} ${c.slice(3)}`;
export const secsLeft = () => 30 - ((Date.now() / 1000) % 30);

let ticking = false;
/** Keeps every `[data-code="Item"]` element showing that item's current code. */
export function tickCodes() {
  const run = () => $$("[data-code]").forEach((el) => {
    const next = fmt(totp(el.dataset.code!));
    if (el.textContent !== next) el.textContent = next;
  });
  run();
  if (!ticking) { ticking = true; setInterval(run, 1000); }
}
