#!/usr/bin/env python3
"""13-inch iPad slides (2064 x 2752, the size App Store Connect takes for the iPad 13-inch slot).
Backgrounds are Nano Banana art from the Gemini app with no text and no device (native/ipad/, 3:4 like the canvas), the
scripted dot grid for slide 3, and the device-free art from iPhone slides 6 and 7.
The iPad is drawn here, upright and straight on, with real captures from the "Leanr iPad 13" simulator (raw/ipad/);
type is set in the app's fonts, the same way as finish.py and duo.py.
Run: uv run --with pillow --with numpy python ipad.py [slide numbers]"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os, sys
import finish as F
from brand import stamp
W, H = 2064, 2752
F.W, F.H = W, H
FONTS = F.FONTS
INK, GREEN, GREY, CREAM, MINT = F.INK, F.GREEN, F.GREY, F.CREAM, F.MINT
SRGB = F.SRGB
SW, SH = 2064, 2752                       # iPad 13-inch capture
R = 'raw/ipad/'

def art(name, zoom=1.0, ax=0.5, ay=0.5):
    """Cover-fit a Nano Banana plate to the canvas; zoom > 1 enlarges it about the anchor (0 = left/top, 1 = right/bottom)."""
    a = Image.open(f'native/ipad/{name}').convert('RGB')
    k = max(W / a.width, H / a.height) * zoom; a = a.resize((round(a.width * k), round(a.height * k)), Image.Resampling.LANCZOS)
    x, y = round((a.width - W) * ax), round((a.height - H) * ay)
    return a.crop((x, y, x + W, y + H))

def from_slide(name, y0=704):
    """Slides 6 and 7 have no device in the art, so the iPhone plate serves here: a 1536 x 2048 (3:4) window, scaled up."""
    a = Image.open(f'native/slide-{name}.png').convert('RGB').crop((0, y0, 1536, y0 + 2048))
    return a.resize((W, H), Image.Resampling.LANCZOS)

def dots(base, dot, pitch=58, r=3.2):
    S = 2; im = Image.new('RGB', (W * S, H * S), base); d = ImageDraw.Draw(im)
    for y in range(pitch // 2, H, pitch):
        for x in range(pitch // 2, W, pitch):
            d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=dot)
    return im.resize((W, H), Image.Resampling.LANCZOS)

def clean(shot):
    """The simulator draws a grey Quick Note corner mark at the bottom right; replace only its grey pixels with the
    nearest non-grey pixel to their left on the same row."""
    import numpy as np
    s = Image.open(shot).convert('RGB'); px = np.asarray(s).copy()
    box = px[2640:, 1960:].astype(int)
    grey = (np.ptp(box, axis=2) < 14) & (box.mean(2) > 70) & (box.mean(2) < 200)
    grey = np.asarray(Image.fromarray((grey * 255).astype('uint8')).filter(ImageFilter.MaxFilter(5))) > 0
    for yy in range(box.shape[0]):
        for xx in range(box.shape[1]):
            if grey[yy, xx]:
                k = xx
                while k > 0 and grey[yy, k]: k -= 1
                px[2640 + yy, 1960 + xx] = px[2640 + yy, 1960 + k]
    return Image.fromarray(px)

def device(im, shot, x, y, sw):
    """iPad Pro seen straight on in portrait: aluminium edge, even black bezel, the capture, a soft contact shadow.
    (x, y) is the top-left of the screen; returns the screen box."""
    sh = round(sw * SH / SW); S = 2
    bz, rim = round(0.030 * sw), round(0.007 * sw); rs = round(0.026 * sw); o = bz + rim
    bw, bh = sw + 2 * o, sh + 2 * o; pad = 180
    body = Image.new('RGBA', ((bw + 2 * pad) * S, (bh + 2 * pad) * S), (0, 0, 0, 0)); d = ImageDraw.Draw(body)
    P = pad * S
    d.rounded_rectangle([P, P, P + bw * S, P + bh * S], radius=(rs + o) * S, fill=(152, 152, 156, 255))
    d.rounded_rectangle([P + 3 * S, P + 3 * S, P + (bw - 3) * S, P + (bh - 3) * S], radius=(rs + o - 3) * S, fill=(206, 206, 210, 255))
    d.rounded_rectangle([P + (rim - 2) * S, P + (rim - 2) * S, P + (bw - rim + 2) * S, P + (bh - rim + 2) * S], radius=(rs + bz + 2) * S, fill=(118, 118, 122, 255))
    d.rounded_rectangle([P + rim * S, P + rim * S, P + (bw - rim) * S, P + (bh - rim) * S], radius=(rs + bz) * S, fill=(8, 8, 9, 255))
    # front camera sits in the middle of the long edge (the top in landscape), here the right-hand bezel
    cx, cy, cr = P + (bw - o / 2) * S, P + bh / 2 * S, 0.0055 * sw * S
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(24, 26, 34, 255))
    body = body.resize((bw + 2 * pad, bh + 2 * pad), Image.Resampling.LANCZOS)
    a = body.getchannel('A')
    shadow = Image.new('L', a.size, 0); shadow.paste(a, (0, 40)); near = shadow.filter(ImageFilter.GaussianBlur(18)).point(lambda v: v * 120 // 255)
    far = shadow.filter(ImageFilter.GaussianBlur(70)).point(lambda v: v * 85 // 255)
    out = im.convert('RGBA')
    for s in (far, near):
        lay = Image.new('RGBA', a.size, (38, 28, 18, 255)); lay.putalpha(s); out.alpha_composite(lay, (x - o - pad, y - o - pad))
    out.alpha_composite(body, (x - o - pad, y - o - pad))
    s = clean(shot).resize((sw, sh), Image.Resampling.LANCZOS)
    m = Image.new('L', (sw * S, sh * S), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, sw * S - 1, sh * S - 1], radius=rs * S, fill=255)
    out.paste(s, (x, y), m.resize((sw, sh), Image.Resampling.LANCZOS))
    return out.convert('RGB'), (x, y, x + sw - 1, y + sh - 1)

def head(im, lines, fills, top, size=300, x=W // 2, align='c', maxw=1600):
    return F.type_block(im, lines, fills, top, size, round(size * 0.80), align=align, x=x, maxw=maxw)[0]

def sub(im, lines, fill, top, x=W // 2, align='c', size=80):
    return F.type_block(im, lines, [fill] * len(lines), top, size, round(size * 1.25), align=align, x=x, font='Roboto-Regular.ttf', maxw=1700)[0]

def save(im, name):
    os.makedirs('final-ipad-2064x2752', exist_ok=True)
    im.convert('RGB').save(f'final-ipad-2064x2752/slide-{name}.png', icc_profile=SRGB); print('  saved', name)

def s1():
    im = art('01-bag.jpeg')
    im = stamp(im, (331, 1960), 124, stacked=True)          # Leanrrr mark and name printed on the bag
    im = head(im, ['EAT OUT.', 'STAY ON', 'TARGET.'], [INK, INK, GREEN], 150, 300)
    im = sub(im, ['The calorie tracker for takeaway.'], GREY, 905)
    im, _ = device(im, R + '1-today.png', 790, 1100, 1160)
    save(im, '01-eat-out')

def s2():
    im = art('02-tray.jpeg')
    im = head(im, ['ORDERS', 'THAT FIT', "WHAT'S LEFT."], [CREAM] * 3, 190, 290, x=130, align='l', maxw=1250)
    im = sub(im, ['Ranked by calories', 'and protein.'], MINT, 935, x=136, align='l')
    im, _ = device(im, R + '2-find.png', 830, 1150, 1120)
    save(im, '02-orders')

def s3():
    im = dots(CREAM, (206, 190, 168))
    im = head(im, ['THE', "RESTAURANT'S", 'OWN NUMBERS.'], [INK, INK, GREEN], 150, 290)
    im = sub(im, ['Official figures from 31 restaurant chains.'], GREY, 880)
    im, b = device(im, R + '3-food-detail.png', 190, 1080, 1180)
    src = Image.open(R + '3-food-detail.png').convert('RGB'); c, m = F.card(src, (41, 662, 2023, 1290), 1060, radius=0.05)
    im = F.drop(im, c, m, (W - 1060 - 80, b[1] + round(0.30 * (b[3] - b[1]))), blur=40, offset=26, strength=80)
    save(im, '03-numbers')

def s4():
    im = art('04-cheese.jpeg')
    x, y, sw = 380, 170, 1180
    im, b = device(im, R + '4-remove-ingredients.png', x, y, sw)
    k = sw / SW; src = Image.open(R + '4-remove-ingredients.png').convert('RGB')
    cw = round(1982 * k * 1.2); c, m = F.card(src, (41, 1853, 2023, 1953), cw, radius=0.03)
    rowy = b[1] + round(1903 * k)
    im = F.drop(im, c, m, ((b[0] + b[2]) // 2 - cw // 2, rowy - c.height // 2), blur=30, offset=20, strength=85)
    im = head(im, ['HOLD THE CHEESE.', 'SEE THE CHANGE.'], [INK, GREEN], 2060, 270, maxw=1760)
    save(im, '04-cheese')

def s5():
    im = art('05-bowl.jpeg')
    im = head(im, ['SAME', 'MEAL?', 'ONE TAP.'], [INK, INK, GREEN], 190, 310, x=130, align='l', maxw=1100)
    im, _ = device(im, R + '5-meal.png', 830, 1150, 1120)
    save(im, '05-meal')

def s6():
    im = from_slide('06-widget')
    im = head(im, ['CALORIES', 'LEFT, AT', 'A GLANCE.'], [INK, INK, GREEN], 250, 290, x=130, align='l', maxw=950)
    im = sub(im, ['A Home Screen widget.'], GREY, 1000, x=136, align='l')
    w = Image.open('raw/06-widget-crop.png').convert('RGB'); c, m = F.card(w, (15, 17, 545, 541), 780, radius=0.145)
    c = c.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))
    im = F.drop(im, c, m, (1130, 250), blur=40, offset=30, strength=95, angle=5)
    save(im, '06-widget')

def s7():
    im = from_slide('07-no-account')
    im = stamp(im, (1022, 1802), 136)          # same spot on the bag as the iPhone and Duo slides
    icon = Image.open('../../MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png').convert('RGB')
    c, m = F.card(icon, (0, 0, 1024, 1024), 250, radius=0.225)
    im = F.drop(im, c, m, ((W - 250) // 2, 150), blur=22, offset=16, strength=90)
    im = head(im, ['NO ACCOUNT.', 'NO SIGN-UP.'], [CREAM] * 2, 470, 290)
    im = sub(im, ['Your food log stays on your iPad.'], MINT, 965)
    S = 2; layer = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONTS + 'Roboto-Medium.ttf', 58 * S); labels = ['On your iPad', 'iCloud if you want', 'Health if you want']
    pw, gap, y, ph = 560, 40, 1170, 124; x = (W - 3 * pw - 2 * gap) // 2
    for t in labels:
        d.rounded_rectangle([x * S, y * S, (x + pw) * S, (y + ph) * S], radius=ph // 2 * S, fill=CREAM)
        l, t0, r, b = d.textbbox((0, 0), t, font=f); d.text(((x + pw / 2) * S - (r - l) / 2 - l, (y + ph / 2) * S - (t0 + b) / 2), t, font=f, fill=GREEN)
        x += pw + gap
    out = im.convert('RGBA'); out.alpha_composite(layer.resize((W, H), Image.Resampling.LANCZOS))
    save(out, '07-no-account')

for n in (sys.argv[1:] or '1234567'):
    print('ipad slide', n); globals()['s' + n]()
