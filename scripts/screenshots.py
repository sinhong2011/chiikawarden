#!/usr/bin/env python3
"""README screenshots (docs/images) and store / promotion images (Design/Store) from the demo vault.

`make screenshots` runs `Triwarden --demo-full --shoot` in light and dark (each started just after a one-time
code period begins, so codes show full rings, not the orange last seconds), then:

  • docs/images/*.jpg     the README's pictures, cropped to the window, at the sizes the README lays out
  • Design/Store/*.png    1600×1200 promotion images: a headline over a soft gradient, the window below it

Needs Pillow (`pip3 install pillow`) and the app built (`make build`).
"""
import os
import shutil
import subprocess
import sys
import time

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "build/Build/Products/Debug/Triwarden.app/Contents/MacOS/Triwarden")
SHOTS = os.path.expanduser("~/Library/Containers/io.github.sinhong2011.triwarden/Data/tmp/demo-shots")
WORK = os.path.join(ROOT, "build/screenshots")

# Promotion images: the shot, and its headline.
STORE = {
    "vault": "Every login, card and passkey. Native on your Mac.",
    "search": "One search across every vault.",
    "codes": "Every one-time code, one click away.",
    "palette": "Press ⌘K. Find it, copy it, done.",
    "menubar": "Always there in the menu bar.",
    "watchtower": "Finds weak, reused and breached passwords.",
    "generator": "Strong passwords, passphrases and usernames.",
    "locked": "Locked tight. Only you hold the key.",
    "signin": "Your Vaultwarden, or Bitwarden. Signed in once.",
}
# README pictures: (shot, file, width). Light unless the shot name says dark.
README = [
    ("vault-light", "vault-light", 1640),
    ("vault-dark", "vault-dark", 1200),
    ("search-light", "search", 1200),
    ("menubar-light", "menubar", 380),
    ("codes-light", "codes", 1200),
    ("watchtower-light", "watchtower", 1200),
    ("generator-light", "generator", 1200),
    ("palette-light", "palette", 1200),
    ("signin-light", "signin", 1200),
]
GRADIENT = {"light": ((214, 237, 253), (128, 197, 240)), "dark": ((18, 41, 61), (8, 18, 29))}
INK = {"light": (11, 42, 64), "dark": (255, 255, 255)}


def shoot(scheme):
    """One pass of the app's screenshot run, started just after a code period begins."""
    subprocess.run(["pkill", "-f", "Triwarden.app/Contents/MacOS/Triwarden --demo"], check=False)
    time.sleep(1)
    time.sleep((30 - time.time() % 30) % 30 + 0.5)
    out = subprocess.run([APP, "--demo-full", "--shoot", "-appearance", scheme], capture_output=True, text=True, timeout=240)
    print(out.stdout.strip().splitlines()[-1] if out.stdout.strip() else out.stderr[-400:])
    os.makedirs(WORK, exist_ok=True)
    for name in os.listdir(SHOTS):
        if name.endswith(f"-{scheme}.png"):
            shutil.copy(os.path.join(SHOTS, name), os.path.join(WORK, name))


def window_only(image, dark):
    """The window without its shadow, on an opaque background (JPEG has no transparency)."""
    image = image.convert("RGBA")
    box = image.split()[3].point(lambda v: 255 if v >= 250 else 0).getbbox()
    image = image.crop(box)
    base = Image.new("RGBA", image.size, (30, 30, 32, 255) if dark else (255, 255, 255, 255))
    base.alpha_composite(image)
    return base.convert("RGB")


def readme():
    for shot, name, width in README:
        path = os.path.join(WORK, shot + ".png")
        if not os.path.exists(path):
            print("missing", shot); continue
        image = window_only(Image.open(path), "dark" in shot)
        image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
        image.save(os.path.join(ROOT, "docs/images", name + ".jpg"), quality=88)
        print("docs/images/%s.jpg" % name, image.size)


def headline_font(size):
    font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    font.set_variation_by_name("Bold")
    return font


def store(scheme):
    top, bottom = GRADIENT[scheme]
    for name, headline in STORE.items():
        path = os.path.join(WORK, f"{name}-{scheme}.png")
        if not os.path.exists(path):
            print("missing", name, scheme); continue
        canvas = Image.new("RGBA", (1600, 1200))
        draw = ImageDraw.Draw(canvas)
        for y in range(1200):
            t = y / 1199
            draw.line([(0, y), (1600, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
        # The headline: bold, centred, no wider than the canvas allows.
        size = 54  # the original images: about 1200 px wide for the longest headline
        font = headline_font(size)
        while draw.textlength(headline, font=font) > 1300:
            size -= 2
            font = headline_font(size)
        draw.text((800, 95), headline, font=font, fill=INK[scheme], anchor="mm")
        # The window (with its own shadow), as large as fits under the headline.
        shot = Image.open(path).convert("RGBA")
        scale = min(1300 / shot.width, 1000 / shot.height)
        shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
        canvas.alpha_composite(shot, ((1600 - shot.width) // 2, 185))
        canvas.convert("RGB").save(os.path.join(ROOT, "Design/Store", f"{name}-{scheme}.png"))
        print("Design/Store/%s-%s.png" % (name, scheme))


if __name__ == "__main__":
    if not os.path.exists(APP):
        sys.exit("Build the app first: make build")
    if "--no-shoot" not in sys.argv:
        for scheme in ("light", "dark"):
            shoot(scheme)
    readme()
    for scheme in ("light", "dark"):
        store(scheme)
