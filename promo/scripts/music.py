"""A small synthesised music track for the films: 120 BPM, B minor (Bm · G · D · A), built from code so there is
nothing to license.

    render(seconds, drop=…, outro=…) -> (left, right)  float arrays at SR

Sections: an intro (pad, filtered plucks, a riser) until `drop`; the groove (kick, clap, hats, bass, chord stabs,
arpeggio, all ducked by the kick) until `outro`; then two bars that ring out. Section edges snap to the beat.
"""
import numpy as np

SR = 48000
BPM = 120
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)

# Bm · G · D · A — root, then the chord tones (MIDI).
PROGRESSION = [(47, [59, 62, 66]), (43, [55, 59, 62]), (50, [57, 62, 66]), (45, [57, 61, 64])]


def hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lowpass(x, k):
    k = max(int(k), 1)
    return np.convolve(x, np.ones(k) / k, mode="same")


def snap(t):
    return round(t / BEAT) * BEAT


class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR) + SR * 4
        # Two buses: music (ducked by the kick) and drums (not).
        self.bus = {"music": [np.zeros(self.n), np.zeros(self.n)], "drums": [np.zeros(self.n), np.zeros(self.n)]}
        self.duck = np.ones(self.n)

    def add(self, clip, t, gain=1.0, pan=0.0, bus="music"):
        i = int(t * SR)
        if i >= self.n or i + len(clip) <= 0:
            return
        c = clip[max(0, -i): self.n - i] * gain
        i = max(i, 0)
        L, R = self.bus[bus]
        L[i:i + len(c)] += c * (1 - max(pan, 0))
        R[i:i + len(c)] += c * (1 + min(pan, 0))

    def sidechain(self, t, depth=0.65, release=0.16):
        i = int(t * SR)
        if i >= self.n:
            return
        m = min(self.n - i, int(release * 5 * SR))
        tt = np.arange(m) / SR
        self.duck[i:i + m] = np.minimum(self.duck[i:i + m], 1 - depth * np.exp(-tt / release))


# ── Instruments ──
def kick():
    t = np.arange(int(0.45 * SR)) / SR
    f = 48 + 140 * np.exp(-t / 0.035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)
    click = rng.standard_normal(len(t)) * np.exp(-t / 0.002) * 0.25
    return np.tanh((body + click) * 1.6) * 0.95


def clap():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    band = lowpass(noise, 6) - lowpass(noise, 40)
    env = np.zeros(n)
    for d in (0, 0.011, 0.022):
        i = int(d * SR)
        env[i:] += np.exp(-(t[: n - i]) / (0.06 if d < 0.02 else 0.16))
    return band * env * 0.55


def hat(open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    hp = noise - lowpass(noise, 4)
    return hp * np.exp(-t / (0.09 if open_ else 0.018)) * (0.32 if open_ else 0.24)


def bass(note, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(note)
    saw = sum(np.sin(2 * np.pi * f * k * t) / k for k in range(1, 7))
    env = np.minimum(1, t / 0.005) * np.exp(-t / (dur * 0.9))
    return np.tanh(saw * 0.9) * env * 0.5


def pluck(note, dur=0.35, bright=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = hz(note)
    tone = np.sin(2 * np.pi * f * t) + 0.4 * bright * np.sin(2 * np.pi * 2 * f * t) + 0.15 * bright * np.sin(2 * np.pi * 3 * f * t)
    return tone * np.minimum(1, t / 0.003) * np.exp(-t / (0.12 + 0.1 * bright))


def pad(notes, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        for det in (-0.15, 0.0, 0.15):
            f = hz(m + 12) + det
            out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) + 0.2 * np.sin(2 * np.pi * 2 * f * t)
    shape = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    return out * shape / (len(notes) * 3)


def riser(dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    seg = max(n // 32, 1)
    for s in range(32):  # brighter as it rises
        out[s * seg:(s + 1) * seg] = (noise - lowpass(noise, int(60 - 55 * s / 31)))[s * seg:(s + 1) * seg]
    sweep = np.sin(2 * np.pi * np.cumsum(200 + 1800 * (t / dur) ** 2) / SR) * 0.15
    return (out * 0.35 + sweep) * (t / dur) ** 2


def crash(dur=2.2):
    n = int(dur * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    return (noise - lowpass(noise, 3)) * np.exp(-t / 0.6) * 0.3


def render(seconds, drop, outro, breakdown=None):
    """Music for a film of `seconds`; the groove runs from `drop` to `outro` (times in seconds), with an optional
    (start, end) breakdown where the drums drop out."""
    tr = Track(seconds)
    drop, outro = snap(drop), snap(outro)
    end = seconds
    bars = int(np.ceil(end / BAR)) + 1

    def chord_at(t):
        return PROGRESSION[int(t // BAR) % 4]

    # Pad throughout (quieter in the groove, where the stabs carry the harmony).
    for b in range(bars):
        t = b * BAR
        if t > end:
            break
        root, tones = chord_at(t)
        tr.add(pad(tones, BAR + 0.3), t, 0.30 if t < drop or t >= outro else 0.18)

    # Intro: filtered plucks on the eighths, a riser into the drop.
    t = 0.0
    while t < drop:
        _, tones = chord_at(t)
        tr.add(lowpass(pluck(tones[int(t / (BEAT / 2)) % 3] + 12, 0.3, 0.3), 3), t, 0.16, pan=0.2 * np.sin(t * 3))
        t += BEAT / 2
    rise = min(2 * BAR, drop)
    tr.add(riser(rise), drop - rise, 0.5)

    # Groove.
    in_break = lambda t: breakdown is not None and breakdown[0] <= t < breakdown[1]
    t = drop
    step = 0
    while t < outro:
        root, tones = chord_at(t)
        beat_in_bar = step % 8  # eighths
        drums = not in_break(t)
        if beat_in_bar % 2 == 0 and drums:
            tr.add(kick(), t, 0.9, bus="drums")
            tr.sidechain(t)
        if beat_in_bar in (2, 6) and drums:
            tr.add(clap(), t, 0.55, bus="drums")
        if drums:
            tr.add(hat(open_=beat_in_bar % 2 == 1), t, 0.6, pan=0.25, bus="drums")
            tr.add(hat(), t + BEAT / 4, 0.35, pan=-0.25, bus="drums")
        # Bass: the root on the eighths, an octave up on the offbeats.
        tr.add(bass(root - 12 + (12 if beat_in_bar % 2 else 0), BEAT / 2 * 0.95), t, 0.55)
        # Chord stabs on the offbeats.
        if beat_in_bar % 2 == 1:
            for k, m in enumerate(tones):
                tr.add(pluck(m + 12, 0.28, 0.8), t, 0.11, pan=(k - 1) * 0.3)
        # Arpeggio in sixteenths, from the second bar of the groove.
        if t >= drop + BAR:
            for s in range(2):
                tt = t + s * BEAT / 4
                tr.add(pluck(tones[(step * 2 + s) % 3] + 24, 0.18, 0.6), tt, 0.07, pan=0.4 * np.sin(tt * 2))
        t += BEAT / 2
        step += 1
    tr.add(crash(), drop, 0.6, bus="drums")
    if breakdown:
        tr.add(riser(min(BAR, breakdown[1] - breakdown[0])), snap(breakdown[1]) - min(BAR, breakdown[1] - breakdown[0]), 0.4)
        tr.add(crash(), snap(breakdown[1]), 0.45, bus="drums")

    # Outro: the last chord rings out under a soft pluck line.
    for i, m in enumerate([66, 69, 74, 78]):
        tr.add(pluck(m, 1.2, 0.5), outro + i * BEAT / 2, 0.12)
    tr.add(crash(3.0), outro, 0.35, bus="drums")

    (mL, mR), (dL, dR) = tr.bus["music"], tr.bus["drums"]
    L, R = mL * tr.duck + dL, mR * tr.duck + dR
    n = int(end * SR)
    return L[:n], R[:n]
