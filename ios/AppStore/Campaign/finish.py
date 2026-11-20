#!/usr/bin/env python3
"""Finishing pass for slides 2 to 7: crop the Nano Banana art to App Store shape, put the real screenshot back on
the phone screen, add real UI cards, and set the type in the app's own fonts.
Run: uv run --with pillow --with numpy python finish.py [slide numbers]"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageCms, ImageChops
import numpy as np, os, sys
from brand import stamp
W, H, K = 1320, 2868, 2868 / 2752
FONTS, SHOTS = '../../Shared/Fonts/', '../Screenshots/'
INK, GREEN, GREY, CREAM, MINT = '#111111', '#01714C', '#4A443D', '#F6F2EA', '#DCEBE2'
SRGB = ImageCms.ImageCmsProfile(ImageCms.createProfile('sRGB')).tobytes()

def crop(name, x0):
    im = Image.open(f'native/slide-{name}.png').convert('RGB')
    return im.crop((x0, 0, x0 + 1267, 2752)).resize((W, H), Image.Resampling.LANCZOS)

def run_edge(v, start, step, need=15):
    """Walk from start in direction step until a dark run of at least `need` px begins; return the last light index."""
    i, n = start, 0
    while 0 <= i < len(v):
        n = n + 1 if v[i] else 0
        if n >= need: return i - step * need
        i += step
    return None

def screen_box(im, cx, cy):
    lum = np.asarray(im).astype(int).sum(2) / 3; dark = lum < 40
    L = [run_edge(dark[y], cx, -1) for y in range(cy - 200, cy + 201, 10)]
    R = [run_edge(dark[y], cx, 1) for y in range(cy - 200, cy + 201, 10)]
    x0, x1 = int(np.median([v for v in L if v is not None])), int(np.median([v for v in R if v is not None]))
    w = x1 - x0 + 1
    cols = [int(x0 + f * w) for f in (.2, .25, .3, .7, .75, .8)]
    T = [run_edge(dark[:, x], cy, -1) for x in cols]; T = [v for v in T if v is not None]
    B = [run_edge(dark[:, x], cy, 1) for x in cols]; B = [v for v in B if v is not None]
    y0 = int(min(T)) if T else None            # a column that crosses status-bar text stops early, so take the outermost hit
    h = round(w * 2868 / 1320)
    y1 = int(np.median(B)) if B else None
    if y0 is None: y0 = y1 - h + 1
    if y1 is None or abs((y1 - y0 + 1) - h) > 0.05 * h: y1 = y0 + h - 1
    return x0, y0, x1, y1

def put_screen(im, shot, cx, cy, keep=(), poly=None):
    """keep: boxes as fractions of the screen (fx0, fy0, fx1, fy1) where the art has something in front of the screen."""
    x0, y0, x1, y1 = screen_box(im, cx, cy); w, h = x1 - x0 + 1, y1 - y0 + 1
    print('  screen', x0, y0, x1, y1, 'aspect', round(h / w, 3), 'real', round(2868 / 1320, 3))
    k = max(w / 1320, h / 2868)                       # same scale both ways, so the app is never stretched
    s = Image.open(shot).convert('RGB').resize((round(1320 * k), round(2868 * k)), Image.Resampling.LANCZOS)
    ox, oy = (s.width - w) // 2, 0
    s = s.crop((ox, oy, ox + w, oy + h))
    S = 4; m = Image.new('L', (W * S, H * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([(x0 + 1) * S, (y0 + 1) * S, (x1 - 1) * S, (y1 - 1) * S], radius=int(0.148 * w * S), fill=255)
    m = m.resize((W, H), Image.Resampling.LANCZOS)
    layer = im.copy(); layer.paste(s, (x0, y0))
    # keep the island and any prop the art put in front of the screen, judged on blurred colour so text never matters
    d = np.asarray(ImageChops.difference(im.filter(ImageFilter.BoxBlur(12)), layer.filter(ImageFilter.BoxBlur(12)))).max(2)
    allow = Image.new('L', (W, H), 0); ad = ImageDraw.Draw(allow)
    for fx0, fy0, fx1, fy1 in ((.3, 0, .7, .075),) + tuple(keep):
        ad.rectangle([x0 + fx0 * w, y0 + fy0 * h, x0 + fx1 * w, y0 + fy1 * h], fill=255)
    kmask = Image.fromarray((((d > 26) & (np.asarray(allow) > 0)) * 255).astype('uint8')).filter(ImageFilter.MinFilter(25)).filter(ImageFilter.MaxFilter(37)).filter(ImageFilter.GaussianBlur(2))
    kmask = ImageChops.multiply(kmask, allow.filter(ImageFilter.MaxFilter(21)))
    m = ImageChops.subtract(m, kmask)
    if poly:            # a prop outlined by hand: keep it, and let it cast a soft shadow on the real screen
        pm = Image.new('L', (W, H), 0); ImageDraw.Draw(pm).polygon(poly, fill=255)
        sh = ImageChops.offset(pm, 14, -10).filter(ImageFilter.GaussianBlur(22)).point(lambda v: v * 95 // 255)
        layer = Image.composite(Image.new('RGB', (W, H), (60, 45, 30)), layer, sh)
        m = ImageChops.subtract(m, pm.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2)))
    return Image.composite(layer, im, m), (x0, y0, x1, y1)

def fit(path, text_lines, size, maxw):
    while True:
        f = ImageFont.truetype(path, size)
        if max(f.getbbox(t)[2] - f.getbbox(t)[0] for t in text_lines) <= maxw: return f, size
        size -= 2

def type_block(im, lines, fills, top, size, pitch, align='c', x=W // 2, font='BebasNeue-Regular.ttf', maxw=900):
    S = 4; layer = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f, fitted = fit(FONTS + font, lines, size * S, maxw * S); pitch = pitch * fitted / (size * S); size = fitted
    for k, (t, c) in enumerate(zip(lines, fills)):
        l, tp, r, b = d.textbbox((0, 0), t, font=f)
        px = (x * S - (r - l) / 2 - l) if align == 'c' else (x * S - l)
        d.text((px, (top + k * pitch) * S - tp), t, font=f, fill=c)
    layer = layer.resize((W, H), Image.Resampling.LANCZOS)
    out = im.convert('RGBA'); out.alpha_composite(layer)
    cap = d.textbbox((0, 0), lines[-1], font=f); print('  type', lines[0], 'size', size // S, 'bottom', round(top + (len(lines) - 1) * pitch + (cap[3] - cap[1]) / S))
    return out.convert('RGB'), size // S

def card(src, box, width, radius=0.06, pad=0):
    c = src.crop(box); h = round(c.height * width / c.width); c = c.resize((width, h), Image.Resampling.LANCZOS)
    S = 4; m = Image.new('L', (width * S, h * S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, width * S - 1, h * S - 1], radius=int(radius * width * S), fill=255)
    return c, m.resize((width, h), Image.Resampling.LANCZOS)

def drop(im, piece, mask, xy, blur=28, offset=18, strength=70, angle=0):
    piece = piece.convert('RGBA'); piece.putalpha(mask)
    if angle: piece = piece.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    a = piece.getchannel('A'); pad = blur * 3
    sh = Image.new('L', (piece.width + 2 * pad, piece.height + 2 * pad), 0); sh.paste(a, (pad, pad))
    sh = sh.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: v * strength // 255)
    out = im.convert('RGBA'); black = Image.new('RGBA', sh.size, (40, 30, 20, 255)); black.putalpha(sh)
    out.alpha_composite(black, (xy[0] - pad, xy[1] - pad + offset)); out.alpha_composite(piece, xy)
    return out.convert('RGB')

def save(im, name):
    for folder, size in (('final-1320x2868', (W, H)), ('final-1206x2622', (1206, 2622))):
        os.makedirs(folder, exist_ok=True)
        (im if size == (W, H) else im.resize(size, Image.Resampling.LANCZOS)).save(f'{folder}/slide-{name}.png', icc_profile=SRGB)
    print('  saved', name)

def s2():
    im = crop('02-orders', 269); im, b = put_screen(im, SHOTS + '2-find.png', round((1028 - 269) * K), round(1500 * K), poly=[(300, 2240), (400, 2298), (450, 2310), (500, 2333), (550, 2366), (592, 2396), (688, 2394), (652, 2470), (556, 2582), (520, 2650), (300, 2650)])
    im, _ = type_block(im, ['ORDERS', 'THAT FIT', "WHAT'S LEFT."], [CREAM] * 3, 235, 210, 162, align='l', x=112, maxw=780)
    im, _ = type_block(im, ['Ranked by calories', 'and protein.'], [MINT] * 2, 715, 56, 70, align='l', x=116, font='Roboto-Regular.ttf')
    save(im, '02-orders')

def s3():
    im = crop('03-numbers', 20); im, b = put_screen(im, 'raw/03-food-detail.png', round((570 - 20) * K), round(1500 * K))
    src = Image.open('raw/03-food-detail.png').convert('RGB'); c, m = card(src, (60, 921, 1260, 1420), 700)
    im = drop(im, c, m, (W - 700 - 70, b[1] + round(0.482 * (b[3] - b[1]))))
    im, _ = type_block(im, ['THE', "RESTAURANT'S", 'OWN NUMBERS.'], [INK, INK, GREEN], 190, 200, 154, maxw=860)
    im, _ = type_block(im, ['Official figures from', '31 restaurant chains.'], [GREY] * 2, 660, 52, 64, font='Roboto-Regular.ttf')
    save(im, '03-numbers')

def s4():
    im = crop('04-cheese', 135); im, b = put_screen(im, 'raw/04-remove-ingredients.png', round((768 - 135) * K), round(1300 * K), poly=[(911, 1960), (1320, 1960), (1320, 2370), (911, 2370)])
    src = Image.open('raw/04-remove-ingredients.png').convert('RGB'); w = b[2] - b[0] + 1
    cw = round(w * 1.2); c, m = card(src, (60, 1444, 1260, 1588), cw, radius=0.035)
    rowy = b[1] + round((1516 / 2868) * (b[3] - b[1] + 1)); im = drop(im, c, m, ((b[0] + b[2]) // 2 - cw // 2, rowy - c.height // 2), blur=22, offset=14, strength=80)
    im, _ = type_block(im, ['HOLD THE CHEESE.', 'SEE THE CHANGE.'], [INK, GREEN], 2392, 160, 124, maxw=980)
    save(im, '04-cheese')

def s5():
    im = crop('05-dinner', 178)
    # the generated phone is about 4.5 percent too short for a real iPhone screen, so lengthen its straight section by
    # two dot pitches (107 px) instead of squashing the screenshot
    px = np.asarray(im).copy(); cut, d, xa, xb = 2300, 107, 395, 1262
    col = px[:, xa:xb].copy(); px[cut:cut + d, xa:xb] = col[cut - d:cut]; px[cut + d:, xa:xb] = col[cut:H - d]
    im = Image.fromarray(px); im, b = put_screen(im, SHOTS + '5-meal.png', round((957 - 178) * K), round(1700 * K))
    im, _ = type_block(im, ['SAME', 'MEAL?', 'ONE TAP.'], [INK, INK, GREEN], 250, 220, 170, align='l', x=112, maxw=780)
    save(im, '05-dinner')

def s6():
    im = crop('06-widget', 135)
    w = Image.open('raw/06-widget-crop.png').convert('RGB'); c, m = card(w, (15, 17, 545, 541), 660, radius=0.145)
    c = c.filter(ImageFilter.UnsharpMask(radius=1.4, percent=60, threshold=2))
    im = drop(im, c, m, (300, 1020), blur=34, offset=26, strength=95, angle=5)
    im, _ = type_block(im, ['CALORIES', 'LEFT, AT', 'A GLANCE.'], [INK, INK, GREEN], 240, 210, 174, maxw=860)
    im, _ = type_block(im, ['A Home Screen widget.'], [GREY], 800, 56, 70, font='Roboto-Regular.ttf')
    save(im, '06-widget')

def s7():
    im = crop('07-no-account', 135)
    im = stamp(im, (652, 2108), 104)          # Leanrrr mark and name printed on the bag, above the receipt
    icon = Image.open('../../MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png').convert('RGB')
    c, m = card(icon, (0, 0, 1024, 1024), 236, radius=0.225)
    im = drop(im, c, m, ((W - 236) // 2, 300), blur=20, offset=14, strength=90)
    im, _ = type_block(im, ['NO ACCOUNT.', 'NO SIGN-UP.'], [CREAM] * 2, 640, 210, 162, maxw=900)
    im, _ = type_block(im, ['Your food log stays', 'on your iPhone.'], [MINT] * 2, 1010, 56, 70, font='Roboto-Regular.ttf')
    S = 4; layer = Image.new('RGBA', (W * S, H * S), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONTS + 'Roboto-Medium.ttf', 46 * S)
    for k, t in enumerate(['On your iPhone', 'iCloud (optional)', 'Apple Health (optional)']):
        y = 1290 + k * 132; d.rounded_rectangle([(W // 2 - 330) * S, y * S, (W // 2 + 330) * S, (y + 104) * S], radius=52 * S, fill=CREAM)
        l, t0, r, b = d.textbbox((0, 0), t, font=f); d.text((W * S / 2 - (r - l) / 2 - l, (y + 52) * S - (t0 + b) / 2), t, font=f, fill=GREEN)
    out = im.convert('RGBA'); out.alpha_composite(layer.resize((W, H), Image.Resampling.LANCZOS))
    save(out.convert('RGB'), '07-no-account')

if __name__ == '__main__':
    for n in sys.argv[1:] or ['2', '3', '4', '5', '6', '7']:
        print('slide', n); globals()['s' + n]()
