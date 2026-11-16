#!/usr/bin/env python3
"""App Store product page header (5244 x 2950) from the Nano Banana art in native/header-art.jpeg.
The art has no text. Its four props are cut out by colour and placed where each device's crop can see them;
the green dot grid, the headline and the Leanrrr print on the bag are set here.
Run: uv run --with pillow --with numpy python header.py"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms
import numpy as np, os
from brand import stamp
W, H = 5244, 2950
FONTS = '../../Shared/Fonts/'
CREAM, MINT = '#F6F2EA', '#DCEBE2'
BASE, DOT = (1, 111, 74), (104, 170, 140)
SRGB = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()

# What App Store Connect's Device Preview shows of this canvas (measured 17 Nov 2026):
#   iPhone      x 1200-4040, y    0-1875, Dynamic Island and round buttons over the top ~520
#   iPhone Duo  x  950-4300, y  360-1810
#   iPad        x  230-5010, y  320-1760, tab pill over the top-centre ~330
#   The Duo's cover camera and side controls also cover everything right of about x 3720.
# Everything that must be seen sits in the band all three share: x 1200-3720, y 560-1740.
CY = 1150

def background():
    S = 2; im = Image.new('RGB', (W * S, H * S), BASE); d = ImageDraw.Draw(im); p, r = 47, 3.2
    for y in np.arange(p / 2, H, p):
        for x in np.arange(p / 2, W, p):
            d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=DOT)
    return im.resize((W, H), Image.Resampling.LANCZOS)

art = Image.open('native/header-art.jpeg').convert('RGB')
dist = np.sqrt(((np.asarray(art.filter(ImageFilter.GaussianBlur(2.5))).astype(float) - BASE) ** 2).sum(2))
alpha = Image.fromarray((np.clip((dist - 48) / 34, 0, 1) * 255).astype('uint8'))
alpha = alpha.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.2))

def prop(box):
    """Cut one prop out of the art: its pixels and a soft alpha from distance to the background green."""
    p = art.crop(box).convert('RGBA'); a = alpha.crop(box)
    ys, xs = np.where(np.asarray(a) > 128)
    p.putalpha(a); return p.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))

def place(im, p, cx, cy, h, rot=0):
    """Paste a prop centred on (cx, cy), scaled to height h, with a short soft contact shadow."""
    k = h / p.height; p = p.resize((round(p.width * k), h), Image.Resampling.LANCZOS)
    if rot: p = p.rotate(rot, resample=Image.Resampling.BICUBIC, expand=True)
    x, y = cx - p.width // 2, cy - p.height // 2
    a = p.getchannel('A'); pad = 120
    sh = Image.new('L', (p.width + 2 * pad, p.height + 2 * pad), 0); sh.paste(a, (pad, pad))
    out = im.convert('RGBA')
    for blur, off, s in ((60, 40, 70), (14, 12, 95)):
        m = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: v * s // 255)
        lay = Image.new('RGBA', sh.size, (0, 38, 24, 255)); lay.putalpha(m); out.alpha_composite(lay, (x - pad + off // 2, y - pad + off))
    out.alpha_composite(p, (x, y)); return out.convert('RGB'), (x, y, x + p.width, y + p.height)

im = background()
bag, bowl = prop((40, 440, 600, 1100)), prop((600, 500, 1110, 1020))
wrap, cup = prop((1650, 440, 2340, 1130)), prop((2350, 550, 2700, 1000))
# bowl and wrap sit just inside the iPhone's crop either side of the headline; bag and cup further out for Duo and iPad
im, bb = place(im, bag, 880, CY, 740)
im = stamp(im, ((bb[0] + bb[2]) // 2, bb[1] + round(0.36 * (bb[3] - bb[1]))), 150, stacked=True)
im, _ = place(im, bowl, 1545, CY + 20, 530)
im, _ = place(im, wrap, 3482, CY + 10, 468)
im, _ = place(im, cup, 4270, CY - 10, 440)

d = ImageDraw.Draw(im)
def line(text, font, size, y, fill):
    f = ImageFont.truetype(FONTS + font, size); l, t, r, b = d.textbbox((0, 0), text, font=f)
    d.text((TX - (r - l) / 2 - l, y - t), text, font=f, fill=fill); return y + (b - t), r - l

TX = 2520
y = 925
for t, c in (('EAT OUT.', CREAM), ('STAY ON TARGET.', MINT)):
    y, w = line(t, 'BebasNeue-Regular.ttf', 250, y, c); y += 30
    print(' ', t, 'width', w)
line('The calorie tracker for takeaway.', 'Roboto-Regular.ttf', 76, y + 22, CREAM)

os.makedirs('header', exist_ok=True)
im.save('header/header-5244x2950.png', icc_profile=SRGB)
a = (np.asarray(im).astype(int) + 1) // 2 * 2            # 7-bit copy: same picture to the eye, small enough to upload
Image.fromarray(a.clip(0, 255).astype('uint8')).save('header/header-5244x2950-upload.png', optimize=True, compress_level=9, icc_profile=SRGB)
crops = Image.new('RGB', (2130, 480), 'white')
for i, box in enumerate(((1200, 0, 4040, 1875), (950, 360, 3720, 1810), (230, 320, 5010, 1760))):
    c = im.crop(box); c = c.resize((700, round(700 * c.height / c.width)), Image.Resampling.LANCZOS); crops.paste(c, (i * 715, 0))
crops.save('header/device-crops.png')
im.resize((1311, 738), Image.Resampling.LANCZOS).save('header/header-preview.png')
print('saved', im.size)
