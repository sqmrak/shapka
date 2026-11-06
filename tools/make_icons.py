#!/usr/bin/env python3
from pathlib import Path
import sys
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
source = Image.open(root / 'resources/icon-source.png').convert('RGB')
# the supplied image has black padding around its rounded square
square = source.crop((45, 51, 1210, 1205)).resize((1165, 1165), Image.Resampling.LANCZOS)
# the home screen of ios 7 and later masks the icon itself, so the icon is a full bleed square: transparent corners would show black
# the crop stays inside the rounded corners of the supplied image
icon_source = source.crop((135, 136, 1119, 1120))
mask = Image.new('L', square.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1164, 1164), radius=255, fill=255)
square.putalpha(mask)
source = square


def glossy_icon():
    # ios 5 and 6 never mask or shine a bundle in /Applications that lists the square ios 7 icons, so the
    # 57 and 72 point icons are drawn here: springboard radius of 18 percent and the glass highlight over the top half
    side = icon_source.width
    base = icon_source.resize((side, side), Image.Resampling.LANCZOS).convert('RGBA')
    shape = Image.new('L', base.size, 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, side - 1, side - 1), radius=round(side * 0.18), fill=255)
    shine = Image.new('L', base.size, 0)
    ImageDraw.Draw(shine).ellipse((-side * 0.45, -side * 1.05, side * 1.45, side * 0.5), fill=255)
    ramp = Image.linear_gradient('L').resize(base.size).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    # strongest at the top edge, fading to a third of it where the highlight ends
    alpha = ramp.point(lambda v: 28 + v * 80 // 255)
    glow = Image.new('RGBA', base.size, (255, 255, 255, 0))
    glow.putalpha(Image.composite(alpha, Image.new('L', base.size, 0), shine))
    base = Image.alpha_composite(base, glow)
    base.putalpha(shape)
    return base


glossy = glossy_icon()
sizes = {
    'Icon.png': 57, 'Icon@2x.png': 114,
    'Icon-60@2x.png': 120, 'Icon-60@3x.png': 180,
    'Icon-72.png': 72, 'Icon-72@2x.png': 144,
    'Icon-76.png': 76, 'Icon-76@2x.png': 152, 'Icon-83.5@2x.png': 167,
    'Icon-Small.png': 29, 'Icon-Small@2x.png': 58, 'Icon-Small@3x.png': 87,
    'Icon-Small-40.png': 40, 'Icon-Small-40@2x.png': 80, 'Icon-Small-40@3x.png': 120,
    'Icon-Small-50.png': 50, 'Icon-Small-50@2x.png': 100,
}
for name, size in sizes.items():
    if name in ('Icon.png', 'Icon@2x.png', 'Icon-72.png', 'Icon-72@2x.png'):
        icon = glossy.resize((size, size), Image.Resampling.LANCZOS)
    else:
        icon = icon_source.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(root / 'resources/icons' / name, optimize=True)

for path in (() if '--icons-only' in sys.argv[1:] else (root / 'resources/launch').glob('*.png')):
    with Image.open(path) as old:
        width, height = old.size
    side = round(min(width, height) * 0.306)
    icon = source.resize((side, side), Image.Resampling.LANCZOS)
    launch = Image.new('RGB', (width, height), (20, 111, 205))
    launch.paste(icon, ((width - side) // 2, (height - side) // 2), icon)
    launch.save(path)
