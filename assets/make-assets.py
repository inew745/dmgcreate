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
    "bold": [
        "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
        "/System/Library/Fonts/SFNS.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ],
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
# The default disk-image background
# ---------------------------------------------------------------------------
#
# A dark window with two rainbow-bordered icon slots and a curved arrow:
# the left slot is where the app goes, the right one is the Applications
# shortcut. Drawn here rather than shipped as a flat file so the Retina
# version is genuinely sharp instead of an upscale.

SLOT_SIZE = 137           # outer size of a slot, in points
SLOT_RADIUS = 26
SLOT_BORDER = 16
SLOT_Y = 118              # top edge of both slots
SLOT_LEFT_X = 113
SLOT_RIGHT_X = 403
SLOT_FILL = (217, 217, 217)

# The outlined plate at the foot of each slot, where the Finder draws the
# item's name. Centred on the slot, straddling its bottom edge.
PLATE_WIDTH = 118
PLATE_HEIGHT = 28.5
PLATE_CENTRE_Y = 251.2
PLATE_RADIUS = 13
PLATE_STROKE = 2.6

# Hue (degrees) along the top-left to bottom-right diagonal of a slot.
HUE_STOPS = [
    (0.000, 300.0), (0.080, 271.0), (0.248, 212.0), (0.390, 163.0),
    (0.493, 133.0), (0.599, 83.0), (0.675, 51.0), (0.745, 44.5),
    (0.810, 38.0), (0.887, 27.5), (1.000, 22.0),
]

TEXT_LINES = ["drag the application", "to the applications", "folder"]
TEXT_TOP = 17             # top of the first line
TEXT_LEADING = 24
TEXT_SIZE = 17


def hue_at(t):
    t = min(max(t, 0.0), 1.0)
    for i in range(len(HUE_STOPS) - 1):
        t0, h0 = HUE_STOPS[i]
        t1, h1 = HUE_STOPS[i + 1]
        if t <= t1:
            f = (t - t0) / (t1 - t0) if t1 > t0 else 0.0
            return h0 + (h1 - h0) * f
    return HUE_STOPS[-1][1]


def rainbow_square(size):
    """A square filled with the diagonal rainbow gradient."""
    import colorsys
    strip = [tuple(round(v * 255) for v in colorsys.hsv_to_rgb(hue_at(i / (2 * size - 2)) / 360.0, 1, 1))
             for i in range(2 * size)]
    band = Image.new("RGB", (2 * size, 1))
    band.putdata(strip)
    square = Image.new("RGB", (size, size))
    for y in range(size):
        square.paste(band.crop((y, 0, y + size, 1)), (0, y))
    return square


def rounded_mask(size, radius, inset=0):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset],
        radius=max(radius - inset, 1), fill=255)
    return mask


def draw_slot(canvas, x, y, scale):
    """One rainbow-bordered icon slot, with a soft shadow under it."""
    size = SLOT_SIZE * scale
    radius = SLOT_RADIUS * scale
    border = SLOT_BORDER * scale

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, y + 4 * scale, x + size, y + size + 4 * scale],
        radius=radius, fill=(0, 0, 0, 110))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(7 * scale)))

    slot = rainbow_square(size).convert("RGBA")
    slot.putalpha(rounded_mask(size, radius))
    inner = Image.new("RGBA", (size, size), SLOT_FILL + (255,))
    inner.putalpha(rounded_mask(size, radius, inset=border))
    slot.alpha_composite(inner)
    canvas.alpha_composite(slot, (x, y))


def draw_label_plate(canvas, slot_x, scale):
    """The outlined name plate under a slot."""
    centre_x = (slot_x + SLOT_SIZE / 2) * scale
    centre_y = PLATE_CENTRE_Y * scale
    half_w = PLATE_WIDTH * scale / 2
    half_h = PLATE_HEIGHT * scale / 2

    plate = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(plate).rounded_rectangle(
        [centre_x - half_w, centre_y - half_h, centre_x + half_w, centre_y + half_h],
        radius=PLATE_RADIUS * scale,
        fill=SLOT_FILL + (255,),
        outline=(0, 0, 0, 255),
        width=round(PLATE_STROKE * scale))
    canvas.alpha_composite(plate)


def draw_arrow(canvas, scale):
    """The curved double-headed arrow between the two slots."""
    import math

    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    cx, cy, r = 319.5 * scale, 171.4 * scale, 90.0 * scale
    start, end = 214.1, 327.5
    width = max(round(4 * scale), 2)
    draw.arc([cx - r, cy - r, cx + r, cy + r], start=start, end=end,
             fill=(255, 255, 255, 255), width=width)

    for angle, sweep in ((start, -1), (end, 1)):
        a = math.radians(angle)
        point = (cx + r * math.cos(a), cy + r * math.sin(a))
        # Tangent to the circle at this end, pointing away from the apex.
        tangent = (-math.sin(a) * sweep, math.cos(a) * sweep)
        normal = (-tangent[1], tangent[0])
        length, half = 15 * scale, 7.5 * scale
        tip = (point[0] + tangent[0] * length * 0.45,
               point[1] + tangent[1] * length * 0.45)
        base = (point[0] - tangent[0] * length * 0.55,
                point[1] - tangent[1] * length * 0.55)
        draw.polygon([tip,
                      (base[0] + normal[0] * half, base[1] + normal[1] * half),
                      (base[0] - normal[0] * half, base[1] - normal[1] * half)],
                     fill=(255, 255, 255, 255))

    shadow = layer.filter(ImageFilter.GaussianBlur(3 * scale))
    shadow = Image.merge("RGBA", (Image.new("L", canvas.size, 0),) * 3 + (shadow.split()[3],))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(layer)


def draw_caption(canvas, scale, lines=None):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    face = font("bold", TEXT_SIZE * scale)
    centre = canvas.size[0] / 2
    for index, line in enumerate(lines or TEXT_LINES):
        y = (TEXT_TOP + TEXT_LEADING * index) * scale
        draw.text((centre, y), line, font=face, fill=(255, 255, 255, 255), anchor="ma")

    shadow = layer.filter(ImageFilter.GaussianBlur(2.5 * scale))
    shadow = Image.merge("RGBA", (Image.new("L", canvas.size, 0),) * 3 + (shadow.split()[3],))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(layer)


def make_background(path, width=660, height=400, scale=1, lines=None, supersample=2):
    s = scale * supersample
    w, h = width * s, height * s

    # Dark background with a very slight vignette, lighter towards the edges.
    vignette = Image.radial_gradient("L").resize((w, h), Image.BICUBIC)
    shade = vignette.point(lambda v: 57 + round(v * 4 / 255))
    canvas = Image.merge("RGB", (shade, shade, shade)).convert("RGBA")

    for slot_x in (SLOT_LEFT_X, SLOT_RIGHT_X):
        draw_slot(canvas, slot_x * s, SLOT_Y * s, s)
    for slot_x in (SLOT_LEFT_X, SLOT_RIGHT_X):
        draw_label_plate(canvas, slot_x, s)
    draw_arrow(canvas, s)
    draw_caption(canvas, s, lines=lines)

    canvas = canvas.resize((width * scale, height * scale), Image.LANCZOS)
    canvas.convert("RGB").save(path)
    return path


if __name__ == "__main__":
    print(make_app_icon(os.path.join(HERE, "appicon.png")))

    # The background every new project starts with, and the one DMG Creator's
    # own disk image uses (./build.sh --dmg).
    print(make_background(os.path.join(HERE, "default-background.png"), scale=1))
    print(make_background(os.path.join(HERE, "default-background@2x.png"), scale=2))
