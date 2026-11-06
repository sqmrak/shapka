#!/usr/bin/env python3
from pathlib import Path
import plistlib
from PIL import Image

root = Path(__file__).resolve().parents[1]
icons = root / 'resources/icons'
plist = plistlib.loads((root / 'packaging/Info.plist').read_bytes())
legacy = {'Icon.png': 57, 'Icon@2x.png': 114, 'Icon-72.png': 72, 'Icon-72@2x.png': 144}
assert plist['CFBundleIconFile'] == 'Icon.png'
for name in plist['CFBundleIconFiles']:
    with Image.open(icons / name) as image:
        assert image.width == image.height
        if name in legacy:
            assert image.size == (legacy[name], legacy[name])
            alpha = image.convert('RGBA').getchannel('A')
            assert alpha.getpixel((0, 0)) == 0
            assert alpha.getpixel((image.width // 2, image.height // 2)) == 255
print('icon tests passed')
