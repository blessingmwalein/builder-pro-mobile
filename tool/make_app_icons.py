"""Builds the app's launcher icons from assets/images/logo.png.

Run from the builder-pro-mobile folder:  python tool/make_app_icons.py

The logo is a single flat colour on a transparent background (the "O2B" mark above
the wordmark). Only the mark is used: the wordmark is unreadable at icon sizes.
The source is small (248 px), so the mark's edge is re-sharpened as it is enlarged
rather than left soft.

Writes:
  android/app/src/main/res/mipmap-*/ic_launcher.png              older Android
  android/app/src/main/res/mipmap-*/ic_launcher_foreground.png   adaptive icon
  android/app/src/main/res/mipmap-*/ic_launcher_monochrome.png   themed icon (Android 13)
  android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml
  android/app/src/main/res/values/ic_launcher_background.xml
  ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png            every size, no alpha
"""

import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "assets", "images", "logo.png")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
APPICON = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")

BRAND = (153, 30, 32)  # the mark's own red
PAPER = (255, 255, 255)

# The mark's rows in the logo (the wordmark starts below them).
MARK_TOP, MARK_BOTTOM = 24, 177


def load_mark():
    logo = Image.open(LOGO).convert("RGBA")
    alpha = logo.getchannel("A").crop((0, MARK_TOP, logo.width, MARK_BOTTOM))
    return alpha.crop(alpha.getbbox())


MARK = load_mark()


def mark_mask(width):
    """The mark as a crisp 0-255 mask [width] px wide."""
    height = max(1, round(width * MARK.height / MARK.width))
    big = (width * 4, height * 4)
    soft = MARK.resize(big, Image.BICUBIC)
    # Push the anti-aliased edge towards a hard one without moving it: the edge
    # sits at half coverage, so steepen the curve around 0.5.
    lut = [int(max(0.0, min(1.0, (v / 255 - 0.5) * 3.2 + 0.5)) * 255) for v in range(256)]
    hard = soft.point(lut)
    return hard.resize((width, height), Image.LANCZOS)


def render(size, mark_fraction, colour, background=None, corner=0.0):
    """A [size] px square: the mark centred, [mark_fraction] of the width.

    With a [background] the square is filled with it (rounded by [corner] of the
    size, with transparent corners); without one it is transparent.
    """
    ss = 4  # draw large, then shrink for smooth rounded corners
    big = size * ss
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if background is not None:
        if corner > 0:
            d = ImageDraw.Draw(canvas)
            d.rounded_rectangle((0, 0, big - 1, big - 1), radius=corner * big, fill=background + (255,))
        else:
            canvas.paste(background + (255,), (0, 0, big, big))
    mask = mark_mask(round(big * mark_fraction))
    ink = Image.new("RGBA", mask.size, colour + (255,))
    x = (big - mask.width) // 2
    y = (big - mask.height) // 2
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    layer.paste(ink, (x, y), mask)
    canvas = Image.alpha_composite(canvas, layer)
    return canvas.resize((size, size), Image.LANCZOS)


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), img.size)


# ---- Android ---------------------------------------------------------------

DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}

for name, k in DENSITIES.items():
    folder = os.path.join(RES, f"mipmap-{name}")
    # Older Android shows the file as it is: a rounded white tile with the mark.
    save(render(round(48 * k), 0.66, BRAND, PAPER, corner=0.22), os.path.join(folder, "ic_launcher.png"))
    # The adaptive icon is 108 dp; only the middle 66 dp is always visible, so the
    # (wide) mark stays inside a circle of about that size.
    save(render(round(108 * k), 0.53, BRAND), os.path.join(folder, "ic_launcher_foreground.png"))
    # Themed icons: the system tints the shape, so it is solid on transparent.
    save(render(round(108 * k), 0.53, (0, 0, 0)), os.path.join(folder, "ic_launcher_monochrome.png"))

anydpi = os.path.join(RES, "mipmap-anydpi-v26", "ic_launcher.xml")
os.makedirs(os.path.dirname(anydpi), exist_ok=True)
with open(anydpi, "w", encoding="utf-8", newline="\n") as f:
    f.write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )
print("wrote", os.path.relpath(anydpi, ROOT))

background = os.path.join(RES, "values", "ic_launcher_background.xml")
with open(background, "w", encoding="utf-8", newline="\n") as f:
    f.write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        '    <color name="ic_launcher_background">#FFFFFF</color>\n'
        "</resources>\n"
    )
print("wrote", os.path.relpath(background, ROOT))

# ---- iOS -------------------------------------------------------------------

with open(os.path.join(APPICON, "Contents.json"), encoding="utf-8") as f:
    contents = json.load(f)
seen = set()
for entry in contents["images"]:
    filename = entry["filename"]
    if filename in seen:
        continue
    seen.add(filename)
    points = float(entry["size"].split("x")[0])
    scale = int(entry["scale"].rstrip("x"))
    px = round(points * scale)
    # iOS rounds the corners itself, and refuses an icon with transparency.
    img = render(px, 0.68, BRAND, PAPER).convert("RGB")
    save(img, os.path.join(APPICON, filename))
