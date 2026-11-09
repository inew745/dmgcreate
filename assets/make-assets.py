#!/usr/bin/env python3
"""Regenerate the artwork that ships with DMG Creator.

    python3 assets/make-assets.py

Produces the app icon and the sample disk-image background (1x and 2x).
Needs Pillow: python3 -m pip install pillow
"""

import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))

FONT_CANDIDATES = {
    "semibold": [
        "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ],
    "regular": [
        "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ],
}


def font(weight, size):
    for path in FONT_CANDIDATES[weight]:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical_gradient(size, top, bottom):
    width, height = size
    image = Image.new("RGB", (1, height))
    for y in range(height):
        image.putpixel((0, y), lerp(top, bottom, y / max(height - 1, 1)))
    return image.resize((width, height), Image.BICUBIC)


def diagonal_gradient(size, start, end):
    width, height = size
    base = Image.new("RGB", (width, height))
    pixels = base.load()
    for y in range(height):
        for x in range(width):
            pixels[x, y] = lerp(start, end, (x / width + y / height) / 2)
    return base


# ---------------------------------------------------------------------------
# App icon
# ---------------------------------------------------------------------------
def make_app_icon(path, canvas=1024):
    scale = 2
    size = canvas * scale
    art = int(size * 0.805)          # Apple leaves a margin around the artwork
    offset = (size - art) // 2
    radius = int(art * 0.2237)       # the macOS squircle corner radius

    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Rounded-square body with a blue-to-violet gradient.
    body = diagonal_gradient((art, art), (56, 132, 255), (124, 77, 230)).convert("RGBA")
    mask = Image.new("L", (art, art), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, art - 1, art - 1], radius=radius, fill=255)

    # Soft drop shadow under the body.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shadow_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shadow_mask).rounded_rectangle(
        [offset, offset + int(art * 0.03), offset + art, offset + art + int(art * 0.03)],
        radius=radius, fill=90)
    shadow.putalpha(shadow_mask.filter(ImageFilter.GaussianBlur(art * 0.035)))
    image.alpha_composite(shadow)

    body.putalpha(mask)
    image.alpha_composite(body, (offset, offset))

    # Glossy highlight across the top third.
    gloss = Image.new("RGBA", (art, art), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(gloss)
    gdraw.ellipse([-art * 0.35, -art * 0.95, art * 1.35, art * 0.42],
                  fill=(255, 255, 255, 34))
    gloss = gloss.filter(ImageFilter.GaussianBlur(art * 0.02))
    gloss.putalpha(Image.composite(gloss.split()[3], Image.new("L", (art, art), 0), mask))
    image.alpha_composite(gloss, (offset, offset))

    draw = ImageDraw.Draw(image)
    centre = size / 2

    # The disk: a white circle with a thin grey rim.
    disk_r = art * 0.295
    draw.ellipse([centre - disk_r, centre - disk_r, centre + disk_r, centre + disk_r],
                 fill=(252, 253, 255, 255), outline=(206, 214, 229, 255),
                 width=max(int(art * 0.006), 1))

    # A small picture inside the disk: sky, sun, two hills — "custom background".
    pic_w = disk_r * 1.22
    pic_h = pic_w * 0.72
    left, top = centre - pic_w / 2, centre - pic_h / 2 + art * 0.012
    right, bottom = left + pic_w, top + pic_h
    pic_radius = pic_w * 0.12

    picture = Image.new("RGBA", (int(pic_w), int(pic_h)), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(picture)
    sky = vertical_gradient((int(pic_w), int(pic_h)), (120, 184, 255), (203, 227, 255)).convert("RGBA")
    pmask = Image.new("L", (int(pic_w), int(pic_h)), 0)
    ImageDraw.Draw(pmask).rounded_rectangle([0, 0, int(pic_w) - 1, int(pic_h) - 1],
                                            radius=pic_radius, fill=255)
    sky.putalpha(pmask)
    picture.alpha_composite(sky)

    sun_r = pic_w * 0.085
    pdraw.ellipse([pic_w * 0.74 - sun_r, pic_h * 0.27 - sun_r,
                   pic_w * 0.74 + sun_r, pic_h * 0.27 + sun_r],
                  fill=(255, 214, 102, 255))
    pdraw.polygon([(pic_w * -0.05, pic_h * 1.02), (pic_w * 0.40, pic_h * 0.46),
                   (pic_w * 0.78, pic_h * 1.02)], fill=(86, 160, 120, 255))
    pdraw.polygon([(pic_w * 0.42, pic_h * 1.02), (pic_w * 0.72, pic_h * 0.60),
                   (pic_w * 1.05, pic_h * 1.02)], fill=(66, 134, 99, 255))
    clipped = Image.new("RGBA", picture.size, (0, 0, 0, 0))
    clipped.paste(picture, (0, 0), pmask)
    image.alpha_composite(clipped, (int(left), int(top)))

    draw.rounded_rectangle([left, top, right, bottom], radius=pic_radius,
                           outline=(255, 255, 255, 235), width=max(int(art * 0.008), 1))

    image = image.resize((canvas, canvas), Image.LANCZOS)
    image.save(path)
    return path


# ---------------------------------------------------------------------------
# Sample disk-image background
# ---------------------------------------------------------------------------
def make_background(path, width=660, height=400, scale=1,
                    title="Install My App",
                    hint="Drag the app onto the Applications folder"):
    w, h = width * scale, height * scale
    image = vertical_gradient((w, h), (247, 249, 252), (229, 234, 243)).convert("RGBA")
    draw = ImageDraw.Draw(image)

    # A soft band behind the icon row.
    band = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        [int(w * 0.06), int(h * 0.27), int(w * 0.94), int(h * 0.74)],
        radius=int(26 * scale), fill=(255, 255, 255, 150))
    image.alpha_composite(band)

    title_text = title
    title = font("semibold", int(27 * scale))
    subtitle = font("regular", int(14 * scale))

    tw = draw.textlength(title_text, font=title)
    draw.text(((w - tw) / 2, int(34 * scale)), title_text, font=title, fill=(32, 38, 51))

    hw = draw.textlength(hint, font=subtitle)
    draw.text(((w - hw) / 2, int(h - 54 * scale)), hint, font=subtitle, fill=(110, 120, 138))

    # Arrow between the two icon slots (icons sit at x=180 and x=480, y=185).
    y = int(185 * scale)
    x0, x1 = int(268 * scale), int(392 * scale)
    thickness = max(int(5 * scale), 2)
    draw.line([(x0, y), (x1 - int(16 * scale), y)], fill=(150, 162, 182), width=thickness)
    draw.polygon([(x1, y), (x1 - int(20 * scale), y - int(13 * scale)),
                  (x1 - int(20 * scale), y + int(13 * scale))], fill=(150, 162, 182))

    # Dashed circle hinting where the Applications folder goes.
    import math
    cx, cy, r = int(480 * scale), y, int(74 * scale)
    for i in range(0, 72):
        if i % 2:
            continue
        a0 = math.radians(i * 5)
        a1 = math.radians(i * 5 + 3)
        draw.line([(cx + r * math.cos(a0), cy + r * math.sin(a0)),
                   (cx + r * math.cos(a1), cy + r * math.sin(a1))],
                  fill=(182, 192, 209), width=max(int(2 * scale), 1))

    image.convert("RGB").save(path)
    return path


if __name__ == "__main__":
    print(make_app_icon(os.path.join(HERE, "appicon.png")))

    # Starter artwork for people building their own image.
    print(make_background(os.path.join(HERE, "sample-background.png"), scale=1))
    print(make_background(os.path.join(HERE, "sample-background@2x.png"), scale=2))

    # The background of DMG Creator's own disk image (./build.sh --dmg).
    for name, scale in (("dmg-background.png", 1), ("dmg-background@2x.png", 2)):
        print(make_background(os.path.join(HERE, name), scale=scale,
                              title="DMG Creator",
                              hint="Drag DMG Creator onto the Applications folder"))
