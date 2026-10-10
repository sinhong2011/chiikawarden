// Live WebGPU backdrops from the open-source `shaders` library (MIT, shaders.com; its licence ships as
// public/licenses/shaders.txt). Each `[data-shader="name"]` element gets a canvas; the element's own CSS background
// is the fallback, so a browser without WebGPU, a failed device or a slow load still shows a finished page. The
// library is fetched only when a backdrop is near the viewport and the main thread is idle, telemetry is off, and
// reduced motion freezes every layer. astro.config.mjs keeps the bundle to the effects used here (SHADERS_USED).
import type { ShaderInstance, PresetConfig } from "shaders/js";

type Theme = "light" | "dark";
type Preset = (theme: Theme, still: boolean) => PresetConfig;

const root = document.documentElement;
const theme = (): Theme =>
  (root.dataset.theme ?? (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")) as Theme;
const still = matchMedia("(prefers-reduced-motion: reduce)").matches;

// Brand palette per theme: sky stays a fill, never text.
const PAL = {
  light: { base: "#F3F6F9", mist: "#E3EEF6", sky: "#80C5EF", sky2: "#A9DAF7", deep: "#4F9FD3", ink: "#0B2A40" },
  dark: { base: "#0B1620", mist: "#102233", sky: "#80C5EF", sky2: "#2F6A92", deep: "#173A55", ink: "#E6EEF4" },
};

const stops = (cs: string[]) => cs.map((color, i) => ({ color, position: i / (cs.length - 1) }));

const PRESETS: Record<string, Preset> = {
  // Hero: a slow mesh of brand blues behind fluted glass, rippling where the cursor passes.
  hero: (t, s) => {
    const p = PAL[t];
    const mesh = {
      type: "MeshGradient", id: "mesh",
      props: {
        stops: stops(t === "light" ? [p.base, p.sky2, p.mist, p.sky, p.base] : [p.base, p.deep, p.mist, p.sky2, p.base]),
        count: 6, smoothness: 2.6, variation: 0.5, swirl: 0.25, drift: 0.6, speed: s ? 0 : 0.35, seed: 11,
      },
    };
    const glass = {
      type: "FlutedGlass", id: "glass",
      props: { shape: "bars", angle: 0, frequency: 16, softness: 0.7, refraction: 1.1, aberration: 0.25, highlight: t === "light" ? 0.35 : 0.18, highlightSoftness: 0.5, speed: s ? 0 : 0.02 },
      children: [mesh],
    };
    const top = s ? glass : { type: "CursorRipples", id: "ripple", props: { intensity: 6, decay: 6, radius: 0.4, chromaticSplit: 0.6 }, children: [glass] };
    return { components: [{ type: "FilmGrain", id: "grain", props: { strength: t === "light" ? 0.12 : 0.14, bias: 1 }, children: [top] }] };
  },
  // Product stage: a calmer, deeper field the screenshots sit on.
  stage: (t, s) => {
    const p = PAL[t];
    return {
      components: [{
        type: "FilmGrain", id: "grain", props: { strength: 0.15, bias: 1 },
        children: [{
          type: "MeshGradient", id: "mesh",
          props: {
            stops: stops(t === "light" ? [p.mist, p.sky, p.deep, p.sky2, p.base] : [p.base, p.deep, p.sky2, p.mist, p.base]),
            count: 6, smoothness: 2.2, variation: 0.5, swirl: -0.2, drift: 0.5, speed: s ? 0 : 0.25, seed: 4,
          },
        }],
      }],
    };
  },
  // Closing: diagonal fluted glass over a bright mesh, like light through a frosted door.
  close: (t, s) => {
    const p = PAL[t];
    return {
      components: [{
        type: "FilmGrain", id: "grain", props: { strength: 0.14, bias: 1 },
        children: [{
          type: "FlutedGlass", id: "glass",
          props: { shape: "waves", angle: 20, frequency: 9, softness: 0.6, waveAmplitude: 0.05, waveFrequency: 1.2, refraction: 1.6, aberration: 0.3, highlight: 0.3, speed: s ? 0 : 0.04 },
          children: [{
            type: "MeshGradient", id: "mesh",
            props: {
              stops: stops(t === "light" ? [p.sky, p.base, p.sky2, p.deep, p.sky] : [p.base, p.sky2, p.deep, p.sky, p.base]),
              count: 5, smoothness: 2.2, variation: 0.4, swirl: 0.35, drift: 0.7, speed: s ? 0 : 0.4, seed: 23,
            },
          }],
        }],
      }],
    };
  },
};

type Mounted = { el: HTMLElement; canvas: HTMLCanvasElement; name: string; shader?: ShaderInstance; theme?: Theme };
const mounted: Mounted[] = [];
let lib: Promise<typeof import("shaders/js")> | undefined;

// Chrome on many Macs returns no adapter for powerPreference "high-performance" (no discrete GPU) and
// then draws nothing. Ask again with the default adapter, then the integrated one. One device is shared.
let gpuPromise: Promise<{ device: GPUDevice; adapter: GPUAdapter } | null> | undefined;
function sharedGpu() {
  gpuPromise ??= (async () => {
    if (!navigator.gpu) return null;
    for (const powerPreference of ["high-performance", undefined, "low-power"] as const) {
      try {
        const adapter = await navigator.gpu.requestAdapter(powerPreference ? { powerPreference } : undefined);
        if (!adapter) continue;
        return { device: await adapter.requestDevice(), adapter };
      } catch { /* this adapter can't build a device; try the next */ }
    }
    return null;
  })();
  return gpuPromise;
}

async function build(m: Mounted) {
  if (!("gpu" in navigator)) return; // no WebGPU: keep the CSS backdrop, skip the download
  lib ??= import("shaders/js");
  const [{ createShader, isWebGPUSupported }, gpu] = await Promise.all([lib, sharedGpu()]);
  if (!isWebGPUSupported()) return;
  const t = theme();
  m.shader?.destroy();
  m.theme = t;
  // Paint at full opacity before the context is created. Chrome never presents a canvas that was opacity 0.
  m.canvas.style.opacity = "1";
  m.shader = await createShader(m.canvas, PRESETS[m.name](t, still), {
    disableTelemetry: true,
    gpu: gpu ?? undefined,
    onReady: () => m.el.classList.add("shader-ready"),
    onError: () => m.el.classList.remove("shader-ready"),
  });
  const rect = m.canvas.getBoundingClientRect();
  if (rect.width > 0 && rect.height > 0) m.shader.resize(rect.width, rect.height);
}

function mount(el: HTMLElement) {
  const name = el.dataset.shader!;
  if (!PRESETS[name]) return;
  const canvas = document.createElement("canvas");
  canvas.className = "shader-canvas";
  // createShader pins an unsized canvas to its first pixel size; percentages keep it following the element.
  canvas.style.width = canvas.style.height = "100%";
  canvas.setAttribute("aria-hidden", "true");
  el.prepend(canvas);
  const m: Mounted = { el, canvas, name };
  mounted.push(m);
  // Start once the backdrop is close; the library's own observer pauses it off-screen afterwards.
  const io = new IntersectionObserver((entries) => {
    if (!entries.some((e) => e.isIntersecting)) return;
    io.disconnect();
    // After first paint settles: the CSS backdrop carries the page until then.
    const go = () => build(m).catch(() => {});
    "requestIdleCallback" in window ? requestIdleCallback(go, { timeout: 1500 }) : setTimeout(go, 300);
  }, { rootMargin: "300px" });
  io.observe(el);
}

document.querySelectorAll<HTMLElement>("[data-shader]").forEach(mount);

// Rebuild with the other palette when the theme flips.
const rebuild = () => mounted.forEach((m) => m.shader && m.theme !== theme() && build(m).catch(() => {}));
new MutationObserver(rebuild).observe(root, { attributes: true, attributeFilter: ["data-theme"] });
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", rebuild);
