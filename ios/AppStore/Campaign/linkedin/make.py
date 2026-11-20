"""LinkedIn profile picture (logo) and banner, from the App Store header art and the app icon."""
from PIL import Image
import numpy as np
HEADER = 'header/header-5244x2950.png'
ICON = '../../MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png'
P = 47  # dot-grid pitch in the header, px

hd = Image.open(HEADER).convert('RGB')

# Banner: rebuild the left strip (paper bag and its shadow) from a clean, grid-aligned tile; the profile photo sits over that corner.
tile = hd.crop((0, 50 * P, 10 * P, 60 * P))
fill = Image.new('RGB', hd.size)
for ty in range(0, hd.height, 10 * P):
    for tx in range(0, hd.width, 10 * P):
        fill.paste(tile, (tx, ty))
ramp = np.clip((1268 - np.arange(hd.width)) / 60, 0, 1)  # solid past the bag, fades out just before the bowl
mask = Image.fromarray((np.tile(ramp, (hd.height, 1)) * 255).astype('uint8'))
hd = Image.composite(fill, hd, mask)
cy = 1180; h = 5244 // 4
hd.crop((0, cy - h // 2, 5244, cy - h // 2 + h)).resize((3168, 792), Image.Resampling.LANCZOS).save('linkedin/leanrrr-linkedin-banner-3168x792.png')

# Profile picture: logo glyph in cream on the dot-grid green.
S = 1024
bg = Image.open(HEADER).convert('RGB').crop((2000, 1880, 2000 + S, 1880 + S))
lum = np.asarray(Image.open(ICON).convert('L')).astype(float)
a = np.clip((190 - lum) / 140, 0, 1); ys, xs = np.where(a > 0.5)
g = Image.fromarray((a * 255).astype('uint8')).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
gh = int(S * 0.50); g = g.resize((round(g.width * gh / g.height), gh), Image.Resampling.LANCZOS)
cream = Image.new('RGB', g.size, (246, 242, 234))
bg.paste(cream, ((S - g.width) // 2, (S - g.height) // 2), g)
bg.save('linkedin/leanrrr-profile-1024.png')
