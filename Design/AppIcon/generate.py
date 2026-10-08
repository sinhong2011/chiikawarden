#!/usr/bin/env python3
"""Generates the Triwarden app icon: Icon Composer layers (AppIcon.icon/Assets + layers/) and flat
reference exports (AppIcon.svg, -Dark, -Tinted, -macOS-grid).

The website's dial as an icon: a bezel with a minute track round a vault door, and on the door three rings,
lightest outside to deepest inside. Each ring has one notch, and all three sit in line under the keyhole: the
three locks lined up, the door about to open. Same geometry as site/src/scripts/dial.ts, scaled to the icon
grid; colours follow the brand sky.

    python3 Design/AppIcon/generate.py
"""
import math
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
W = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
C = 512

# The dial is drawn at the site's size (bezel radius 470) and scaled so the bezel sits just inside the macOS
# icon grid (an 824-point rounded square): its rim at 404 points from the centre.
SCALE = 404 / 470
G = f'<g transform="translate({C} {C}) scale({SCALE:.4f}) translate(-{C} -{C})">'

# Ring radii (stroke centre), in dial units. Every notch is at 6 o'clock, under the keyhole.
RINGS = [("outer", 270), ("middle", 202), ("inner", 134)]
NOTCH = 90  # degrees clockwise from 3 o'clock
STROKE = 40
GAP = 30  # clear space across each notch

PALETTES = {
    "light": dict(bg0="#8FCDF3", bg1="#4BA7E0", bez=("#FFFFFF", "#E7EEF4", "#D3DEE8"), tick="#0B2A40",
                  door0="#FFFFFF", door1="#E4F2FB", rim="#0B5E96", shadow="#0B2A40",
                  outer=("#A9DAF7", "#6DBBEB"), middle=("#4AA8E4", "#2283C9"), inner=("#1670AE", "#0A4E80"),
                  hub=("#1670AE", "#0A4E80")),
    "dark": dict(bg0="#173A57", bg1="#06111C", bez=("#2E4255", "#1E2F3F", "#142230"), tick="#E6EEF4",
                 door0="#2C4560", door1="#16263A", rim="#000000", shadow="#000000",
                 outer=("#3E6A8C", "#2C5374"), middle=("#6DBBEB", "#4AA8E4"), inner=("#B7E1F9", "#80C5EF"),
                 hub=("#B7E1F9", "#80C5EF")),
    "tinted": dict(bg0="#3A3A3C", bg1="#1C1C1E", bez=("#F2F2F7", "#D6D6DA", "#BDBDC2"), tick="#1C1C1E",
                   door0="#FFFFFF", door1="#D6D6DA", rim="#000000", shadow="#000000",
                   outer=("#C7C7CC", "#AEAEB2"), middle=("#8E8E93", "#6C6C70"), inner=("#48484A", "#2C2C2E"),
                   hub=("#48484A", "#2C2C2E")),
}


def grad(id, a, b, y1=300, y2=724):
    return (f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>')


def notched_ring(r):
    """A ring with its notch centred at NOTCH; round caps, so the clear gap is GAP wide."""
    half = math.asin((GAP + STROKE) / 2 / r)
    n = math.radians(NOTCH)
    a0, a1 = n + half, n - half + 2 * math.pi
    x0, y0 = C + r * math.cos(a0), C + r * math.sin(a0)
    x1, y1 = C + r * math.cos(a1), C + r * math.sin(a1)
    return (f'<path d="M{x0:.1f} {y0:.1f} A{r} {r} 0 1 1 {x1:.1f} {y1:.1f}" fill="none" '
            f'stroke-width="{STROKE}" stroke-linecap="round"')


def ticks(colour):
    """The bezel's minute track: 60 marks, longer and heavier every five; thicker than the site's 120, so they
    still read at small sizes."""
    out = []
    for i in range(60):
        a = i / 60 * 2 * math.pi - math.pi / 2
        major = i % 5 == 0
        r0, r1 = 452, (412 if major else 432)
        out.append(f'<line x1="{C + r0 * math.cos(a):.1f}" y1="{C + r0 * math.sin(a):.1f}" '
                   f'x2="{C + r1 * math.cos(a):.1f}" y2="{C + r1 * math.sin(a):.1f}" stroke="{colour}" '
                   f'stroke-opacity="{.55 if major else .25}" stroke-width="{7 if major else 3.5}" stroke-linecap="round"/>')
    return ''.join(out)


def layers(p):
    bg = (W + '<defs>' + grad('bg', p['bg0'], p['bg1'], 0, 1024) +
          '<radialGradient id="hi" cx=".5" cy=".15" r=".75"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".28"/>'
          '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>'
          '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#hi)"/></svg>')
    b0, b1, b2 = p['bez']
    bezel = (W + '<defs><linearGradient id="b" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="' + b0 + '"/>'
             f'<stop offset=".5" stop-color="{b1}"/><stop offset="1" stop-color="{b2}"/></linearGradient></defs>' + G +
             '<circle cx="512" cy="512" r="470" fill="url(#b)"/>'
             f'<circle cx="512" cy="512" r="469" fill="none" stroke="{p["tick"]}" stroke-opacity=".10" stroke-width="3"/>'
             f'<circle cx="512" cy="512" r="384" fill="none" stroke="{p["tick"]}" stroke-opacity=".10" stroke-width="3"/>'
             + ticks(p['tick']) + '</g></svg>')
    door = (W + '<defs>' + grad('d', p['door0'], p['door1'], 168, 856) + '</defs>' + G +
            '<circle cx="512" cy="512" r="344" fill="url(#d)"/>'
            f'<circle cx="512" cy="512" r="336" fill="none" stroke="{p["rim"]}" stroke-opacity=".10" stroke-width="12"/></g></svg>')
    rings = []
    for name, r in RINGS:
        top, bottom = p[name]
        rings.append(W + '<defs>' + grad('r', top, bottom, C - r, C + r) + '</defs>' + G
                     + notched_ring(r) + ' stroke="url(#r)"/></g></svg>')
    # The keyhole: a round head and a slot that runs down into the line of notches.
    hub = (W + '<defs>' + grad('h', *p['hub'], 440, 600) + '</defs>' + G +
           '<circle cx="512" cy="488" r="46" fill="url(#h)"/>'
           '<path d="M494 500 L530 500 L540 592 Q541 604 529 604 L495 604 Q483 604 484 592 Z" fill="url(#h)"/></g></svg>')
    return [bg, bezel, door, *rings, hub]


NAMES = ['1-background', '2-bezel', '3-door', '4-outer', '5-middle', '6-inner', '7-keyhole']


def flat(p):
    body = [svg[len(W):-6].replace('id="', f'id="L{i}').replace('url(#', f'url(#L{i}') for i, svg in enumerate(layers(p))]
    # A soft drop under the dial, as Icon Composer's shadow gives the layered icon.
    shadow = (f'<defs><filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="20" '
              f'stdDeviation="26" flood-color="{p["shadow"]}" flood-opacity=".28"/></filter></defs>'
              f'<circle cx="512" cy="512" r="404" fill="{p["bez"][1]}" filter="url(#sh)"/>')
    return (W + '<defs><clipPath id="sq"><rect width="1024" height="1024" rx="230"/></clipPath></defs><g clip-path="url(#sq)">'
            + body[0] + shadow + ''.join(body[1:]) + '</g></svg>')


def main():
    for d in ('layers', 'AppIcon.icon/Assets'):
        folder = os.path.join(HERE, d)
        for old in os.listdir(folder):
            if old.endswith('.svg'):
                os.remove(os.path.join(folder, old))
        for name, svg in zip(NAMES, layers(PALETTES['light'])):
            with open(os.path.join(folder, f'{name}.svg'), 'w') as f:
                f.write(svg)
    exports = {'AppIcon.svg': 'light', 'AppIcon-Dark.svg': 'dark', 'AppIcon-Tinted.svg': 'tinted'}
    for file, mode in exports.items():
        with open(os.path.join(HERE, file), 'w') as f:
            f.write(flat(PALETTES[mode]))
    # The website favicon and navigation mark are the light application-icon export, not a separately maintained copy.
    shutil.copyfile(os.path.join(HERE, 'AppIcon.svg'), os.path.join(REPO, 'site', 'public', 'assets', 'icon.svg'))
    grid = flat(PALETTES['light']).replace(
        '</g></svg>', '</g><g fill="none" stroke="#FF2D55" stroke-opacity=".5" stroke-width="2">'
        '<rect x="100" y="100" width="824" height="824" rx="185"/><circle cx="512" cy="512" r="404"/>'
        + ''.join(f'<circle cx="512" cy="512" r="{r * SCALE:.1f}"/>' for _, r in RINGS) +
        '<line x1="512" y1="0" x2="512" y2="1024"/><line x1="0" y1="512" x2="1024" y2="512"/></g></svg>')
    with open(os.path.join(HERE, 'AppIcon-macOS-grid.svg'), 'w') as f:
        f.write(grid)


if __name__ == '__main__':
    main()
