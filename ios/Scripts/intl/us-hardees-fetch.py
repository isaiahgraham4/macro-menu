#!/usr/bin/env python3
"""Hardee's (US): the Nutritional Information poster on hardees.com/nutritional-info, saved as us-hardees-source.json.

hardees.com/nutritional-info shows the whole guide as one large poster image (a Kentico content asset, linked from the page,
so a plain request finds the current edition). There's no PDF or text version, so the poster is read with the macOS Vision
text recogniser (ocr-pages.swift in this folder, compiled to the temp folder on first run) in overlapping strips.
The poster gives each item its allergen letters (E egg, F fish, M milk, P peanut, SF shellfish, S soy, T tree nut, W wheat,
SS sesame: the nine US majors; "+" marks ice cream made where peanuts or tree nuts are present), then serving weight,
calories, calories from fat, fat, saturated fat, trans fat, cholesterol, sodium, carbs, fibre, sugars and protein.

Reading the poster:
- Vision skips most lone "0"s (and the odd other number), so every cell is also read glyph by glyph: the poster uses one
  typeface, so each character's shape is learnt from the cells Vision did read, and a cell Vision skipped is read from
  those shapes (a glyph unlike all of them leaves the cell null). Where Vision and the glyph reading disagree and only the
  glyph reading fits the row's macros, the glyph reading is used (counted in `src`);
- rows with Small / Medium / Large figures in one cell ("97 / 102 / 144") become one row per size;
- a row must have calories, protein, carbs and fat, and calories must be within a third of 4p + 4c + 9f (misreads and
  misprints are counted in `src`); saturated fat above total fat is dropped to null.
Left out: kids' meals (they include fries and a drink) and bottled water. Fountain drinks are listed per cup size
(the poster's serving column gives fluid ounces for them).

Run: python3 ios/Scripts/intl/us-hardees-fetch.py
The same reader is used by us-carlsjr-fetch.py (Carl's Jr. publishes the same poster format).
"""
import json
import os
import pathlib
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
# Downloads and OCR scratch are kept out of the repo: $PDF_DIR, or the system temp folder
TMP = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
KEYS = ['g', 'cal', 'calfat', 'f', 'sat', 'trans', 'chol', 'sodium', 'c', 'fibre', 'sugar', 'p']
LETTERS = {'E': ['egg'], 'F': ['fish'], 'M': ['milk'], 'P': ['peanut'], 'SF': ['shellfish'], 'S': ['soy'], 'T': ['treenut'],
           'W': ['gluten', 'wheat'], 'SS': ['sesame']}
NUM = r'(?:\d+(?:\.\d+)?|<\s?1)'
SLASH = re.compile(rf'{NUM}(?:\s*/\s*{NUM})+')


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def num(s):
    if s is None:
        return None
    s = s.strip().replace('<1', '0.5').replace('< 1', '0.5')
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def ocr_binary():
    exe = TMP / 'leanr-ocr-pages'
    src = HERE / 'ocr-pages.swift'
    if not exe.exists() or exe.stat().st_mtime < src.stat().st_mtime:
        subprocess.run(['swiftc', '-O', str(src), '-o', str(exe)], check=True)
    return str(exe)


def poster_image(page_url, pattern, name):
    """Download the poster linked from the nutrition page; returns (path, asset url)."""
    html = get(page_url).decode('utf-8', 'replace')
    m = re.search(r'src="(/getContentAsset/[^"]*' + pattern + r'[^"]*\.(?:jpg|jpeg|png)[^"]*)"', html, re.I)
    if not m:
        raise SystemExit(f'{name}: the nutrition poster image is missing from {page_url}')
    url = urllib.parse.urljoin(page_url, m.group(1).replace('&amp;', '&'))
    TMP.mkdir(parents=True, exist_ok=True)
    path = TMP / (re.sub(r'\W+', '-', name.lower()).strip('-') + '-poster.jpg')
    path.write_bytes(get(url))
    return path, url


def ocr_words(img, strip=700, overlap=160):
    """Every recognised line on the poster, in image pixels: [{t, x0, x1, cx, cy, h}]."""
    pg = pymupdf.open(img)[0]
    full = pymupdf.Pixmap(str(img))
    W, H = full.width, full.height
    s = W / pg.rect.width
    tiles, y, i = [], 0, 0
    tdir = pathlib.Path(tempfile.mkdtemp(dir=TMP))
    while y < H:
        y1 = min(H, y + strip + overlap)
        p = pg.get_pixmap(clip=pymupdf.Rect(0, y / s, W / s, y1 / s), matrix=pymupdf.Matrix(s, s))
        f = tdir / f'tile{i:03d}.png'
        p.save(str(f))
        tiles.append((f, y, p.width, p.height))
        i += 1
        y += strip
    out = subprocess.run([ocr_binary()] + [str(t[0]) for t in tiles], capture_output=True, text=True, check=True).stdout
    by = {}
    for line in out.splitlines():
        d = json.loads(line)
        by[d['file']] = d['lines']
    words = []
    for f, y0, w, h in tiles:
        for l in by.get(f.name, []):
            ly = (l['y'] + l['h'] / 2) * h          # each strip keeps the words centred in its own band
            if ly >= strip + overlap / 2 and y0 + h < H or y0 > 0 and ly < overlap / 2:
                continue
            x = l['x'] * w
            words.append({'t': l['t'].strip(), 'x0': x, 'x1': x + l['w'] * w, 'cx': x + l['w'] * w / 2,
                          'cy': y0 + ly, 'h': l['h'] * h})
    for f, *_ in tiles:
        f.unlink()
    tdir.rmdir()
    return words, full


class Gray:
    """The poster as one grey byte per pixel, with the glyph reader's helpers."""

    def __init__(self, pix):
        g = pymupdf.Pixmap(pymupdf.csGRAY, pix) if pix.n > 1 else pix
        self.W, self.H, self.b = g.width, g.height, bytes(g.samples)

    def dark(self, x, y):
        return self.b[y * self.W + x] < 120

    def rules(self, ys, half):
        """x positions of the vertical column rules: dark in almost every sampled row band."""
        pts = [y for cy in ys for y in range(int(cy - half), int(cy + half), 3)]
        xs = [x for x in range(self.W) if sum(self.dark(x, y) for y in pts) > len(pts) * 0.9]
        out = []
        for x in xs:
            if out and x - out[-1][-1] <= 3:
                out[-1].append(x)
            else:
                out.append([x])
        return [(r[0], r[-1]) for r in out]

    def glyphs(self, x0, x1, y0, y1):
        """Glyphs left to right in a box: [(features, x0, x1)], split where a pixel column has no ink."""
        x0, x1, y0, y1 = int(x0), int(x1), int(max(0, y0)), int(min(self.H - 1, y1))
        colink = [any(self.dark(x, y) for y in range(y0, y1)) for x in range(x0, x1)]
        runs, start = [], None
        for i, on in enumerate(colink + [False]):
            if on and start is None:
                start = i
            elif not on and start is not None:
                runs.append((x0 + start, x0 + i))
                start = None
        out = []
        for gx0, gx1 in runs:
            ys = [y for y in range(y0, y1) if any(self.dark(x, y) for x in range(gx0, gx1))]
            gy0, gy1 = ys[0], ys[-1] + 1
            w, h = gx1 - gx0, gy1 - gy0
            if w * h < 6:
                continue            # specks
            feat = []
            for j in range(16):
                for i in range(10):
                    xa, xb = gx0 + w * i // 10, max(gx0 + w * (i + 1) // 10, gx0 + w * i // 10 + 1)
                    ya, yb = gy0 + h * j // 16, max(gy0 + h * (j + 1) // 16, gy0 + h * j // 16 + 1)
                    tot = (xb - xa) * (yb - ya)
                    feat.append(sum(self.dark(x, y) for x in range(xa, xb) for y in range(ya, yb)) / tot)
            feat += [h / (y1 - y0) * 4, w / h * 2, (gy0 + gy1) / 2 / (y1 - y0) * 4 - (y0 / (y1 - y0)) * 4]
            out.append((feat, gx0, gx1))
        return out


def classify(feat, templates):
    best, bd = None, None
    for ch, t in templates.items():
        d = sum((a - b) ** 2 for a, b in zip(feat, t))
        if bd is None or d < bd:
            best, bd = ch, d
    return best, bd


def read_cell(gray, box, templates, limit):
    """Text of a cell from the glyph templates, or None when a glyph is unlike any template."""
    gl = gray.glyphs(*box)
    out = ''
    for feat, gx0, gx1 in gl:
        ch, d = classify(feat, templates)
        if ch is None or d > limit:
            return None
        out += ch
    return out


def read_allergen_cell(gray, box, templates, limit):
    """Allergen letters from glyph templates. '+' is the legend's only symbol; when Vision never read one there's no
    template for it, so a last glyph that sits apart from the letters and matches nothing is taken as '+'."""
    gl = gray.glyphs(*box)
    out = ''
    for k, (feat, gx0, gx1) in enumerate(gl):
        ch, d = classify(feat, templates)
        if ch is not None and d <= limit and (ch.isalpha() and ch.isupper() or ch == ','):
            out += ch
        elif '+' not in templates and k == len(gl) - 1 and k and gx0 - gl[k - 1][2] > (gx1 - gx0) * 0.5:
            out += ' +'
        else:
            return None
    return out


def read_poster(img):
    """Rows of the poster: [{'name', 'section', 'alg': text or None, 'cells': [12 strings/None], 'notes': set()}]."""
    words, pix = ocr_words(img)
    gray = Gray(pix)
    isnum = lambda t: re.fullmatch(NUM, t) or SLASH.fullmatch(t) or re.fullmatch(r'\d+\s?oz', t)
    # the 12 number columns: clusters of number positions
    xs = sorted(w['cx'] for w in words if re.fullmatch(r'\d+(\.\d+)?', w['t']) and w['cx'] > pix.width * 0.2)
    cl = [[xs[0]]]
    for v in xs[1:]:
        (cl[-1].append(v) if v - cl[-1][-1] <= pix.width * 0.009 else cl.append([v]))
    cl = [c for c in cl if len(c) >= 8]
    if len(cl) != 12:
        raise SystemExit(f'poster: found {len(cl)} number columns, expected 12')
    cols = [sum(c) / len(c) for c in cl]
    half = min(b - a for a, b in zip(cols, cols[1:])) * 0.45
    name_edge = cols[0] - (cols[1] - cols[0]) * 1.6        # allergen column sits between the names and the first figures
    hmed = sorted(w['h'] for w in words)[len(words) // 2]

    names, figs, algs = [], [], []
    for w in words:
        if w['x0'] < name_edge - (cols[1] - cols[0]) * 0.6 and not isnum(w['t']):
            names.append(w)
        elif w['cx'] < cols[0] - half:
            algs.append(w)
        elif isnum(w['t'].replace(' ', '')) or isnum(w['t']):
            figs.append(w)
    names.sort(key=lambda w: w['cy'])
    gaps = sorted(b['cy'] - a['cy'] for a, b in zip(names, names[1:]) if b['cy'] - a['cy'] > hmed * 0.8)
    pitch = gaps[len(gaps) // 4] if gaps else hmed * 1.3
    tol = pitch * 0.45

    figs.sort(key=lambda w: w['cy'])
    frows = []
    for w in figs:
        if frows and abs(w['cy'] - frows[-1]['cy']) < hmed * 0.5:
            frows[-1]['w'].append(w)
            frows[-1]['cy'] = sum(x['cy'] for x in frows[-1]['w']) / len(frows[-1]['w'])
        else:
            frows.append({'cy': w['cy'], 'w': [w]})
    claimed, rows = set(), []
    for fr in frows:
        near = [i for i, n in enumerate(names) if i not in claimed and abs(n['cy'] - fr['cy']) <= tol]
        if not near:
            continue
        near = [i for i in near if not re.sub(r'[^A-Za-z]', '', names[i]['t']).isupper()] or near
        claimed.update(near)
        ws = sorted((names[i] for i in near), key=lambda w: (round(w['cy'] / hmed), w['x0']))
        # a word read twice in the strips' overlap (sometimes in pieces): keep the longer reading
        ws = [w for w in ws if not any(o is not w and len(o['t']) > len(w['t']) and abs(o['cy'] - w['cy']) < hmed * 0.5 and min(o['x1'], w['x1']) - max(o['x0'], w['x0'])
                                       > (w['x1'] - w['x0']) * 0.5 for o in ws)]
        rows.append({'cy': fr['cy'], 'name': ' '.join(w['t'] for w in ws),
                     'top': min(names[i]['cy'] for i in near), 'figs': fr['w']})
    heads = []
    for i, n in enumerate(names):
        if i in claimed:
            continue
        if re.sub(r'[^A-Za-z]', '', n['t']).isupper():
            heads.append(n)
        elif not any(abs(r['cy'] - n['cy']) <= tol * 1.6 for r in rows):
            rows.append({'cy': n['cy'], 'name': n['t'], 'top': n['cy'], 'figs': []})
    rows.sort(key=lambda r: r['cy'])

    # cell boxes: between the column rules, and half a row pitch around each row's centre
    rules = gray.rules([r['cy'] for r in rows if r['figs']][:40], pitch * 0.3)
    bounds = []
    for c in [name_edge + (cols[0] - half * 1.2 - name_edge) / 2] + cols:
        left = max((r[1] for r in rules if r[1] < c), default=c - half)
        right = min((r[0] for r in rules if r[0] > c), default=c + half)
        bounds.append((left + 3, right - 2))
    ybox = lambda r: (r['cy'] - pitch * 0.42, r['cy'] + pitch * 0.42)

    # what the recogniser read per cell; glyph templates from the cells it read whole
    read = []
    samples = {}
    for r in rows:
        cells = [[] for _ in cols]
        for w in r['figs']:
            ci = min(range(12), key=lambda i: abs(cols[i] - w['cx']))
            if bounds[ci + 1][0] - 4 <= w['cx'] <= bounds[ci + 1][1] + 4:
                cells[ci].append(w)
        texts = []
        for ws in cells:          # a word read twice (once in each overlapping strip) counts once
            ws = sorted(ws, key=lambda w: w['x0'])
            ws = [w for k, w in enumerate(ws) if not any(o['t'] == w['t'] and abs(o['cx'] - w['cx']) < hmed for o in ws[:k])]
            texts.append(' '.join(w['t'] for w in ws) if ws else None)
        alg = [w for w in algs if abs(w['cy'] - r['cy']) <= tol]
        atext = ' '.join(w['t'] for w in sorted(alg, key=lambda w: w['x0'])) or None
        read.append((atext, texts))
        for ci, t in enumerate([atext] + texts):
            if not t:
                continue
            chars = t.replace(' ', '')
            gl = gray.glyphs(bounds[ci][0], bounds[ci][1], *ybox(r))
            if len(gl) == len(chars):
                for ch, (feat, *_) in zip(chars, gl):
                    samples.setdefault(ch, []).append(feat)
    templates = {ch: [sum(v) / len(fs) for v in zip(*fs)] for ch, fs in samples.items() if len(fs) >= 2}
    # how far a glyph may be from its template: well beyond the spread of the harvested samples
    spread = sorted(classify(f, templates)[1] for fs in samples.values() for f in fs)
    limit = spread[int(len(spread) * 0.98)] * 2.5 if spread else 0

    out = []
    for r, (atext, texts) in zip(rows, read):
        vals, notes, alts = [], set(), {}
        for ci, t in enumerate(texts):
            box = (bounds[ci + 1][0], bounds[ci + 1][1], *ybox(r))
            g = read_cell(gray, box, templates, limit)
            if t:
                vals.append(t)
                if g and g != t.replace(' ', '') and re.fullmatch(NUM, g):
                    alts[ci] = g        # the glyph reading disagrees: kept to try if the row fails its check
                continue
            if g is None or g and not (re.fullmatch(NUM, g) or SLASH.fullmatch(g)):
                vals.append(None)
                notes.add(KEYS[ci])
            else:
                vals.append(g or None)
        if atext is None:
            atext = read_allergen_cell(gray, (bounds[0][0], bounds[0][1], *ybox(r)), templates, limit)
        above = [h['t'] for h in heads if h['cy'] < r['top']]
        out.append({'name': r['name'], 'section': above[-1] if above else '', 'alg': atext, 'cells': vals, 'notes': notes, 'alts': alts,
                    'empty': not r['figs'] and all(v is None for v in vals)})
    return out


def allergens(text, where):
    if text is None:
        return None, None
    toks = re.findall(r'SS|SF|[A-Z]|\+', text.upper().replace('5', 'S'))
    contains, may = set(), set()
    for t in toks:
        if t == '+':
            may.update(['peanut', 'treenut'])
        elif t in LETTERS:
            contains.update(LETTERS[t])
        else:
            return None, None
    return sorted(contains), sorted(may - contains)


def expand(rows):
    """One row per size for 'Small / Medium / Large' rows; values parsed to numbers."""
    out = []
    for r in rows:
        cells = [c.replace(' ', '') if c else c for c in r['cells']]
        split = [c.split('/') if c and '/' in c else None for c in cells]
        n = max((len(s) for s in split if s), default=1)
        m = re.match(r'(.*?)\s*-\s*((?:Small|Medium|Large|Regular|Kids)(?:\s*/\s*(?:Small|Medium|Large|Regular|Kids))+)$', r['name'])
        if n > 1:
            sizes = [s.strip().lower() for s in m.group(2).split('/')] if m else []
            if len(sizes) != n or any(s and len(s) != n for s in split):
                continue
            for k in range(n):
                vals = [num(s[k]) if s else num(c) for s, c in zip(split, cells)]
                out.append(dict(r, name=f'{m.group(1)} ({sizes[k]})', v=dict(zip(KEYS, vals)), serve_g=vals[0]))
        else:
            vals = [num(c) if not (c and re.search(r'oz', c)) else c for c in cells]
            alt = dict(zip(KEYS, vals))
            alt.update({KEYS[ci]: num(g) for ci, g in r.get('alts', {}).items()})
            out.append(dict(r, v=dict(zip(KEYS, vals)), alt=alt if r.get('alts') else None, serve_g=vals[0]))
    return out


def edition_from(words_text):
    m = re.search(r'current as of ([A-Z][a-z]+ \d{1,2}, \d{4}|\d{1,2}[-/]\d{1,2}[-/]\d{2,4})', words_text)
    return m.group(1) if m else None


def build(chain, name, page_url, pattern, tidy, category, meat, skip, note=''):
    img, img_url = poster_image(page_url, pattern, name)
    rows = read_poster(img)
    items, dropped, unread, seen, fixed = [], [], [], set(), []
    ok = lambda v: all(isinstance(v[k], (int, float)) for k in ('cal', 'p', 'c', 'f'))
    fits = lambda v: abs(4 * v['p'] + 4 * v['c'] + 9 * v['f'] - v['cal']) <= max(v['cal'] / 3, 15)
    rows = expand(rows)
    # the same name with its letters split differently ("Diet Co ke"): use the spelling most rows have
    spell = {}
    for r in rows:
        t = tidy(r['name'], r) or ''
        spell.setdefault(re.sub(r'\W', '', t.lower()), []).append(t)
    best = {k: max(set(v), key=v.count) for k, v in spell.items()}
    for r in rows:
        if r.get('empty'):
            continue                # footnotes and other text lines
        nm = tidy(r['name'], r)
        nm = best.get(re.sub(r'\W', '', (nm or '').lower()), nm)
        if nm is None or skip(nm, r):
            continue
        v = r['v']
        if r.get('alt') and ok(r['alt']) and fits(r['alt']) and not (ok(v) and fits(v)):
            v = r['alt']
            fixed.append(nm)
        if not ok(v):
            unread.append(nm)
            continue
        if not fits(v):
            dropped.append(nm)
            continue
        sat = v['sat'] if isinstance(v['sat'], (int, float)) and v['sat'] <= v['f'] else None
        contains, may = allergens(r['alg'], nm)
        g = r['serve_g']
        if isinstance(g, str):
            serve = re.sub(r'(\d)\s*oz', r'\1 oz', g)
        elif g and 'BEVERAGE' in r['section'].upper():
            serve = f'{g} oz'
        elif g and (v['cal'] == 0 or v['cal'] / g <= 9.5):
            serve = f'1 serving ({g} g)'
        else:
            serve = '1 serving'
        if 'BEVERAGE' in r['section'].upper() and re.fullmatch(r'\d+ oz', serve) and f'({serve})' not in nm and not re.search(r'\((small|medium|large)', nm):
            nm = f'{nm} ({serve})'
        if nm in seen:
            continue
        seen.add(nm)
        items.append({
            'name': nm, 'cat': category(nm, r), 'serve': serve,
            'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'], 'sat': sat,
            'sugar': v['sugar'] if isinstance(v['sugar'], (int, float)) else None,
            'fibre': v['fibre'] if isinstance(v['fibre'], (int, float)) else None,
            'sodium': v['sodium'] if isinstance(v['sodium'], (int, float)) else None, 'salt': None,
            'contains': contains, 'may': may, 'vg': None, 'meat': meat(nm),
        })
    # a drink's sodium far above the next smaller cup's (the poster's 1184 mg for a 32 oz diet soda after 136 mg for 24 oz)
    odd_sodium = []
    cups = {}
    for i in items:
        m = re.match(r'(.*) \((\d+) oz\)$', i['name'])
        if m and isinstance(i['sodium'], (int, float)):
            cups.setdefault(m.group(1), []).append((int(m.group(2)), i))
    for base, lst in cups.items():
        lst.sort(key=lambda t: t[0])
        for (oz0, a), (oz1, b) in zip(lst, lst[1:]):
            if a['sodium'] and b['sodium'] > a['sodium'] * oz1 / oz0 * 3:
                odd_sodium.append(f"{b['name']} ({b['sodium']} mg)")
                b['sodium'] = None
    edition = re.search(r'(\d{1,2})-(\d{1,2})-(\d{2})\.jpg', img_url) or re.search(r'(20\d\d)\.jpg', img_url)
    if edition and len(edition.groups()) == 3:
        edition = f'dated {edition.group(1)}/{edition.group(2)}/20{edition.group(3)} (month/day/year)'
    elif edition:
        edition = f'{edition.group(1)} edition'
    else:
        edition = 'current edition'
    src = (f"{name} Nutritional Information poster (U.S.), {edition}, read from the poster image with OCR. Allergens are the "
           f"poster's letters (the nine US majors, sesame included); '+' (ice cream made where peanuts or tree nuts are "
           f"present) is may-contain peanut and tree nut. Cells the OCR skipped (mostly zeros) are read glyph by glyph from "
           f"character shapes learnt from the rest of the poster. Left out: kids' meals and bottled water{note}")
    if odd_sodium:
        src += f"; sodium left out where it can't be right next to the other cup sizes: {', '.join(odd_sodium)}"
    if fixed:
        src += f"; {len(fixed)} row(s) where the OCR and the glyph reading disagreed take the reading that fits the macros ({', '.join(fixed)})"
    if unread:
        src += f"; {len(unread)} row(s) whose calories or macros couldn't be read ({', '.join(unread)})"
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': chain, 'name': name, 'how': 'Official nutrition poster (image, read with OCR)', 'url': page_url,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    path = HERE / f'{chain}-source.json'
    path.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'{name}: {len(items)} items, {len(dropped)} dropped, {len(unread)} unreadable -> {path.name}')
    return out


def cat_is_drink(cat):
    return cat == 'drink'


# ---------- Hardee's ----------

CONFUSABLES = str.maketrans('аеорсхуіАЕОРСХМТВНК', 'aeopcxyiAEOPCXMTBHK')     # Cyrillic look-alikes OCR sometimes returns


def tidy(name, r):
    n = name.translate(CONFUSABLES).replace('®', '').replace('™', '').replace('°', '')
    n = re.sub(r'\blced\b', 'Iced', n)
    n = n.replace('®', '').replace('™', '').replace('’', "'").replace('‘', "'").replace('*', '').replace('"', '')
    n = re.sub(r'\s+', ' ', n).strip(' -')
    n = re.sub(r'\s*-\s*(Single|Double|Triple)$', lambda m: f' ({m.group(1).lower()})', n)
    n = re.sub(r'\s*-\s*(Small|Medium|Large)\s*\(([\d.]+) fl\.? ?oz\.?\)$', lambda m: f' ({m.group(1).lower()}, {m.group(2)} oz)', n)
    n = re.sub(r'\s*-\s*(Small|Medium|Large|Kids)$', lambda m: f' ({m.group(1).lower()})', n)
    n = re.sub(r'\s*\(([\d.]+) ?fl\.? ?oz\.?\)$', r' (\1 oz)', n)
    n = re.sub(r'\s*-\s*(Ham|Bacon|Sausage|Vanilla|Chocolate|Strawberry)$', r' (\1)', n)
    m = re.match(r'Hand-Scooped Ice-Cream Shake\W*\s*(Vanilla|Chocolate|Strawberry)\)?$', n)
    if m:
        n = f'{m.group(1)} Hand-Scooped Ice Cream Shake'
    return n


def category(name, r):
    n, sec = name.lower(), r['section'].upper()
    if re.search(r'sauce|dressing|ketchup|syrup|jelly', n) and 'pouch' not in n:
        return 'extra'
    if 'BEVERAGE' in sec or re.search(r'shake|coffee|lemonade|\btea\b|juice|milk\b|coca|\bcola\b|pepper|sprite|powerade', n):
        return 'drink'
    if 'DESSERT' in sec or re.search(r'cinnamon roll|turnover|cookie|cake', n):
        return 'sweet'
    if 'SIDE' in sec or re.search(r'fries|curly|hash rounds|grits|onion rings|potato', n):
        return 'side'
    if 'BREAKFAST' in sec:
        return 'breakfast'
    return 'main'


MEATS = [(r'chicken|\btenders?\b', 'chicken'),
         (r'burger|\bstar\b|frisco|thickburger|angus|roast beef|steak|beef|chili dog|western|mushroom & swiss|big carl|diablo|guacamole bacon', 'beef'),
         (r'bacon|sausage|\bham\b|pork|hot dog|monster biscuit|loaded omelet|biscuit .n. gravy', 'pork'), (r'\bfish\b', 'fish'), (r'turkey', 'turkey')]


def meat(name):
    n = name.lower()
    out = [m for pat, m in MEATS if re.search(pat, n)]
    if 'zucchini star' in n:
        out = []
    return out or None


def skip(name, r):
    return bool(re.search(r'(?i)kids meal|water|^\d+$', name)) or 'KIDS' in r['section'].upper() or len(name) < 3


if __name__ == '__main__':
    build('us-hardees', "Hardee's", 'https://www.hardees.com/nutritional-info', 'nutrition', tidy, category, meat, skip)
