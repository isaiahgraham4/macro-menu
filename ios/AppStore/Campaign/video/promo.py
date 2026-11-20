#!/usr/bin/env python3
"""Leanrrr promo video: real simulator footage in a drawn phone, Gemini b-roll for the opening, type in the app's fonts.
Run from this folder:
  SEG=<frames dir> FF=<ffmpeg> uv run --with pillow python promo.py L out.mp4      (YouTube, 1920x1080)
  SEG=<frames dir> FF=<ffmpeg> uv run --with pillow python promo.py P out.mp4      (Reels and TikTok, 1080x1920)
  ... promo.py L preview 0,60,200     writes preview-L-<frame>.png instead of a video
Frames come from src/take1.mov and the two Gemini clips; cut times are in README.md."""
import os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FMT, OUT = sys.argv[1], sys.argv[2]
PREVIEW = [int(x) for x in sys.argv[3].split(',')] if len(sys.argv) > 3 else None
W, H = (1920, 1080) if FMT == 'L' else (1080, 1920)
FPS = 30
SEG, FF = os.environ['SEG'], os.environ.get('FF', 'ffmpeg')
IOS = os.path.expanduser('~/drive-thru-macros/ios/')
FONTS = IOS + 'Shared/Fonts/'
ICON = IOS + 'MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png'
INK, GREEN, GREY, CREAM = (17, 17, 17), (1, 113, 76), (74, 68, 61), (246, 242, 234)
RING = (.046, .2861, .954, .4639)      # calorie card on Today, as fractions of the screen
SCENES = [
    dict(k='hook', dur=3.3, head=['EAT OUT.', 'STAY ON TARGET.'], sub='The calorie tracker for takeaway.'),
    dict(k='today', dur=3.2, clips=[('today', 10, 92)], head=['CALORIES LEFT,', 'AT A GLANCE.'],
         sub='Calories and protein for today.', lifts=[dict(box=RING, t=1.45)]),
    dict(k='find', dur=5.0, clips=[('find1', 4, 56), ('find2', 0, 66)], head=['ORDERS THAT FIT', "WHAT'S LEFT."],
         sub='Ranked against your calories and protein.', lifts=[dict(box=(.046, .3047, .954, .6203), t=3.8)]),
    dict(k='detail', dur=3.2, clips=[('detail1', 0, 60)], head=["THE RESTAURANT'S", 'OWN NUMBERS.'],
         sub='Official figures from 31 restaurant chains.', lifts=[dict(box=(.046, .3214, .954, .4717), t=1.0)]),
    dict(k='tog', dur=4.6, clips=[('detail2', 4, 52), ('tog1', 0, 42), ('tog2', 0, 54)],
         head=['HOLD THE CHEESE.', 'SEE THE CHANGE.'], sub='Numbers update as you customise.',
         lifts=[dict(box=(.046, .5454, .954, .652), t=1.75), dict(box=(.046, .850, .786, .9014), t=1.85, pill=True, under=True)],
         taps=[(1, 14, .841, .571), (2, 12, .841, .6255)]),
    dict(k='log', dur=4.4, clips=[('log1', 0, 54), ('log2', 0, 84)], head=['LOG IT', 'IN ONE TAP.'],
         sub='Your day updates straight away.', lifts=[dict(box=(.046, .1999, .954, .3766), t=2.5)], taps=[(0, 13, .416, .8755)]),
    dict(k='prog', dur=2.6, clips=[('prog', 0, 72)], head=['SEE THE', 'TREND.'], sub='Weight, goal and progress.'),
    dict(k='end', dur=3.4),
]
for s in SCENES: s['n'] = round(s['dur'] * FPS)
START = [sum(s['n'] for s in SCENES[:i]) for i in range(len(SCENES))]
TOTAL = sum(s['n'] for s in SCENES)

# ---- layout ----
if FMT == 'L':
    SH = 940; SW = round(SH * 1320 / 2868); PX, PY = 1560 - SW // 2, (H - SH) // 2
    HOOK = (1000, 562, 1370 - 500, (H - 562) // 2)
    COL, COLW, HEAD_MAX, SUB_PX = 120, 760, 170, 44
    LIFT_W, LIFT_CX = 600, 1290
else:
    SW = 600; SH = round(SW * 2868 / 1320); PX, PY = (W - SW) // 2, 600
    HOOK = (640, 1138, (W - 640) // 2, 600)
    COL, COLW, HEAD_MAX, SUB_PX = 70, 940, 158, 44
    LIFT_W, LIFT_CX = 860, W // 2
BEZ = round(SW * 0.035); RAD = round(SW * 0.125)

def clamp(x): return max(0.0, min(1.0, x))
def ease(x): x = clamp(x); return 1 - (1 - x) ** 3
def font(name, px): return ImageFont.truetype(FONTS + name, px)

def rrect_mask(w, h, r, ss=3):
    m = Image.new('L', (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), r * ss, fill=255)
    return m.resize((w, h), Image.Resampling.LANCZOS)

def shadow(w, h, r, blur, alpha):
    pad = blur * 3
    m = Image.new('L', (w + pad * 2, h + pad * 2), 0)
    ImageDraw.Draw(m).rounded_rectangle((pad, pad, pad + w, pad + h), r, fill=alpha)
    return m.filter(ImageFilter.GaussianBlur(blur)), pad

def background():
    ss = 2; im = Image.new('RGB', (W * ss, H * ss), CREAM); d = ImageDraw.Draw(im)
    dot = tuple(round(c * 0.84 + i * 0.16) for c, i in zip(CREAM, (46, 34, 22)))
    pitch, r = 40 * ss, 3 * ss
    for y in range(pitch // 2, H * ss, pitch):
        for x in range(pitch // 2, W * ss, pitch): d.ellipse((x - r, y - r, x + r, y + r), fill=dot)
    return im.resize((W, H), Image.Resampling.LANCZOS)

BG = background()
SCREEN_MASK = rrect_mask(SW, SH, RAD)
BEZEL = Image.new('RGB', (SW + BEZ * 2, SH + BEZ * 2), (12, 12, 12))
BEZEL_MASK = rrect_mask(SW + BEZ * 2, SH + BEZ * 2, RAD + BEZ)
PH_SHADOW, PH_PAD = shadow(SW + BEZ * 2, SH + BEZ * 2, RAD + BEZ, 28, 70)
HOOK_MASK = rrect_mask(HOOK[0], HOOK[1], 40)
HK_SHADOW, HK_PAD = shadow(HOOK[0], HOOK[1], 40, 24, 50)

_cache = {}
def seg_frame(name, i):
    files = _cache.get(name)
    if files is None:
        d = os.path.join(SEG, name); files = _cache[name] = sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith('.jpg'))
    return Image.open(files[min(i, len(files) - 1)]).convert('RGB')

# phone timeline: which footage frame shows on each output frame
PHONE = {}
for s, st in zip(SCENES, START):
    if 'clips' not in s: continue
    f = st; s['clip_start'] = []
    for j, (name, a, n) in enumerate(s['clips']):
        last = j == len(s['clips']) - 1; s['clip_start'].append(f - st)
        count = (st + s['n'] - f) if last else n
        for k in range(count): PHONE[f] = (name, a + min(k, n - 1), (st, j)); f += 1
P0, P1 = min(PHONE), max(PHONE)
XF = 5
def phone_frame(f):
    f = max(P0, min(P1, f)); name, i, cid = PHONE[f]; im = seg_frame(name, i)
    for back in range(1, XF + 1):                       # short cross-fade after each cut
        g = f - back
        if g >= P0 and PHONE[g][2] != cid:
            return Image.blend(seg_frame(*PHONE[g][:2]), im, back / (XF + 1))
    return im

def paste_alpha(canvas, im, pos, mask, op=1.0):
    if op <= 0: return
    if op < 1: mask = mask.point(lambda a: int(a * op))
    canvas.paste(im, pos, mask)

def draw_phone(canvas, f, dy):
    x, y = PX, PY + dy
    paste_alpha(canvas, Image.new('RGB', PH_SHADOW.size, (40, 30, 20)), (x - BEZ - PH_PAD, y - BEZ - PH_PAD + 22), PH_SHADOW)
    canvas.paste(BEZEL, (x - BEZ, y - BEZ), BEZEL_MASK)
    src = phone_frame(f)
    canvas.paste(src.resize((SW, SH), Image.Resampling.LANCZOS), (x, y), SCREEN_MASK)
    return src

_lift = {}
def draw_lifts(canvas, s, src, local, op_out):
    prev_bottom = None; placed = []
    for L in s.get('lifts', []):
        x0, y0, x1, y1 = L['box']; sw, sh = src.size
        box = (round(x0 * sw), round(y0 * sh), round(x1 * sw), round(y1 * sh))
        mag = LIFT_W / (0.908 * sw)
        w, h = round((box[2] - box[0]) * mag), round((box[3] - box[1]) * mag)
        cy = PY + (y0 + y1) / 2 * SH
        if FMT == 'P': cy = min(cy, 1500 - h / 2)
        if L.get('under') and prev_bottom is not None: cy = max(cy, prev_bottom + 34 + h / 2) if FMT == 'L' else prev_bottom + 34 + h / 2
        prev_bottom = cy + h / 2
        p = ease((local - L['t'] * FPS) / 9); op = p * op_out
        if op <= 0: continue
        sc = 0.94 + 0.06 * p; ww, hh = round(w * sc), round(h * sc)
        r = hh // 2 if L.get('pill') else round(46 * mag * sc)
        key = (ww, hh, r)
        if key not in _lift: _lift[key] = (rrect_mask(ww, hh, r), shadow(ww, hh, r, 22, 85))
        mask, (shm, pad) = _lift[key]
        x, y = round(LIFT_CX - ww / 2), round(cy - hh / 2)
        paste_alpha(canvas, Image.new('RGB', shm.size, (40, 30, 20)), (x - pad, y - pad + 16), shm, op)
        paste_alpha(canvas, src.crop(box).resize((ww, hh), Image.Resampling.LANCZOS), (x, y), mask, op)
        placed.append((L['box'], x, y, ww, hh, p))
    return placed

def draw_taps(canvas, s, local, placed):
    for j, fr, fx, fy in s.get('taps', []):
        t = (local - s['clip_start'][j] - fr) / 13
        if not 0 <= t < 1: continue
        cx, cy, k = PX + fx * SW, PY + fy * SH, 1.0
        for (x0, y0, x1, y1), x, y, ww, hh, p in placed:
            if p > 0.5 and x0 <= fx <= x1 and y0 <= fy <= y1:
                cx, cy, k = x + (fx - x0) / (x1 - x0) * ww, y + (fy - y0) / (y1 - y0) * hh, ww / ((x1 - x0) * SW)
        r = round(SW * (0.05 + 0.045 * ease(t)) * k); d = r * 2 + 2
        m = Image.new('L', (d * 3, d * 3), 0); ImageDraw.Draw(m).ellipse((0, 0, d * 3 - 1, d * 3 - 1), fill=255)
        paste_alpha(canvas, Image.new('RGB', (d, d), (70, 70, 70)), (round(cx - d / 2), round(cy - d / 2)),
                    m.resize((d, d), Image.Resampling.LANCZOS), 0.42 * (1 - t) ** 1.5)

def fit(lines, name, maxpx, width):
    px = maxpx
    while max(font(name, px).getlength(t) for t in lines) > width: px -= 2
    return font(name, px), px

_text = {}
def text_layer(t, fnt, fill):
    key = (t, fnt.path, fnt.size, fill)
    if key not in _text:
        l, top, r, b = fnt.getbbox(t); im = Image.new('L', (r - l + 8, b + 8), 0)
        ImageDraw.Draw(im).text((4 - l, 4), t, font=fnt, fill=255)
        _text[key] = (Image.new('RGB', im.size, fill), im, r - l)
    return _text[key]

def draw_text(canvas, s, local, hook):
    if 'head' not in s: return
    colw = (HOOK[2] - COL - 70) if (hook and FMT == 'L') else COLW
    hf, px = fit(s['head'], 'BebasNeue-Regular.ttf', HEAD_MAX, colw)
    sf, _ = fit([s['sub']], 'Roboto-Medium.ttf', SUB_PX, colw + (60 if FMT == 'L' else 0))
    pitch = round(px * 0.9); cap = hf.getbbox('H'); captop, caph = cap[1], cap[3] - cap[1]
    block = pitch * (len(s['head']) - 1) + caph + 34 + SUB_PX
    y0 = (H - block) // 2 if FMT == 'L' else 215
    out = clamp((s['n'] - local) / 5)
    rows = [(t, hf, INK if i == 0 else GREEN, y0 + i * pitch - captop, i * 4) for i, t in enumerate(s['head'])]
    rows.append((s['sub'], sf, GREY, y0 + pitch * (len(s['head']) - 1) + caph + 34 - sf.getbbox('H')[1], 10))
    for i, (t, fnt, fill, y, delay) in enumerate(rows):
        if hook: delay = (0, 16, 30)[i]
        p = 1.0 if (hook and i == 0) else ease((local - delay) / 10)
        col, mask, tw = text_layer(t, fnt, fill)
        x = COL if FMT == 'L' else (W - tw) // 2
        paste_alpha(canvas, col, (x - 4, round(y + (1 - p) * 26) - 4), mask, p * out)

ICON_PX = 230
_icon = Image.open(ICON).convert('RGB').resize((ICON_PX, ICON_PX), Image.Resampling.LANCZOS)
ICON_MASK = rrect_mask(ICON_PX, ICON_PX, round(ICON_PX * 0.2237))
IC_SHADOW, IC_PAD = shadow(ICON_PX, ICON_PX, round(ICON_PX * 0.2237), 18, 60)

def draw_end(canvas, local):
    wf, tf, nf = font('BebasNeue-Regular.ttf', 210), font('Roboto-Medium.ttf', 50), font('Roboto-Regular.ttf', 40)
    cap = wf.getbbox('H'); caph = cap[3] - cap[1]
    block = ICON_PX + 54 + caph + 40 + 50 + 30 + 40
    y = (H - block) // 2 - (60 if FMT == 'P' else 0)
    p = ease((local - 8) / 10); sc = 0.9 + 0.1 * p
    if p > 0:
        px = round(ICON_PX * sc); x, yy = (W - px) // 2, y + (ICON_PX - px) // 2
        paste_alpha(canvas, Image.new('RGB', IC_SHADOW.size, (40, 30, 20)), ((W - ICON_PX) // 2 - IC_PAD, y - IC_PAD + 12), IC_SHADOW, p)
        paste_alpha(canvas, _icon.resize((px, px), Image.Resampling.LANCZOS), (x, yy), ICON_MASK.resize((px, px), Image.Resampling.LANCZOS), p)
    y += ICON_PX + 54
    rows = [('LEANRRR', wf, INK, y - cap[1], 13), ('The calorie tracker for takeaway.', tf, GREEN, y + caph + 40 - tf.getbbox('H')[1], 19),
            ('No account. No sign-up.', nf, GREY, y + caph + 40 + 50 + 30 - nf.getbbox('H')[1], 27)]
    for t, fnt, fill, ty, delay in rows:
        q = ease((local - delay) / 10); col, mask, tw = text_layer(t, fnt, fill)
        paste_alpha(canvas, col, ((W - tw) // 2 - 4, round(ty + (1 - q) * 22) - 4), mask, q)

def render(f):
    canvas = BG.copy()
    i = max(k for k in range(len(SCENES)) if START[k] <= f); s = SCENES[i]; local = f - START[i]
    if s['k'] == 'hook':
        hw, hh, hx, hy = HOOK; out = ease((local - (s['n'] - 9)) / 9)
        y = hy + round(out * (H - hy + 60))
        paste_alpha(canvas, Image.new('RGB', HK_SHADOW.size, (40, 30, 20)), (hx - HK_PAD, y - HK_PAD + 18), HK_SHADOW)
        clip = seg_frame('hook' + FMT, local).resize((hw, hh), Image.Resampling.LANCZOS)
        canvas.paste(clip, (hx, y), HOOK_MASK)
        draw_text(canvas, s, local, True)
    elif s['k'] == 'end':
        dy = round(ease(local / 12) * (H - PY + 80))
        if dy < H - PY + 60: draw_phone(canvas, P1, dy)
        draw_end(canvas, local)
    else:
        dy = round((1 - ease((f - P0) / 16)) * (H - PY + 80)) if i == 1 else 0
        src = draw_phone(canvas, f, dy)
        placed = draw_lifts(canvas, s, src, local, clamp((s['n'] - local) / 5))
        draw_taps(canvas, s, local, placed)
        draw_text(canvas, s, local, False)
    return canvas

if PREVIEW:
    for f in PREVIEW: render(f).save(f'preview-{FMT}-{f:04d}.png')
    print('frames', TOTAL, 'starts', START); sys.exit()
enc = subprocess.Popen([FF, '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{W}x{H}', '-r', str(FPS),
                        '-i', '-', '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p',
                        '-colorspace', 'bt709', '-color_primaries', 'bt709', '-color_trc', 'bt709', '-movflags', '+faststart', OUT], stdin=subprocess.PIPE)
for f in range(TOTAL):
    enc.stdin.write(render(f).tobytes())
    if f % 60 == 0: print(f, '/', TOTAL, flush=True)
enc.stdin.close(); enc.wait(); print('wrote', OUT)
