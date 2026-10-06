#!/usr/bin/env python3
"""Generates the Triwarden app icon: Icon Composer layers (AppIcon.icon/Assets + layers/) and flat
reference exports (AppIcon.svg, -Dark, -Tinted, -macOS-grid).

三才 (heaven, person, earth) are three dial rings on a round vault door, lightest outside to deepest inside.
Each ring has one notch, turned apart from the others: the dial mid-turn, still locked. (Lined up under
the keyhole they read as a podcast mark.) 歸元, the notches coming into line, is left to the unlock.
The keyhole's round head is 無極. Colours follow the brand sky.

    python3 Design/AppIcon/generate.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
W = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
C = 512

# Ring radii (stroke centre) and where each notch sits, in degrees clockwise from 3 o'clock.
RINGS = [("heaven", 270, -45), ("person", 202, 165), ("earth", 134, 60)]
STROKE = 40
GAP = 30  # clear space across each notch, in points

PALETTES = {
    # background top/bottom, door top/bottom, door rim, ring gradients (top/bottom) per ring, keyhole
    "light": dict(bg0="#8FCDF3", bg1="#4BA7E0", door0="#FFFFFF", door1="#E4F2FB", rim="#0B5E96",
                  heaven=("#A9DAF7", "#6DBBEB"), person=("#4AA8E4", "#2283C9"), earth=("#1670AE", "#0A4E80"),
                  hub=("#1670AE", "#0A4E80")),
    "dark": dict(bg0="#173A57", bg1="#06111C", door0="#2C4560", door1="#16263A", rim="#000000",
                 heaven=("#3E6A8C", "#2C5374"), person=("#6DBBEB", "#4AA8E4"), earth=("#B7E1F9", "#80C5EF"),
                 hub=("#B7E1F9", "#80C5EF")),
    "tinted": dict(bg0="#3A3A3C", bg1="#1C1C1E", door0="#FFFFFF", door1="#D6D6DA", rim="#000000",
                   heaven=("#C7C7CC", "#AEAEB2"), person=("#8E8E93", "#6C6C70"), earth=("#48484A", "#2C2C2E"),
                   hub=("#48484A", "#2C2C2E")),
}


def grad(id, a, b, y1=300, y2=724):
    return (f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>')


def notched_ring(r, stroke, notch):
    """A ring with its notch centred on `notch` degrees; round caps, so the clear gap is GAP wide."""
    half = math.asin((GAP + stroke) / 2 / r)
    n = math.radians(notch)
    a0, a1 = n + half, n - half + 2 * math.pi
    x0, y0 = C + r * math.cos(a0), C + r * math.sin(a0)
    x1, y1 = C + r * math.cos(a1), C + r * math.sin(a1)
    return (f'<path d="M{x0:.1f} {y0:.1f} A{r} {r} 0 1 1 {x1:.1f} {y1:.1f}" fill="none" '
            f'stroke-width="{stroke}" stroke-linecap="round"')


def layers(p):
    bg = (W + '<defs>' + grad('bg', p['bg0'], p['bg1'], 0, 1024) +
          '<radialGradient id="hi" cx=".5" cy=".15" r=".75"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".28"/>'
          '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>'
          '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#hi)"/></svg>')
    door = (W + '<defs>' + grad('d', p['door0'], p['door1'], 168, 856) + '</defs>'
            '<circle cx="512" cy="512" r="344" fill="url(#d)"/>'
            f'<circle cx="512" cy="512" r="336" fill="none" stroke="{p["rim"]}" stroke-opacity=".10" stroke-width="12"/></svg>')
    rings = []
    for name, r, notch in RINGS:
        top, bottom = p[name]
        rings.append(W + '<defs>' + grad('r', top, bottom, C - r, C + r) + '</defs>'
                     + notched_ring(r, STROKE, notch) + ' stroke="url(#r)"/></svg>')
    # The keyhole: a round head and a slot that runs down into the line of notches.
    hub = (W + '<defs>' + grad('h', *p['hub'], 440, 600) + '</defs>'
           '<circle cx="512" cy="488" r="46" fill="url(#h)"/>'
           '<path d="M494 500 L530 500 L540 592 Q541 604 529 604 L495 604 Q483 604 484 592 Z" fill="url(#h)"/></svg>')
    return [bg, door, *rings, hub]


NAMES = ['1-background', '2-door', '3-heaven', '4-person', '5-earth', '6-keyhole']


def flat(p):
    body = [svg[len(W):-6].replace('id="', f'id="L{i}').replace('url(#', f'url(#L{i}') for i, svg in enumerate(layers(p))]
    return (W + '<defs><clipPath id="sq"><rect width="1024" height="1024" rx="230"/></clipPath></defs><g clip-path="url(#sq)">'
            + body[0] + '<circle cx="512" cy="532" r="344" fill="#0B2A40" fill-opacity=".18"/>' + ''.join(body[1:]) + '</g></svg>')


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
    grid = flat(PALETTES['light']).replace(
        '</g></svg>', '</g><g fill="none" stroke="#FF2D55" stroke-opacity=".5" stroke-width="2">'
        '<rect x="100" y="100" width="824" height="824" rx="185"/><circle cx="512" cy="512" r="344"/>'
        + ''.join(f'<circle cx="512" cy="512" r="{r}"/>' for _, r, _ in RINGS) +
        '<line x1="512" y1="0" x2="512" y2="1024"/><line x1="0" y1="512" x2="1024" y2="512"/></g></svg>')
    with open(os.path.join(HERE, 'AppIcon-macOS-grid.svg'), 'w') as f:
        f.write(grid)


if __name__ == '__main__':
    main()
