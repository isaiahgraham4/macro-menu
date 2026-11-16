"""Print the Leanrrr mark and name onto a surface in a slide, as if stamped in ink (multiply blend keeps the paper grain)."""
from PIL import Image, ImageDraw, ImageFont
import numpy as np
ICON = '../../MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png'
FONT = '../../Shared/Fonts/BebasNeue-Regular.ttf'

def lockup(glyph_h, stacked=False, gap=0.28):
    lum = np.asarray(Image.open(ICON).convert('L')).astype(float)
    a = np.clip((190 - lum) / 140, 0, 1); ys, xs = np.where(a > 0.5)
    g = Image.fromarray((a * 255).astype('uint8')).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    S = 4; g = g.resize((round(g.width * glyph_h * S / g.height), glyph_h * S), Image.Resampling.LANCZOS)
    f = ImageFont.truetype(FONT, round(glyph_h * (0.62 if stacked else 1.18)) * S)
    l, t, r, b = f.getbbox('LEANRRR'); tw, th = r - l, b - t; pad = round(gap * glyph_h * S)
    if stacked:
        m = Image.new('L', (max(g.width, tw), g.height + pad + th), 0)
        m.paste(g, ((m.width - g.width) // 2, 0)); ImageDraw.Draw(m).text(((m.width - tw) // 2 - l, g.height + pad - t), 'LEANRRR', font=f, fill=255)
    else:
        m = Image.new('L', (g.width + pad + tw, max(g.height, th)), 0)
        m.paste(g, (0, (m.height - g.height) // 2)); ImageDraw.Draw(m).text((g.width + pad - l, (m.height - th) // 2 - t), 'LEANRRR', font=f, fill=255)
    return m.resize((m.width // S, m.height // S), Image.Resampling.LANCZOS)

def stamp(im, centre, glyph_h, angle=0, stacked=False, ink=(46, 34, 22), strength=0.86, clip=None):
    m = lockup(glyph_h, stacked)
    if angle: m = m.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    full = Image.new('L', im.size, 0); full.paste(m, (centre[0] - m.width // 2, centre[1] - m.height // 2))
    if clip is not None: full = Image.composite(full, Image.new('L', im.size, 0), clip)
    a = (np.asarray(full).astype(float) / 255 * strength)[..., None]
    px = np.asarray(im.convert('RGB')).astype(float)
    out = px * (1 - a * (1 - np.array(ink) / 255))
    return Image.fromarray(out.round().astype('uint8'))
