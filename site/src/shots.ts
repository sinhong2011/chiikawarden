/** Real app screenshots (public/assets/shots/<name>-light|dark.webp), captured with
    `Triwarden --demo-full --shoot -appearance light|dark` — windows with their own shadows, on transparency. */
export const SHOTS = {
  vault: { w: 1800, h: 1388 },
  search: { w: 1800, h: 1388 },
  codes: { w: 1800, h: 1388 },
  watchtower: { w: 1800, h: 1388 },
  palette: { w: 1800, h: 1388 },
  // The palette capture with the window behind it blurred (promo/scripts/focus-palette.py).
  "palette-focus": { w: 1800, h: 1388 },
  generator: { w: 1800, h: 1388 },
  menubar: { w: 852, h: 1616 },
  signin: { w: 1800, h: 1388 },
  locked: { w: 1800, h: 1388 },
} as const;

export type ShotName = keyof typeof SHOTS;
