"""Builds the Google Play store graphics from assets/images/logo.png.

Run from the builder-pro-mobile folder:  python tool/make_store_graphics.py

Writes to store/google-play/:
  icon-512.png               the Play Store icon (512 x 512, full square: Google rounds it)
  feature-graphic-1024x500.png   the banner at the top of the listing (24-bit, no alpha)

The logo is a flat colour on transparent (the "O2B" mark above the wordmark) and is
only 248 px wide, so its edge is re-sharpened as it is enlarged, as in
make_app_icons.py.
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, "assets", "images", "logo.png")
FONT = os.path.join(ROOT, "assets", "fonts", "InterVariable.ttf")
OUT = os.path.join(ROOT, "store", "google-play")

BRAND = (153, 30, 32)  # the mark's own red (same as the launcher icon)
DEEP = (118, 15, 27)  # the app's brick red, #760f1b
PAPER = (255, 255, 255)

MARK_TOP, MARK_BOTTOM = 24, 177  # the mark's rows; the wordmark is below them


def _sharp(alpha, width):
    """[alpha] scaled to [width] px wide with a crisp edge."""
    height = max(1, round(width * alpha.height / alpha.width))
    soft = alpha.resize((width * 4, height * 4), Image.BICUBIC)
    lut = [int(max(0.0, min(1.0, (v / 255 - 0.5) * 3.2 + 0.5)) * 255) for v in range(256)]
    return soft.point(lut).resize((width, height), Image.LANCZOS)


def _logo_alpha():
    return Image.open(LOGO).convert("RGBA").getchannel("A")


def mark_only():
    a = _logo_alpha().crop((0, MARK_TOP, 248, MARK_BOTTOM))
    return a.crop(a.getbbox())


def whole_logo():
    a = _logo_alpha()
    return a.crop(a.getbbox())


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), img.size, img.mode)


def play_icon():
    size, ss = 512, 4
    big = size * ss
    canvas = Image.new("RGBA", (big, big), PAPER + (255,))
    mask = _sharp(mark_only(), round(big * 0.68))
    ink = Image.new("RGBA", mask.size, BRAND + (255,))
    canvas.paste(ink, ((big - mask.width) // 2, (big - mask.height) // 2), mask)
    return canvas.resize((size, size), Image.LANCZOS).convert("RGB")


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    try:
        # Inter has an optical-size axis as well as weight: set weight, keep the rest.
        values = []
        for axis in f.get_variation_axes():
            name = axis["name"]
            name = name.decode() if isinstance(name, bytes) else name
            values.append(weight if name.lower() == "weight" else axis["default"])
        f.set_variation_by_axes(values)
    except Exception:
        pass  # a build of Pillow without variable-font support: the default weight
    return f


def feature_graphic():
    w, h, ss = 1024, 500, 2
    canvas = Image.new("RGBA", (w * ss, h * ss), DEEP + (255,))

    # Left: the whole logo (mark + wordmark) in white.
    logo_w = 300 * ss
    mask = _sharp(whole_logo(), logo_w)
    ink = Image.new("RGBA", mask.size, PAPER + (255,))
    lx = 90 * ss
    ly = (h * ss - mask.height) // 2
    canvas.paste(ink, (lx, ly), mask)

    # A thin divider between the logo and the words.
    d = ImageDraw.Draw(canvas)
    dx = 450 * ss
    d.line((dx, 130 * ss, dx, 370 * ss), fill=(255, 255, 255, 70), width=2 * ss)

    # Right: what the app is for.
    x = 490 * ss
    head = font(41 * ss, 700)
    sub = font(23 * ss, 400)
    d.text((x, 154 * ss), "Construction projects,", font=head, fill=PAPER)
    d.text((x, 207 * ss), "run from your phone.", font=head, fill=PAPER)
    d.text(
        (x, 292 * ss),
        "Tasks  ·  Time  ·  Budgets  ·  Chat",
        font=sub,
        fill=(255, 255, 255, 215),
    )
    return canvas.resize((w, h), Image.LANCZOS).convert("RGB")


if __name__ == "__main__":
    save(play_icon(), "icon-512.png")
    save(feature_graphic(), "feature-graphic-1024x500.png")
