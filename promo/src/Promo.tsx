import React from "react";
import { AbsoluteFill, Audio, staticFile } from "remotion";
import { Cut, type CutName } from "./Cut";

/** A cut (cuts.json) over its soundtrack from scripts/soundtrack.py: public/soundtrack-<cut>.wav. */
export const Promo: React.FC<{ cut: CutName }> = ({ cut }) => (
  <AbsoluteFill>
    <Cut name={cut} />
    <Audio src={staticFile(`soundtrack-${cut}.wav`)} />
  </AbsoluteFill>
);
