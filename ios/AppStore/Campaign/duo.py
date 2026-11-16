#!/usr/bin/env python3
"""iPhone Duo slides (2007 x 2853, the inner-display portrait size App Store Connect accepts).
Backgrounds are Nano Banana art with no text and no device (native/duo/), or the device-free art from slides 6 and 7.
The Duo is drawn here, closed, with real captures of its cover screen (raw/duo/); type is set in the app's fonts.
Run: uv run --with pillow --with numpy python duo.py [slide numbers]"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms
import numpy as np, os, sys
import finish as F
from brand import stamp
W, H = 2007, 2853
F.W, F.H = W, H
FONTS = F.FONTS
INK, GREEN, GREY, CREAM, MINT = F.INK, F.GREEN, F.GREY, F.CREAM, F.MINT
SRGB = F.SRGB
SW, SH = 1398, 2034                      # cover screen capture

def art(name, zoom=1.0, ax=0.5, ay=0.5):
    """Cover-fit a Nano Banana plate to the canvas; zoom > 1 enlarges it about the anchor (0 = left/top, 1 = right/bottom)."""
    a = Image.open(f'native/duo/{name}').convert('RGB')
    k = max(W / a.width, H / a.height) * zoom; a = a.resize((round(a.width * k), round(a.height * k)), Image.Resampling.LANCZOS)
    x, y = round((a.width - W) * ax), round((a.height - H) * ay)
    return a.crop((x, y, x + W, y + H))

def from_slide(name, y0=568):
    """Slides 6 and 7 have no device in the art, so the same plate serves here: a 1536 x 2184 window, scaled up."""
    a = Image.open(f'native/slide-{name}.png').convert('RGB').crop((0, y0, 1536, y0 + 2184))
    return a.resize((W, H), Image.Resampling.LANCZOS)

def dots(base, dot, pitch=58, r=3.2):
    S = 2; im = Image.new('RGB', (W * S, H * S), base); d = ImageDraw.Draw(im)
    for y in range(pitch // 2, H, pitch):
        for x in range(pitch // 2, W, pitch):
            d.ellipse([(x - r) * S, (y - r) * S, (x + r) * S, (y + r) * S], fill=dot)
    return im.resize((W, H), Image.Resampling.LANCZOS)

def device(im, shot, x, y, sw):
    """Closed Duo seen straight on: titanium rim, black bezel, the cover screen capture, a soft contact shadow.
    (x, y) is the top-left of the screen; returns the screen box."""
    sh = round(sw * SH / SW); S = 2
    bz, rim = round(0.026 * sw), round(0.010 * sw); rs = round(0.088 * sw); o = bz + rim
    bw, bh = sw + 2 * o, sh + 2 * o; pad = 160
    body = Image.new('RGBA', ((bw + 2 * pad) * S, (bh + 2 * pad) * S), (0, 0, 0, 0)); d = ImageDraw.Draw(body)
    P = pad * S
    d.rounded_rectangle([P, P, P + bw * S, P + bh * S], radius=(rs + o) * S, fill=(150, 144, 136, 255))
    d.rounded_rectangle([P + 3 * S, P + 3 * S, P + (bw - 3) * S, P + (bh - 3) * S], radius=(rs + o - 3) * S, fill=(196, 190, 181, 255))
    d.rounded_rectangle([P + (rim - 2) * S, P + (rim - 2) * S, P + (bw - rim + 2) * S, P + (bh - rim + 2) * S], radius=(rs + bz + 2) * S, fill=(120, 114, 107, 255))
    d.rounded_rectangle([P + rim * S, P + rim * S, P + (bw - rim) * S, P + (bh - rim) * S], radius=(rs + bz) * S, fill=(8, 8, 9, 255))
    body = body.resize((bw + 2 * pad, bh + 2 * pad), Image.Resampling.LANCZOS)
    a = body.getchannel('A')
    shadow = Image.new('L', a.size, 0); shadow.paste(a, (0, 34)); near = shadow.filter(ImageFilter.GaussianBlur(16)).point(lambda v: v * 120 // 255)
    far = shadow.filter(ImageFilter.GaussianBlur(60)).point(lambda v: v * 85 // 255)
    out = im.convert('RGBA')
    for s in (far, near):
        lay = Image.new('RGBA', a.size, (38, 28, 18, 255)); lay.putalpha(s); out.alpha_composite(lay, (x - o - pad, y - o - pad))
    out.alpha_composite(body, (x - o - pad, y - o - pad))
    s = Image.open(shot).convert('RGB').resize((sw, sh), Image.Resampling.LANCZOS)
    m = Image.new('L', (sw * S, sh * S), 0); ImageDraw.Draw(m).rounded_rectangle([0, 0, sw * S - 1, sh * S - 1], radius=rs * S, fill=255)
    # the cover camera sits in the corner the app leaves clear, above the clock
    k = sw / SW; cam = Image.new('RGBA', (sw * S, sh * S), (0, 0, 0, 0)); cd = ImageDraw.Draw(cam)
    cx, cy, cr = 1262 * k * S, 118 * k * S, 44 * k * S
    cd.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(6, 6, 8, 255)); cd.ellipse([cx - cr * .42, cy - cr * .42, cx + cr * .42, cy + cr * .42], fill=(22, 24, 34, 255))
    s = s.convert('RGBA'); s.alpha_composite(cam.resize((sw, sh), Image.Resampling.LANCZOS))
    out.paste(s.convert('RGB'), (x, y), m.resize((sw, sh), Image.Resampling.LANCZOS))
    return out.convert('RGB'), (x, y, x + sw - 1, y + sh - 1)

def head(im, lines, fills, top, size=300, x=W // 2, align='c', maxw=1500):
    return F.type_block(im, lines, fills, top, size, round(size * 0.80), align=align, x=x, maxw=maxw)[0]

def sub(im, lines, fill, top, x=W // 2, align='c', size=78):
    return F.type_block(im, lines, [fill] * len(lines), top, size, round(size * 1.25), align=align, x=x, font='Roboto-Regular.ttf', maxw=1500)[0]

def save(im, name):
    os.makedirs('final-duo-2007x2853', exist_ok=True)
    im.convert('RGB').save(f'final-duo-2007x2853/slide-{name}.png', icc_profile=SRGB); print('  saved', name)

D = 'raw/duo/'

def s1():
    im = art('01-bag.jpeg', 1.0, 0.0, 0.5)
    im = stamp(im, (452, 2080), 120, stacked=True)          # Leanrrr mark and name printed on the bag
    im = head(im, ['EAT OUT.', 'STAY ON', 'TARGET.'], [INK, INK, GREEN], 190, 310)
    im = sub(im, ['The calorie tracker for takeaway.'], GREY, 960)
    im, _ = device(im, D + '1-today.png', 790, 1180, 1100)
    save(im, '01-eat-out')

def s2():
    im = art('02-tray.jpeg')
    im = head(im, ['ORDERS', 'THAT FIT', "WHAT'S LEFT."], [CREAM] * 3, 210, 290, x=130, align='l', maxw=1100)
    im = sub(im, ['Ranked by calories', 'and protein.'], MINT, 960, x=136, align='l')
    im, _ = device(im, D + '2-find.png', 860, 1090, 1060)
    save(im, '02-orders')

def s3():
    im = dots(CREAM, (206, 190, 168))
    im = head(im, ['THE', "RESTAURANT'S", 'OWN NUMBERS.'], [INK, INK, GREEN], 170, 290)
    im = sub(im, ['Official figures from 31 restaurant chains.'], GREY, 900)
    im, b = device(im, D + '3-food-detail.png', 300, 1110, 1140)
    src = Image.open(D + '3-food-detail.png').convert('RGB'); c, m = F.card(src, (63, 740, 1143, 1225), 1000)
    im = F.drop(im, c, m, (W - 1000 - 90, b[1] + round(0.41 * (b[3] - b[1]))), blur=40, offset=26, strength=80)
    save(im, '03-numbers')

def s4():
    im = art('04-cheese.jpeg', 1.1, 1.0, 0.0)
    im, b = device(im, D + '4-remove-ingredients.png', 430, 250, 1150)
    k = 1150 / SW; src = Image.open(D + '4-remove-ingredients.png').convert('RGB')
    cw = round(1080 * k * 1.22); c, m = F.card(src, (63, 848, 1143, 995), cw, radius=0.035)
    rowy = b[1] + round(921 * k)
    im = F.drop(im, c, m, (b[0] + round(603 * k) - cw // 2, rowy - c.height // 2), blur=30, offset=20, strength=85)
    im = head(im, ['HOLD THE CHEESE.', 'SEE THE CHANGE.'], [INK, GREEN], 2230, 270, maxw=1560)
    save(im, '04-cheese')

def s5():
    im = art('05-bowl.jpeg', 1.3, 0.0, 0.62)
    im = head(im, ['SAME', 'MEAL?', 'ONE TAP.'], [INK, INK, GREEN], 200, 310, x=130, align='l', maxw=1100)
    im, _ = device(im, D + '5-meal.png', 800, 1060, 1100)
    save(im, '05-meal')

def s6():
    im = from_slide('06-widget')
    im = head(im, ['CALORIES', 'LEFT, AT', 'A GLANCE.'], [INK, INK, GREEN], 330, 290, x=130, align='l', maxw=900)
    im = sub(im, ['A Home Screen widget.'], GREY, 1080, x=136, align='l')
    w = Image.open('raw/06-widget-crop.png').convert('RGB'); c, m = F.card(w, (15, 17, 545, 541), 760, radius=0.145)
    c = c.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))
    im = F.drop(im, c, m, (1090, 330), blur=40, offset=30, strength=95, angle=5)
    save(im, '06-widget')

def s7():
    im = from_slide('07-no-account')
    im = stamp(im, (994, 1930), 132)
    icon = Image.open('../../MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png').convert('RGB')
    c, m = F.card(icon, (0, 0, 1024, 1024), 250, radius=0.225)
    im = F.drop(im, c, m, ((W - 250) // 2, 180), blur=22, offset=16, strength=90)
    im = head(im, ['NO ACCOUNT.', 'NO SIGN-UP.'], [CREAM] * 2, 510, 290)
    im = sub(im, ['Your food log stays on your iPhone.'], MINT, 1010)
    S = 2; layer = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONTS + 'Roboto-Medium.ttf', 58 * S); labels = ['On your iPhone', 'iCloud if you want', 'Health if you want']
    pw, gap, y, ph = 560, 40, 1220, 124; x = (W - 3 * pw - 2 * gap) // 2
    for t in labels:
        d.rounded_rectangle([x * S, y * S, (x + pw) * S, (y + ph) * S], radius=ph // 2 * S, fill=CREAM)
        l, t0, r, b = d.textbbox((0, 0), t, font=f); d.text(((x + pw / 2) * S - (r - l) / 2 - l, (y + ph / 2) * S - (t0 + b) / 2), t, font=f, fill=GREEN)
        x += pw + gap
    out = im.convert('RGBA'); out.alpha_composite(layer.resize((W, H), Image.Resampling.LANCZOS))
    save(out, '07-no-account')

for n in (sys.argv[1:] or '1234567'):
    print('duo slide', n); globals()['s' + n]()
