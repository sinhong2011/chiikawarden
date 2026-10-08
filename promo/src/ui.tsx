import React from "react";
import { AbsoluteFill, Img, staticFile, useCurrentFrame } from "remotion";
import { C, mono, serif, tween } from "./theme";

export const Paper: React.FC<{ children?: React.ReactNode; dark?: boolean }> = ({ children, dark }) => (
  <AbsoluteFill
    style={{
      background: dark
        ? C.night
        : `radial-gradient(1400px 800px at 60% 45%, #FFFFFF 0%, rgba(255,255,255,0) 60%), repeating-linear-gradient(90deg, rgba(11,42,64,.035) 0 1px, transparent 1px 120px), ${C.paper}`,
    }}
  >
    {children}
  </AbsoluteFill>
);

/** A line of text that rises out of a mask. */
export const Rise: React.FC<{ at: number; children: React.ReactNode; style?: React.CSSProperties; dur?: number }> = ({ at, children, style, dur = 26 }) => {
  const f = useCurrentFrame();
  const y = tween(f, at, at + dur, 110, 0);
  return (
    <span style={{ display: "block", overflow: "hidden", paddingBottom: "0.26em", marginBottom: "-0.18em", ...style }}>
      <span style={{ display: "inline-block", transform: `translateY(${y}%)` }}>{children}</span>
    </span>
  );
};

export const Kicker: React.FC<{ at: number; children: React.ReactNode; color?: string }> = ({ at, children, color = C.ink3 }) => {
  const f = useCurrentFrame();
  return (
    <div style={{ font: `500 22px/1 ${mono}`, letterSpacing: ".16em", textTransform: "uppercase", color, opacity: tween(f, at, at + 18, 0, 1), transform: `translateY(${tween(f, at, at + 24, 12, 0)}px)` }}>
      {children}
    </div>
  );
};

export const Headline: React.FC<{ at: number; lines: React.ReactNode[]; size?: number; color?: string; align?: "left" | "center" }> = ({ at, lines, size = 112, color = C.ink, align = "left" }) => (
  <div style={{ font: `400 ${size}px/.96 ${serif}`, letterSpacing: "-.025em", color, textAlign: align }}>
    {lines.map((l, i) => <Rise key={i} at={at + i * 5}>{l}</Rise>)}
  </div>
);

export const Em: React.FC<{ children: React.ReactNode; color?: string }> = ({ children, color = C.ink3 }) => (
  <em style={{ fontStyle: "italic", color }}>{children}</em>
);

export const Tile: React.FC<{ letter: string; size?: number }> = ({ letter, size = 56 }) => (
  <span style={{ width: size, height: size, borderRadius: size * 0.27, display: "grid", placeItems: "center", background: "#fff", boxShadow: `0 0 0 1.5px ${C.line}, 0 1px 3px rgba(11,42,64,.08)`, fontWeight: 600, fontSize: size * 0.4, color: C.ink2, flex: "none" }}>
    {letter}
  </span>
);

export const Kbd: React.FC<{ children: React.ReactNode; size?: number; style?: React.CSSProperties }> = ({ children, size = 30, style }) => (
  <span style={{ font: `500 ${size * 0.5}px/1 ${mono}`, display: "inline-grid", placeItems: "center", minWidth: size, height: size, padding: `0 ${size * 0.25}px`, borderRadius: size * 0.27, background: C.card, boxShadow: `0 0 0 1.5px ${C.line2}, 0 2px 0 ${C.line2}`, color: C.ink2, ...style }}>
    {children}
  </span>
);

/** Countdown ring like the app's one-time-code timer. */
export const Timer: React.FC<{ left: number; size?: number }> = ({ left, size = 64 }) => (
  <div style={{ width: size, height: size, position: "relative" }}>
    <svg viewBox="0 0 46 46" width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
      <circle cx="23" cy="23" r="19" fill="none" stroke="rgba(11,42,64,.1)" strokeWidth="4" />
      <circle cx="23" cy="23" r="19" fill="none" stroke="#3F86C4" strokeWidth="4" strokeLinecap="round" pathLength={30} strokeDasharray="30 30" strokeDashoffset={30 - left} />
    </svg>
    <span style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", font: `600 ${size * 0.28}px ${mono}`, color: C.ink2 }}>{Math.ceil(left)}</span>
  </div>
);

export const Toast: React.FC<{ at: number; until: number; children: React.ReactNode; style?: React.CSSProperties }> = ({ at, until, children, style }) => {
  const f = useCurrentFrame();
  const o = Math.min(tween(f, at, at + 10, 0, 1), tween(f, until, until + 10, 1, 0));
  return (
    <div style={{ position: "absolute", left: "50%", padding: "18px 30px", borderRadius: 999, background: "rgba(11,42,64,.94)", color: "#F3F6F9", font: "500 26px/1 inherit", whiteSpace: "nowrap", opacity: o, transform: `translate(-50%, ${tween(f, at, at + 18, 24, 0)}px)`, boxShadow: "0 20px 40px -12px rgba(11,42,64,.5)", ...style }}>
      {children}
    </div>
  );
};

/** Part of a real app capture (public/shots, 2704 × 2084 windows): the source rect [x, y, w, h] fills a box `width`
    wide; `zoom` pushes in around the box's centre. */
export const Crop: React.FC<{ src: string; rect: [number, number, number, number]; width: number; zoom?: number; radius?: number; style?: React.CSSProperties }> = ({ src, rect: [x, y, w, h], width, zoom = 1, radius = 24, style }) => {
  const k = width / w;
  return (
    <div style={{ width, height: h * k, borderRadius: radius, overflow: "hidden", position: "relative", boxShadow: "0 0 0 1.5px rgba(11,42,64,.12), 0 50px 100px -40px rgba(11,42,64,.5)", ...style }}>
      <div style={{ position: "absolute", inset: 0, transform: `scale(${zoom})` }}>
        <Img src={staticFile(src)} style={{ position: "absolute", left: -x * k, top: -y * k, width: 2704 * k, maxWidth: "none" }} />
      </div>
    </div>
  );
};
