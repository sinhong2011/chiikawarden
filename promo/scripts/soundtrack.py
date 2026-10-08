#!/usr/bin/env python3
"""A cut's soundtrack (public/soundtrack-<cut>.wav): music from scripts/music.py (120 BPM, Bm · G · D · A) with
its drop, breakdown and outro on the bars src/cuts.json gives, and hits on the beats the picture uses — dial clicks,
key presses, numbers landing, cuts. Scene starts come from the same cuts.json the film plays, so they can't drift.
Everything is synthesised, so there is nothing to license. Loudness is normalised to −14 LUFS for social apps.

    python3 scripts/soundtrack.py film     # the full minute
    python3 scripts/soundtrack.py short    # the 38-second cut
"""
import os
import subprocess
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import music  # noqa: E402

import json

CUT_NAME = sys.argv[1] if len(sys.argv) > 1 else "film"
CUTS = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "cuts.json")))
CUT = CUTS[CUT_NAME]
SR = music.SR
FPS = CUTS["fps"]
BEAT = CUTS["beat"]
BAR = 4 * BEAT
START = {sid: start * BAR for sid, start, _ in CUT["scenes"]}
LENGTH = {sid: bars for sid, _, bars in CUT["scenes"]}
FRAMES = CUT["bars"] * BAR
rng = np.random.default_rng(3)


def at(scene, frame):
    return (START[scene] + frame) / FPS


def env(n, a, r):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-t / r)


def lowpass(x, k):
    return np.convolve(x, np.ones(k) / k, mode="same")


def note(f):
    return 440.0 * 2 ** ((f - 69) / 12)


# ── Sound design ──
def click(heavy=True):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    metal = sum(np.sin(2 * np.pi * f * t) * a for f, a in [(2380, .5), (3710, .35), (5230, .2), (7400, .1)]) * np.exp(-t / .012)
    noise = np.diff(rng.standard_normal(n + 1)) * np.exp(-t / .004) * .25
    thump = np.sin(2 * np.pi * 95 * t * (1 + 2 * np.exp(-t / .01))) * np.exp(-t / .05) * (.9 if heavy else 0)
    return (metal * (.6 if heavy else .3) + noise + thump) * .5


def tick():
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 4200 * t) * .3 + np.diff(rng.standard_normal(n + 1)) * .15) * np.exp(-t / .006) * .4


def key():
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 180 * t) * np.exp(-t / .02)
    clack = lowpass(rng.standard_normal(n), 3) * np.exp(-t / .008) * .5
    return (body + clack) * .35


def whoosh(dur=0.9):
    n = int(dur * SR)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    seg = n // 24
    for s in range(24):  # a crude filter sweep: wider smoothing early, narrower at the peak
        k = int(40 - 30 * np.sin(np.pi * s / 23))
        out[s * seg:(s + 1) * seg] = lowpass(x, max(k, 3))[s * seg:(s + 1) * seg]
    return out * np.hanning(n) * .35


def bell(f, dur=3.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return sum(np.sin(2 * np.pi * f * r * t) * a * np.exp(-t / (dur / (1 + i))) for i, (r, a) in enumerate([(1, .5), (2.0, .2), (2.76, .14), (5.4, .06)])) * env(n, .002, 10)


def pad(midis, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    L = np.zeros(n)
    R = np.zeros(n)
    for m in midis:
        f = note(m)
        for det, side in [(-0.12, 0), (0.12, 1)]:
            s = np.sin(2 * np.pi * (f + det) * t + rng.uniform(0, 6)) + .18 * np.sin(2 * np.pi * 2 * (f + det) * t)
            (L if side == 0 else R)[:] += s
    shape = np.minimum(1, t / 1.2) * np.minimum(1, (dur - t) / 1.2)
    return L * shape / len(midis), R * shape / len(midis)


def pluck(f, dur=0.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * f * t) + .3 * np.sin(2 * np.pi * 2 * f * t)) * env(n, .003, .18)




# ── Music ──
bar_s = BAR / FPS
mus = CUT["music"]
brk = mus.get("breakdown")
L, R = music.render(FRAMES / FPS, drop=mus["drop"] * bar_s, outro=mus["outro"] * bar_s,
                    breakdown=(brk[0] * bar_s, brk[1] * bar_s) if brk else None)


def both(clip, t, g):
    i = int(t * SR)
    j = min(len(L), i + len(clip))
    L[i:j] += clip[: j - i] * g
    R[i:j] += clip[: j - i] * g


# ── Hits on the picture's beats ──
for k in (1, 2, 3):                                   # the dial's rings landing
    both(click(True), at("dial", k * BEAT), .9)
both(whoosh(.6), at("dial", BAR - 10), .7)            # the dive through the keyhole
for k in (0, 1, 2):                                   # ⇧ ⌘ Space
    both(key(), at("palette", k * BEAT + 3), 1.0)
for k in range(4):                                    # auto-type keys lighting
    both(key(), at("autotype", k * BEAT), .8)
for k in range(1, LENGTH["montage"] * 2):            # montage cuts, every two beats
    both(whoosh(.35), at("montage", k * 2 * BEAT - 4), .35)
if "security" in START:                               # each lock's ring landing on its bar
    for k in range(3):
        both(click(True), at("security", k * BAR), .85)
for sid in ("shared", "generator"):                   # cuts into the new scenes
    if sid in START:
        both(whoosh(.45), at(sid, -4), .4)
for k in range(3):                                    # speed numbers landing
    both(click(False), at("speed", (2 + 2 * k) * BEAT), 1.0)
both(whoosh(1.2), at("lightdark", 4), .5)             # light to dark
for k in (1, 2, 3):                                   # the end card's rings
    both(click(True), at("end", k * BEAT), .8)
both(bell(note(86), 4), at("end", 3 * BEAT), .3)

# ── Master: soft tail, gentle saturation, then −14 LUFS ──
n_end = int(FRAMES / FPS * SR)
L, R = L[:n_end], R[:n_end]
tail = np.ones(n_end)
tail[-int(1.2 * SR):] = np.linspace(1, 0, int(1.2 * SR)) ** 1.5
L, R = np.tanh(L * tail * 0.9), np.tanh(R * tail * 0.9)
peak = max(np.abs(L).max(), np.abs(R).max())
pcm = (np.stack([L, R], axis=1) / peak * 0.89 * 32767).astype("<i2")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "public", f"soundtrack-{CUT_NAME}.wav")
raw = out + ".raw.wav"
with wave.open(raw, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-af", "loudnorm=I=-14:TP=-1:LRA=9", "-ar", str(SR), out], check=True)
os.remove(raw)
print(f"wrote {os.path.normpath(out)} ({n_end / SR:.1f} s)")
