import React, { useId } from "react";

/* The three-ring dial — same geometry as Design/AppIcon/generate.py.
   Rotation 0 puts a ring's notch at 6 o'clock, under the keyhole, all three in line. */
const CX = 512, STROKE = 40, GAP = 30;
export const RINGS = [
  { r: 270, apart: -135, grad: ["#A9DAF7", "#6DBBEB"] },
  { r: 202, apart: 75, grad: ["#4AA8E4", "#2283C9"] },
  { r: 134, apart: -30, grad: ["#1670AE", "#0A4E80"] },
] as const;

const ringPath = (r: number) => {
  const half = Math.asin((GAP + STROKE) / 2 / r);
  const a0 = Math.PI / 2 + half, a1 = Math.PI / 2 - half + 2 * Math.PI;
  const p = (a: number) => `${(CX + r * Math.cos(a)).toFixed(1)} ${(CX + r * Math.sin(a)).toFixed(1)}`;
  return `M${p(a0)} A${r} ${r} 0 1 1 ${p(a1)}`;
};

type Props = {
  size: number;
  rot: readonly [number, number, number];
  draw?: readonly [number, number, number];
  opacity?: readonly [number, number, number];
  hub?: number;
  hubOpacity?: number;
  bezel?: boolean;
  bezelRot?: number;
  door?: boolean;
  style?: React.CSSProperties;
};

export const Dial: React.FC<Props> = ({
  size, rot, draw = [1, 1, 1], opacity = [1, 1, 1], hub = 1, hubOpacity = 1, bezel = false, bezelRot = 0, door = true, style,
}) => {
  const id = useId().replace(/:/g, "");
  const ticks = [];
  if (bezel) {
    for (let i = 0; i < 120; i++) {
      const a = (i / 120) * Math.PI * 2 - Math.PI / 2;
      const major = i % 10 === 0, mid = i % 5 === 0;
      const r1 = major ? 420 : mid ? 430 : 440;
      ticks.push(
        <line key={i} x1={CX + 452 * Math.cos(a)} y1={CX + 452 * Math.sin(a)} x2={CX + r1 * Math.cos(a)} y2={CX + r1 * Math.sin(a)}
          stroke="#0B2A40" strokeOpacity={major ? 0.55 : 0.22} strokeWidth={major ? 3 : 1.6} strokeLinecap="round" />,
      );
    }
  }
  return (
    <svg viewBox="0 0 1024 1024" width={size} height={size} style={{ overflow: "visible", ...style }}>
      <defs>
        <linearGradient id={`${id}door`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#FFFFFF" /><stop offset="1" stopColor="#E4F2FB" /></linearGradient>
        <linearGradient id={`${id}bez`} x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#FFFFFF" /><stop offset=".5" stopColor="#E7EEF4" /><stop offset="1" stopColor="#D3DEE8" /></linearGradient>
        <linearGradient id={`${id}hub`} gradientUnits="userSpaceOnUse" x1="0" y1="440" x2="0" y2="600"><stop offset="0" stopColor="#1670AE" /><stop offset="1" stopColor="#0A4E80" /></linearGradient>
        <filter id={`${id}sh`} x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="28" stdDeviation="34" floodColor="#0B2A40" floodOpacity=".22" /></filter>
        {RINGS.map((g, i) => (
          <linearGradient key={i} id={`${id}r${i}`} gradientUnits="userSpaceOnUse" x1="0" y1={CX - g.r} x2="0" y2={CX + g.r}>
            <stop offset="0" stopColor={g.grad[0]} /><stop offset="1" stopColor={g.grad[1]} />
          </linearGradient>
        ))}
      </defs>
      {bezel && (
        <g transform={`rotate(${bezelRot} 512 512)`}>
          <circle cx="512" cy="512" r="470" fill={`url(#${id}bez)`} filter={`url(#${id}sh)`} />
          <circle cx="512" cy="512" r="470" fill="none" stroke="#0B2A40" strokeOpacity=".08" strokeWidth="2" />
          <circle cx="512" cy="512" r="384" fill="none" stroke="#0B2A40" strokeOpacity=".08" strokeWidth="2" />
          {ticks}
        </g>
      )}
      {bezel && <path d="M512 26 l-12 -20 h24 z" fill="#0B2A40" fillOpacity=".7" />}
      {door && (
        <>
          <circle cx="512" cy="512" r="344" fill={`url(#${id}door)`} filter={bezel ? undefined : `url(#${id}sh)`} />
          <circle cx="512" cy="512" r="336" fill="none" stroke="#0B5E96" strokeOpacity=".10" strokeWidth="12" />
        </>
      )}
      {RINGS.map((g, i) => (
        <g key={i} transform={`rotate(${rot[i]} 512 512)`} opacity={opacity[i]}>
          <path d={ringPath(g.r)} pathLength={1} fill="none" stroke={`url(#${id}r${i})`} strokeWidth={STROKE} strokeLinecap="round"
            strokeDasharray={`${draw[i]} ${1 - draw[i] + 0.0001}`} />
        </g>
      ))}
      <g transform={`translate(512 540) scale(${hub}) translate(-512 -540)`} opacity={hubOpacity}>
        <circle cx="512" cy="488" r="46" fill={`url(#${id}hub)`} />
        <path d="M494 500 L530 500 L540 592 Q541 604 529 604 L495 604 Q483 604 484 592 Z" fill={`url(#${id}hub)`} />
      </g>
    </svg>
  );
};
