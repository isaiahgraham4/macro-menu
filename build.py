#!/usr/bin/env python3
"""Build the installable app (GitHub Pages serves docs/) from index.html, the page that is also published as the Claude artifact.

Run:  python3 build.py
"""
import hashlib, json, pathlib, re

ROOT = pathlib.Path(__file__).parent
OUT = ROOT / 'docs'
SRC = (ROOT / 'index.html').read_text()

NAME, SHORT = 'Macro Menu', 'Macro Menu'
THEME, BG = '#1E6B47', '#F3F5F0'
DESC = 'Find the fast-food order that fits your calories, protein and budget, build meals and track your day.'

# The artifact file starts with <title>, font links and <style>; those belong in <head>.
split = SRC.index('<div class="wrap">')
head_part, body_part = SRC[:split], SRC[split:]

# Same small reset the artifact viewer adds around the page.
RESET = """<style>
:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}
body{margin:0}img{max-width:100%}[hidden]{display:none!important}
</style>"""

version = hashlib.sha1(SRC.encode()).hexdigest()[:10]

REGISTER = f"""<script>
if ('serviceWorker' in navigator) {{
  navigator.serviceWorker.register('sw.js').then(reg => {{
    // An update found while the app is open takes over on the next launch; say so once.
    reg.addEventListener('updatefound', () => {{
      const w = reg.installing;
      w?.addEventListener('statechange', () => {{
        if (w.state === 'installed' && navigator.serviceWorker.controller && typeof toast === 'function') toast('Update ready. It will load next time you open the app.');
      }});
    }});
  }}).catch(() => {{}});
}}
</script>"""

html = f"""<!doctype html>
<html lang="en-AU" data-standalone data-version="{version}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="description" content="{DESC}">
<meta name="theme-color" content="{THEME}">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" type="image/png" sizes="192x192" href="icons/icon-192.png">
<link rel="apple-touch-icon" href="icons/apple-touch-icon.png">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="{SHORT}">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
{RESET}
{head_part.strip()}
</head>
<body>
{body_part.strip()}
{REGISTER}
</body>
</html>
"""

manifest = {
    "name": NAME, "short_name": SHORT, "description": DESC,
    "id": "./", "start_url": "./", "scope": "./", "display": "standalone",
    "background_color": BG, "theme_color": THEME, "lang": "en-AU", "categories": ["food", "health", "lifestyle"],
    "icons": [
        {"src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png"},
        {"src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png"},
        {"src": "icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable"},
    ],
}

SW = f"""// Macro Menu offline cache. Version changes whenever index.html changes.
const CACHE = 'macro-menu-{version}';
const CORE = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png', './icons/apple-touch-icon.png'];

self.addEventListener('install', e => {{
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(CORE)));
}});
self.addEventListener('activate', e => {{
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
}});
self.addEventListener('fetch', e => {{
  const req = e.request;
  if (req.method !== 'GET') return;
  // The app page: newest from the network when online, cached copy when offline.
  if (req.mode === 'navigate') {{
    e.respondWith(fetch(req).then(res => {{ const copy = res.clone(); caches.open(CACHE).then(c => c.put('./index.html', copy)); return res; }})
      .catch(() => caches.match('./index.html')));
    return;
  }}
  // Everything else (icons, fonts): cached copy first, refreshed in the background.
  e.respondWith(caches.match(req).then(hit => {{
    const net = fetch(req).then(res => {{ if (res.ok || res.type === 'opaque') {{ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }} return res; }}).catch(() => hit);
    return hit || net;
  }}));
}});
"""


def icons():
    from PIL import Image, ImageDraw, ImageFont
    (OUT / 'icons').mkdir(parents=True, exist_ok=True)
    font_path = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'

    def draw(size, safe, rounded):
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        r = int(size * 0.22) if rounded else 0
        d.rounded_rectangle([0, 0, size - 1, size - 1], radius=r, fill=THEME)
        inner = size * safe
        f = ImageFont.truetype(font_path, int(inner * 0.46))
        text = 'MM'
        tb = d.textbbox((0, 0), text, font=f)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        x = (size - tw) / 2 - tb[0]
        y = size / 2 - th * 0.62 - tb[1]
        d.text((x, y), text, font=f, fill='#FFFFFF')
        # three macro bars: protein, carbs, fat
        bw, bh = inner * 0.62, inner * 0.07
        bx, by = (size - bw) / 2, size / 2 + th * 0.55
        for frac, col in ((0.42, '#7FA2FF'), (0.33, '#E5B04A'), (0.25, '#EE8067')):
            w = bw * frac
            d.rounded_rectangle([bx, by, bx + w - inner * 0.015, by + bh], radius=bh / 2, fill=col)
            bx += w
        return img

    draw(512, 0.86, True).save(OUT / 'icons/icon-512.png')
    draw(192, 0.86, True).resize((192, 192)).save(OUT / 'icons/icon-192.png')
    draw(512, 0.62, False).save(OUT / 'icons/icon-maskable-512.png')
    ap = draw(180, 0.86, False)
    bg = Image.new('RGB', (180, 180), THEME); bg.paste(ap, (0, 0), ap); bg.save(OUT / 'icons/apple-touch-icon.png')


OUT.mkdir(exist_ok=True)
(OUT / 'index.html').write_text(html)
(OUT / 'manifest.webmanifest').write_text(json.dumps(manifest, indent=2))
(OUT / 'sw.js').write_text(SW)
(OUT / '.nojekyll').write_text('')
icons()
print(f'Built docs/ (version {version})')
