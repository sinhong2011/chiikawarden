#!/usr/bin/env python3
"""Generates the DMG window background: background.png (1x), background@2x.png, and background.tiff (both, for
Finder on Retina). scripts/dmg-settings.py places the icons on the slots drawn here, so keep the two in step.

Brand sky swept on a diagonal, the vault door's dial rings turning in the corner, motion lines, and a comet arrow
arcing from the app to Applications. Finder draws the icon labels black in light mode and white in dark mode, so
the band they sit on stays a mid blue that both read on. Blue stays in the fills; arrow and caption are white.

    python3 Design/DMG/generate.py      (needs Pillow)
"""
import math
import os
import subprocess

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 660, 400                     # window content size, in points
APP, APPS = (170, 175), (490, 175)  # icon centres; dmg-settings.py uses the same
CAPTION = "Drag Triwarden to Applications"
SS = 4                              # supersampling: drawn at 4x, saved at 2x and 1x


def font(size, bold=False):
    for path in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(path):
            f = ImageFont.truetype(path, size)
            if bold and path.endswith("SFNS.ttf"):
                try:
                    f.set_variation_by_axes([100, 28, 400, 600])  # width, optical size, grade, weight
                except Exception:
                    pass
            return f
    return ImageFont.load_default(size)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def layer(w, h):
    return Image.new("RGBA", (w, h), (255, 255, 255, 0))


def bezier(p0, p1, p2, n=200):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in (i / n for i in range(n + 1))]


def render():
    s = SS
    w, h = W * s, H * s

    # Diagonal sky: light top-left to deep bottom-right.
    stops = [(0.0, (0x8F, 0xCD, 0xF3)), (0.45, (0x3F, 0x9C, 0xDA)), (1.0, (0x0E, 0x5A, 0x95))]
    small = Image.new("RGB", (W, H))
    px = small.load()
    for y in range(H):
        for x in range(W):
            t = min(1, max(0, (x / W) * 0.55 + (y / H) * 0.75 - 0.08))
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t <= t1:
                    px[x, y] = lerp(c0, c1, (t - t0) / (t1 - t0))
                    break
    img = small.resize((w, h), Image.BICUBIC).convert("RGBA")

    # Light from the top-left.
    glow = layer(w, h)
    ImageDraw.Draw(glow).ellipse([-200 * s, -260 * s, 360 * s, 220 * s], fill=(255, 255, 255, 90))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(70 * s)))

    # The vault door's three dial rings, each with its notch turned apart, off the bottom-right corner.
    rings = layer(w, h)
    d = ImageDraw.Draw(rings)
    cx, cy = 600 * s, 420 * s
    for r, notch, a in ((250, -120, 26), (190, -160, 20), (130, -95, 15)):
        box = [cx - r * s, cy - r * s, cx + r * s, cy + r * s]
        d.arc(box, notch + 7, notch + 360 - 7, fill=(255, 255, 255, a), width=16 * s)
    img.alpha_composite(rings)

    # Motion lines sweeping left to right, fading out at both ends.
    streaks = layer(w, h)
    for y0, bend, a, wd in ((58, -26, 70, 2), (92, -18, 46, 1.5), (300, 22, 52, 2), (330, 30, 34, 1.5),
                            (128, -10, 26, 1)):
        line = layer(w, h)
        pts = [(x * s, y * s) for x, y in bezier((-20, y0), (W / 2, y0 + bend), (W + 20, y0 - bend * 0.4))]
        ImageDraw.Draw(line).line(pts, fill=(255, 255, 255, a), width=round(wd * s), joint="curve")
        fade = Image.linear_gradient("L").rotate(90, expand=True).resize((w, h))
        fade = ImageChops.multiply(fade, fade.transpose(Image.FLIP_LEFT_RIGHT)).point(lambda v: min(255, v * 4))
        line.putalpha(ImageChops.multiply(line.getchannel("A"), fade))
        streaks.alpha_composite(line)
    img.alpha_composite(streaks)

    # Halos behind the two icon slots.
    halos = layer(w, h)
    d = ImageDraw.Draw(halos)
    for x, y in (APP, APPS):
        r = 78 * s
        d.ellipse([x * s - r, y * s - r, x * s + r, y * s + r], fill=(255, 255, 255, 80))
    img.alpha_composite(halos.filter(ImageFilter.GaussianBlur(26 * s)), (0, -10 * s))

    # Comet arrow: an arc over the gap, a dotted tail that grows into a solid stroke, and a head.
    p0, p2 = (APP[0] + 82, APP[1] - 6), (APPS[0] - 84, APPS[1] - 6)
    p1 = ((p0[0] + p2[0]) / 2, APP[1] - 80)
    path = bezier(p0, p1, p2, 400)
    arrow = layer(w, h)
    d = ImageDraw.Draw(arrow)
    for i in range(0, 130, 13):  # tail dots, growing
        x, y = path[i]
        r = (1.0 + 2.0 * i / 130) * s
        d.ellipse([x * s - r, y * s - r, x * s + r, y * s + r], fill=(255, 255, 255, 120 + i))
    # Body: one tapered outline (offset either side of the curve) so the edge stays smooth as it thickens.
    body = path[138:392]
    left, right = [], []
    for i, (x, y) in enumerate(body):
        (ax, ay), (bx, by) = body[max(i - 1, 0)], body[min(i + 1, len(body) - 1)]
        n = math.hypot(bx - ax, by - ay) or 1
        nx, ny = -(by - ay) / n, (bx - ax) / n
        half = (1.5 + 1.6 * i / len(body))
        left.append(((x + nx * half) * s, (y + ny * half) * s))
        right.append(((x - nx * half) * s, (y - ny * half) * s))
    d.polygon(left + right[::-1], fill="white")
    (sx, sy), (tx, ty) = body[0], body[-1]
    d.ellipse([sx * s - 1.5 * s, sy * s - 1.5 * s, sx * s + 1.5 * s, sy * s + 1.5 * s], fill="white")
    (ex, ey), (bx, by) = path[-1], path[-14]
    ang = math.atan2(ey - by, ex - bx)
    for side in (1, -1):
        a = ang + math.pi + side * 0.62
        tip = (ex * s, ey * s)
        e = ((ex + 16 * math.cos(a)) * s, (ey + 16 * math.sin(a)) * s)
        d.line([tip, e], fill="white", width=round(6 * s))
        for c in (tip, e):
            d.ellipse([c[0] - 3 * s, c[1] - 3 * s, c[0] + 3 * s, c[1] + 3 * s], fill="white")
    shadow = arrow.copy()
    shadow.putalpha(arrow.getchannel("A").point(lambda v: v * 0.35))
    shadow = Image.merge("RGBA", (*Image.new("RGB", (w, h), (0x08, 0x3A, 0x63)).split(), shadow.getchannel("A")))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(5 * s)), (0, 3 * s))
    img.alpha_composite(arrow)

    # Sparkles along the arc.
    d = ImageDraw.Draw(img)
    for i, r in ((60, 3), (200, 2), (300, 2.5)):
        x, y = path[i]
        y -= 16 if i != 200 else -14
        for dx, dy in ((r * 2.2, 0), (0, r * 2.2)):
            d.line([((x - dx) * s, (y - dy) * s), ((x + dx) * s, (y + dy) * s)], fill=(255, 255, 255, 200),
                   width=round(1.2 * s))

    # Caption, white with a soft shadow.
    text = layer(w, h)
    f = font(15 * s, bold=True)
    ImageDraw.Draw(text).text((w / 2, 345 * s), CAPTION, font=f, fill="white", anchor="mm")
    sh = Image.merge("RGBA", (*Image.new("RGB", (w, h), (0x05, 0x30, 0x55)).split(),
                              text.getchannel("A").point(lambda v: v * 0.5)))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4 * s)), (0, 2 * s))
    img.alpha_composite(text)
    return img.convert("RGB")


def main():
    one, two = os.path.join(HERE, "background.png"), os.path.join(HERE, "background@2x.png")
    big = render()
    big.resize((W * 2, H * 2), Image.LANCZOS).save(two, dpi=(144, 144))
    big.resize((W, H), Image.LANCZOS).save(one, dpi=(72, 72))
    subprocess.run(["tiffutil", "-cathidpicheck", one, two, "-out", os.path.join(HERE, "background.tiff")],
                   check=True, capture_output=True)


if __name__ == "__main__":
    main()
