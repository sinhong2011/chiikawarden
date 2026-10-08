import { loadFont as loadSerif } from "@remotion/google-fonts/InstrumentSerif";
import { loadFont as loadSans } from "@remotion/google-fonts/Geist";
import { loadFont as loadMono } from "@remotion/google-fonts/GeistMono";
import { loadFont as loadCJK } from "@remotion/google-fonts/NotoSerifTC";
import { Easing, interpolate } from "remotion";

export const serif = loadSerif("normal", { weights: ["400"], subsets: ["latin"] }).fontFamily;
loadSerif("italic", { weights: ["400"], subsets: ["latin"] });
export const sans = loadSans("normal", { weights: ["400", "500", "600", "700"], subsets: ["latin"] }).fontFamily;
export const mono = loadMono("normal", { weights: ["400", "500", "600"], subsets: ["latin"] }).fontFamily;
export const cjk = loadCJK("normal", { weights: ["700"] }).fontFamily;

// Brand: tail sky as fills only; navy ink for text and icons.
export const C = {
  paper: "#F3F6F9",
  paper2: "#E9F0F6",
  card: "#FBFCFD",
  ink: "#0B2A40",
  ink2: "#3D5568",
  ink3: "#7B8D9C",
  line: "rgba(11,42,64,.1)",
  line2: "rgba(11,42,64,.16)",
  sky: "#80C5EF",
  night: "#0A1622",
  ok: "#3FB96B",
};

export const expoOut = Easing.bezier(0.16, 1, 0.3, 1);
export const inOut = Easing.bezier(0.65, 0, 0.35, 1);

/** Clamped interpolate with an easing — the workhorse for every move in the film. */
export const tween = (frame: number, from: number, to: number, a: number, b: number, easing = expoOut) =>
  interpolate(frame, [from, to], [a, b], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing });
