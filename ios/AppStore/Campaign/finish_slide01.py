#!/usr/bin/env python3
"""Sharpen slide 1 after Nano Banana: put the real screenshot back on the phone screen and
re-set the headline in the app's own fonts. Run: uv run --with pillow --with numpy python finish_slide01.py"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms
import numpy as np, io
SRC, SHOT, OUT = 'export-1320x2868/slide-01-eat-out.png', '../Screenshots/1-today.png', 'final-1320x2868/slide-01-eat-out.png'
FONTS = '../../Shared/Fonts/'
im = Image.open(SRC).convert('RGB'); W, H = im.size
a = np.asarray(im).astype(int); lum = a.sum(2) / 3

# 1. Phone screen mask, taken from the generated image itself so the corners and island stay as drawn.
dark = Image.fromarray(((lum < 70) * 255).astype('uint8'))
bez = dark.copy(); ImageDraw.floodfill(bez, (220, 2000), 128)
bezel = np.asarray(bez) == 128
inside = Image.fromarray((~bezel * 255).astype('uint8')).copy(); ImageDraw.floodfill(inside, (660, 2000), 128)
screen = np.asarray(inside) == 128
isl = dark.copy(); ImageDraw.floodfill(isl, (660, 1250), 128)
island = np.asarray(isl) == 128
assert island.sum() < 60000 and island.sum() > 5000, island.sum()
ys, xs = np.where(screen); x0, x1, y0 = xs.min(), xs.max(), ys.min()
print('screen', x0, x1, y0, 'island px', island.sum())
mask = Image.fromarray((screen * 255).astype('uint8')).filter(ImageFilter.MinFilter(5))
keep = Image.fromarray((island * 255).astype('uint8')).filter(ImageFilter.MaxFilter(7))
mask = Image.fromarray(np.where(np.asarray(keep) > 0, 0, np.asarray(mask)).astype('uint8')).filter(ImageFilter.GaussianBlur(1.2))
shot = Image.open(SHOT).convert('RGB'); sw = x1 - x0 + 1
shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.Resampling.LANCZOS)
layer = im.copy(); layer.paste(shot, (x0, y0))
im = Image.composite(layer, im, mask)

# 2. Headline band: rebuild the dotted paper on the same grid, then set the type in the real fonts.
P = 53.15                                   # dot pitch measured from the generated grid
bg = np.median(a[20:330, 150:500].reshape(-1, 3), 0)
strip = lum[20:1600, 20:200]; d = strip < np.median(strip) - 25
def centres(v):
    out, s, p = [], v[0], v[0]
    for x in v[1:]:
        if x != p + 1: out.append((s + p) / 2); s = x
        p = x
    return out + [(s + p) / 2]
cx = np.array(centres(np.where(d.sum(0) > 6)[0])) + 20; cy = np.array(centres(np.where(d.sum(1) > 2)[0])) + 20
px = np.mean((cx - cx[0]) - np.round((cx - cx[0]) / P) * P) + cx[0]; py = np.mean((cy - cy[0]) - np.round((cy - cy[0]) / P) * P) + cy[0]
dotc = a[20:330, 150:500][(lum[20:330, 150:500] < np.median(lum[20:330, 150:500]) - 40)].mean(0)
print('grid phase', round(px, 1), round(py, 1), 'bg', bg, 'dot', dotc.round())
T0, T1, S = 385, 1128, 4                    # band rows; S = supersample
band = Image.new('RGB', (W * S, (T1 - T0) * S), tuple(int(v) for v in bg)); bd = ImageDraw.Draw(band)
r = 3.1
for i in range(-2, 30):
    for j in range(-2, 60):
        x, y = px + i * P, py + j * P - T0
        if -10 < y < T1 - T0 + 10: bd.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=tuple(int(v) for v in dotc))
def text(lines, font, fills, top, pitch):
    for k, (line, fill) in enumerate(zip(lines, fills)):
        l, t, rr, b = bd.textbbox((0, 0), line, font=font)
        bd.text(((W * S - (rr - l)) / 2 - l, (top + k * pitch) * S - t), line, font=font, fill=fill)
    return max(bd.textbbox((0, 0), s, font=font)[2] - bd.textbbox((0, 0), s, font=font)[0] for s in lines) / S
head = ImageFont.truetype(FONTS + 'BebasNeue-Regular.ttf', 220 * S)
hw = text(['EAT OUT.', 'STAY ON', 'TARGET.'], head, ['#111111', '#01714C', '#01714C'], 432 - T0, 168)
sup = ImageFont.truetype(FONTS + 'Roboto-Regular.ttf', 58 * S)
sw_ = text(['The calorie tracker', 'for takeaway.'], sup, ['#4A443D'] * 2, 966 - T0, 72)
print('headline width', round(hw), 'support width', round(sw_), 'of', W)
band = band.resize((W, T1 - T0), Image.Resampling.LANCZOS)
fade = np.ones((T1 - T0, W)); f = 14
fade[:f] *= np.linspace(0, 1, f)[:, None]; fade[-f:] *= np.linspace(1, 0, f)[:, None]
im.paste(band, (0, T0), Image.fromarray((fade * 255).astype('uint8')))

# 3. Leanrrr mark and name printed on the paper bag (only where the pixel is kraft-coloured, so the phone stays clean)
from brand import stamp
px = np.asarray(im).astype(int); kraft = (px[..., 0] > 150) & (px[..., 0] - px[..., 2] > 45) & (px[..., 0] < 235)
clip = Image.fromarray((kraft * 255).astype('uint8')).filter(ImageFilter.MinFilter(5))
im = stamp(im, (94, 2400), 94, angle=6, stacked=True, clip=clip)
import os; os.makedirs(os.path.dirname(OUT), exist_ok=True)
im.save(OUT, icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes())
im.resize((1206, 2622), Image.Resampling.LANCZOS).save('final-1206x2622/slide-01-eat-out.png', icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes())
print(OUT, im.size, im.mode)
