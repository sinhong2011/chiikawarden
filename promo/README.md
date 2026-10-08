# Triwarden — the film

Two cuts made with [Remotion](https://www.remotion.dev), edited to their music: 120 BPM, 15 frames a beat, every cut on a
downbeat and every word, key and number on a beat. 1920×1080, 30 fps.

- **Film** (60 s, `out/triwarden-film.mp4`): the website and YouTube; it goes to `site/public/media/triwarden-promo.mp4`.
- **Short** (38 s, `out/triwarden-short.mp4`): TikTok, Threads and X.

Both play scene lists from `src/cuts.json` (scene, start bar, bars) through `src/Cut.tsx`.

```bash
cd promo
npm install
python3 scripts/soundtrack.py film && python3 scripts/soundtrack.py short   # music + hits, −14 LUFS
npm run studio                  # preview and scrub
npx remotion render Film out/triwarden-film.mp4 && npx remotion render Short out/triwarden-short.mp4
ffmpeg -i out/triwarden-film.mp4 -c copy -movflags +faststart ../site/public/media/triwarden-promo.mp4
```

App UI in the film is only real captures (`public/shots/*-light.png`), from `Triwarden --demo-full --shoot` — see
`site/README.md`. Refresh them there when the app changes. The music (`scripts/music.py`) and the hits (`scripts/soundtrack.py`) read the same `src/cuts.json`, including where the
drop, breakdown and outro fall, so re-timing a scene there moves its sound with it. The dial matches `Design/AppIcon/generate.py` (same radii, stroke and notch geometry).
