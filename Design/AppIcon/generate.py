#!/usr/bin/env python3
"""Generates the vault-door app icon: Icon Composer layers (AppIcon.icon/Assets + layers/) and flat
reference exports (AppIcon.svg, -Dark, -Tinted, -macOS-grid). Colours follow the brand: the mascot's tail sky.

    python3 Design/AppIcon/generate.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
W = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
C = 512

PALETTES = {
    # background top/bottom, door top/bottom, rim, groove/bolts, handle top/bottom, hub centre
    "light": dict(bg0="#8FCDF3", bg1="#4BA7E0", door0="#FFFFFF", door1="#E2F1FB", rim="#0B5E96", groove="#2E8FD3",
                  bolt="#2E8FD3", w0="#3A9BDD", w1="#0B5E96", hubin="#FFFFFF"),
    "dark": dict(bg0="#173A57", bg1="#06111C", door0="#2C4560", door1="#16263A", rim="#000000", groove="#80C5EF",
                 bolt="#80C5EF", w0="#A6D8F6", w1="#5FB1E8", hubin="#16263A"),
    "tinted": dict(bg0="#3A3A3C", bg1="#1C1C1E", door0="#FFFFFF", door1="#D6D6DA", rim="#000000", groove="#000000",
                   bolt="#000000", w0="#8E8E93", w1="#48484A", hubin="#FFFFFF"),
}


def grad(id, a, b, y1=300, y2=724):
    return (f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="0" y1="{y1}" x2="0" y2="{y2}">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient>')


def layers(p):
    bg = (W + '<defs>' + grad('bg', p['bg0'], p['bg1'], 0, 1024) +
          '<radialGradient id="hi" cx=".5" cy=".15" r=".75"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".28"/>'
          '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient></defs>'
          '<rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#hi)"/></svg>')
    bolts = ''.join(
        f'<circle cx="{C + 300 * math.cos(2 * math.pi * i / 12 - math.pi / 2):.1f}" '
        f'cy="{C + 300 * math.sin(2 * math.pi * i / 12 - math.pi / 2):.1f}" r="11" fill="{p["bolt"]}" fill-opacity=".30"/>'
        for i in range(12))
    door = (W + '<defs>' + grad('d', p['door0'], p['door1'], 168, 856) + '</defs>'
            '<circle cx="512" cy="512" r="344" fill="url(#d)"/>'
            f'<circle cx="512" cy="512" r="338" fill="none" stroke="{p["rim"]}" stroke-opacity=".12" stroke-width="12"/>'
            f'<circle cx="512" cy="512" r="262" fill="none" stroke="{p["groove"]}" stroke-opacity=".20" stroke-width="10"/>'
            + bolts + '</svg>')
    R = 196
    spokes = ''.join(f'<line x1="{C + R * math.cos(a):.1f}" y1="{C + R * math.sin(a):.1f}" '
                     f'x2="{C - R * math.cos(a):.1f}" y2="{C - R * math.sin(a):.1f}"/>' for a in (math.pi / 4, 3 * math.pi / 4))
    knobs = ''.join(f'<circle cx="{C + R * math.cos(a):.1f}" cy="{C + R * math.sin(a):.1f}" r="36" fill="url(#w)"/>'
                    for a in (math.pi / 4, 3 * math.pi / 4, 5 * math.pi / 4, 7 * math.pi / 4))
    wheel = (W + '<defs>' + grad('w', p['w0'], p['w1']) + '</defs>'
             '<circle cx="512" cy="512" r="150" fill="none" stroke="url(#w)" stroke-width="38"/>'
             f'<g stroke="url(#w)" stroke-width="44" stroke-linecap="round">{spokes}</g>{knobs}</svg>')
    hub = (W + '<defs>' + grad('h', p['w0'], p['w1'], 420, 604) + '</defs>'
           f'<circle cx="512" cy="512" r="92" fill="url(#h)"/><circle cx="512" cy="512" r="36" fill="{p["hubin"]}"/></svg>')
    return bg, door, wheel, hub


def flat(p):
    body = [svg[len(W):-6].replace('id="', f'id="L{i}').replace('url(#', f'url(#L{i}') for i, svg in enumerate(layers(p))]
    return (W + '<defs><clipPath id="sq"><rect width="1024" height="1024" rx="230"/></clipPath></defs><g clip-path="url(#sq)">'
            + body[0] + '<circle cx="512" cy="532" r="344" fill="#0B2A40" fill-opacity=".18"/>' + ''.join(body[1:]) + '</g></svg>')


def main():
    names = ['1-background', '2-door', '3-wheel', '4-hub']
    for name, svg in zip(names, layers(PALETTES['light'])):
        for d in ('layers', 'AppIcon.icon/Assets'):
            with open(os.path.join(HERE, d, f'{name}.svg'), 'w') as f:
                f.write(svg)
    exports = {'AppIcon.svg': 'light', 'AppIcon-Dark.svg': 'dark', 'AppIcon-Tinted.svg': 'tinted'}
    for file, mode in exports.items():
        with open(os.path.join(HERE, file), 'w') as f:
            f.write(flat(PALETTES[mode]))
    grid = flat(PALETTES['light']).replace(
        '</g></svg>', '</g><g fill="none" stroke="#FF2D55" stroke-opacity=".5" stroke-width="2">'
        '<rect x="100" y="100" width="824" height="824" rx="185"/><circle cx="512" cy="512" r="344"/>'
        '<circle cx="512" cy="512" r="196"/><line x1="512" y1="0" x2="512" y2="1024"/><line x1="0" y1="512" x2="1024" y2="512"/></g></svg>')
    with open(os.path.join(HERE, 'AppIcon-macOS-grid.svg'), 'w') as f:
        f.write(grid)


if __name__ == '__main__':
    main()
