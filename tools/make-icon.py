#!/usr/bin/env python3
"""Generates the 4chios app icon and the asset catalog around it.

The mark is a bold `>>` in imageboard greentext green on a deep charcoal
gradient: recognisable to anyone who knows the format, abstract enough to look
like a designed app icon to everyone else. Deliberately not a clover or any
other 4chan trademark.

Run from the repository root:

    python tools/make-icon.py

Outputs App/Assets.xcassets/AppIcon.appiconset/{icon-NNN.png,Contents.json}.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App", "Assets.xcassets", "AppIcon.appiconset")

# Rendered oversized, then downsampled, so every size is cleanly anti-aliased.
MASTER = 2048

BG_TOP = (30, 35, 42)
BG_BOTTOM = (9, 11, 14)
GREEN_LIGHT = (163, 220, 126)
GREEN_DARK = (82, 156, 88)
GLOW = (110, 200, 105)

# Chevron geometry, centred on the canvas.
LEFT_X = 644
TIP_OFFSET = 300
TOP_Y = 620
MID_Y = 1024
BOTTOM_Y = 1428
STROKE = 164


def vertical_gradient(size, top, bottom):
    image = Image.new("RGB", (size, size), top)
    draw = ImageDraw.Draw(image)
    for y in range(size):
        ratio = y / max(size - 1, 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(round(top[i] + (bottom[i] - top[i]) * ratio) for i in range(3)),
        )
    return image


def chevron_mask(size, scale):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    stroke = round(STROKE * scale)
    radius = stroke // 2

    for left in (LEFT_X, LEFT_X + TIP_OFFSET + 160):
        points = [
            (round((left) * scale), round(TOP_Y * scale)),
            (round((left + TIP_OFFSET) * scale), round(MID_Y * scale)),
            (round((left) * scale), round(BOTTOM_Y * scale)),
        ]
        draw.line(points, fill=255, width=stroke, joint="curve")
        # Round the caps: Pillow's line has square ends.
        for x, y in (points[0], points[-1]):
            draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=255)

    return mask


def build_master():
    size = MASTER
    scale = size / 2048

    background = vertical_gradient(size, BG_TOP, BG_BOTTOM)

    # A soft green pool of light behind the mark gives the flat background depth.
    pool = Image.new("L", (size, size), 0)
    ImageDraw.Draw(pool).ellipse(
        [round(380 * scale), round(560 * scale), round(1668 * scale), round(1560 * scale)],
        fill=110,
    )
    pool = pool.filter(ImageFilter.GaussianBlur(round(180 * scale)))
    background = Image.composite(
        Image.new("RGB", (size, size), GLOW), background, pool
    )

    mask = chevron_mask(size, scale)

    # Outer glow driven by the same shape.
    glow = mask.filter(ImageFilter.GaussianBlur(round(70 * scale))).point(lambda v: v * 0.55)
    background = Image.composite(Image.new("RGB", (size, size), GLOW), background, glow)

    mark = vertical_gradient(size, GREEN_LIGHT, GREEN_DARK)
    return Image.composite(mark, background, mask)


# name, pixel size
ICONS = [
    ("icon-20", 20),
    ("icon-20@2x", 40),
    ("icon-20@3x", 60),
    ("icon-29", 29),
    ("icon-29@2x", 58),
    ("icon-29@3x", 87),
    ("icon-40", 40),
    ("icon-40@2x", 80),
    ("icon-40@3x", 120),
    ("icon-60@2x", 120),
    ("icon-60@3x", 180),
    ("icon-76", 76),
    ("icon-76@2x", 152),
    ("icon-83.5@2x", 167),
    ("icon-1024", 1024),
]

CONTENTS = {
    "images": [
        {"size": "20x20", "idiom": "iphone", "filename": "icon-20@2x.png", "scale": "2x"},
        {"size": "20x20", "idiom": "iphone", "filename": "icon-20@3x.png", "scale": "3x"},
        {"size": "29x29", "idiom": "iphone", "filename": "icon-29@2x.png", "scale": "2x"},
        {"size": "29x29", "idiom": "iphone", "filename": "icon-29@3x.png", "scale": "3x"},
        {"size": "40x40", "idiom": "iphone", "filename": "icon-40@2x.png", "scale": "2x"},
        {"size": "40x40", "idiom": "iphone", "filename": "icon-40@3x.png", "scale": "3x"},
        {"size": "60x60", "idiom": "iphone", "filename": "icon-60@2x.png", "scale": "2x"},
        {"size": "60x60", "idiom": "iphone", "filename": "icon-60@3x.png", "scale": "3x"},
        {"size": "20x20", "idiom": "ipad", "filename": "icon-20.png", "scale": "1x"},
        {"size": "20x20", "idiom": "ipad", "filename": "icon-20@2x.png", "scale": "2x"},
        {"size": "29x29", "idiom": "ipad", "filename": "icon-29.png", "scale": "1x"},
        {"size": "29x29", "idiom": "ipad", "filename": "icon-29@2x.png", "scale": "2x"},
        {"size": "40x40", "idiom": "ipad", "filename": "icon-40.png", "scale": "1x"},
        {"size": "40x40", "idiom": "ipad", "filename": "icon-40@2x.png", "scale": "2x"},
        {"size": "76x76", "idiom": "ipad", "filename": "icon-76.png", "scale": "1x"},
        {"size": "76x76", "idiom": "ipad", "filename": "icon-76@2x.png", "scale": "2x"},
        {"size": "83.5x83.5", "idiom": "ipad", "filename": "icon-83.5@2x.png", "scale": "2x"},
        {"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon-1024.png", "scale": "1x"},
    ],
    "info": {"version": 1, "author": "xcode"},
}


def main():
    os.makedirs(OUT, exist_ok=True)
    master = build_master()

    for name, size in ICONS:
        resized = master.resize((size, size), Image.LANCZOS)
        # App icons must be opaque; the system applies the rounded mask.
        resized.convert("RGB").save(os.path.join(OUT, f"{name}.png"), optimize=True)

    with open(os.path.join(OUT, "Contents.json"), "w", encoding="utf-8") as handle:
        json.dump(CONTENTS, handle, indent=2)
        handle.write("\n")

    print(f"wrote {len(ICONS)} icons to {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
