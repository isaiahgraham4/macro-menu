#!/usr/bin/env python3
"""Krispy Kreme (US): the per-item "Nutritional & Allergen Info" sheets linked from each product page on krispykreme.com/menu,
saved as us-krispykreme-source.json.

krispykreme.com/about/nutritional-info sends people to the menu; every product page there has a "Nutritional & Allergen Info"
button whose address (a PDF on Krispy Kreme's kktestkitchen.com image bucket) is in the page's server-rendered data. A plain
request gets the menu pages (/menu/doughnuts/all and /menu/coffee-and-drinks/all), each product page, and each PDF; no browser.

Each sheet is a one-page US nutrition facts label: serving sizes across the top (one column for a doughnut, 12/16/20/32 fl oz
for drinks), then calories, fat, saturated fat, trans fat, cholesterol, sodium, carbs, fibre, sugars (and added sugars) and
protein. The figures are read by position (rows by label, columns by the serving size above them), because the text layer
doesn't always list the columns left to right. Rows are named after the sheet's own title, since a few product pages link the
sheet for a variant (the oat milk version of a latte, say).

Left out:
- packaged coffee (ground coffee bags, K-Cups) and the Brew Box (8 servings of the brewed coffee that is listed per cup);
- 24-count Doughnut Dots boxes;
- product pages whose linked sheet is plainly for another drink (the Original Glazed Latte page links the Original Glazed
  Flavored Iced Coffee sheet, the Iced Caramel Mocha Coffee page links the Iced Caramel Mocha Latte with Oatmilk sheet);
- the two older landscape tables (espresso 2022, chillers 2020), which aren't single-item labels;
- rows whose calories are far from 4p + 4c + 9f (more than a third out), which are counted in `src`.
Allergens: the sheets' "Contains" lines and the facility statement only cover peanuts, tree nuts, soy, milk, eggs and wheat
(no sesame, fish or shellfish), so contains/may are null for every item.

Run: python3 ios/Scripts/intl/us-krispykreme-fetch.py
"""
import hashlib
import json
import os
import pathlib
import re
import tempfile
import urllib.request
from datetime import date, datetime

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-krispykreme-source.json'
# The PDFs are downloads, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir()) / 'us-krispykreme'
SITE = 'https://www.krispykreme.com'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
MENUS = [('doughnuts', 'sweet'), ('coffee-and-drinks', 'drink')]
ROWS = [('cal', r'^Calories$'), ('f', r'^Total Fat'), ('sat', r'^Saturated'), ('trans', r'^Trans'), ('chol', r'^Cholesterol'),
        ('sodium', r'^Sodium'), ('c', r'^Total Carbohydrates'), ('fibre', r'^Dietary Fiber'), ('sugar', r'^Sugars'),
        ('added', r'^Added Sugars'), ('p', r'^Protein')]
SKIP_SLUG = re.compile(r'ground-coffee|krispy-kreme-classic|coffee-box|^24-count')
# words in a product name that the sheet's title must also have, or the page links another item's sheet
KEY_WORDS = ['latte', 'coffee', 'iced', 'frozen', 'mocha', 'caramel', 'vanilla', 'chiller', 'chocolate', 'cappuccino', 'americano',
             'lemonade', 'mango', 'watermelon', 'strawberry', 'cookie', 'glazed', 'decaf']


def get(url):
    req = urllib.request.Request(url.replace(' ', '%20'), headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def rsc(html):
    """The Next.js server-rendered data (self.__next_f.push chunks) as one string."""
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.S)
    return json.loads('"' + ''.join(chunks) + '"') if chunks else ''


def num(s):
    s = s.strip().lower().replace('mg', '').replace('gram', '').strip()
    if s.startswith('less than') or s.startswith('<'):
        s = re.sub(r'^(less than|<)\s*', '', s)
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def tidy(t):
    t = re.sub(r'[®™]|TM\b', '', t).replace('’', "'")
    t = re.sub(r'\s+', ' ', t).strip()
    if t.isupper():
        t = t.title().replace("'S", "'s")
    return t


def title_of(page):
    """The sheet's title: the biggest text in the top of the page, in reading order."""
    spans = []
    for b in page.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            for s in l['spans']:
                if s['bbox'][1] < 110 and s['text'].strip():
                    spans.append(s)
    if not spans:
        return ''
    big = max(s['size'] for s in spans)
    top = sorted((s for s in spans if s['size'] >= big - 0.6), key=lambda s: (round(s['bbox'][1] / 8), s['bbox'][0]))
    text = ''
    for i, s in enumerate(top):           # spans can split a word ("Berry C" + "obbler")
        joined = i and abs(s['bbox'][0] - top[i - 1]['bbox'][2]) < 1.5 and not top[i - 1]['text'].endswith(' ')
        text += ('' if joined or not text else ' ') + s['text'].strip()
    return tidy(text)


def parse(page):
    """{'title', 'cols': [(header, {key: value})], 'revised'} from a portrait one-item label, or None for other layouts."""
    if page.rect.width > page.rect.height:
        return None
    words = page.get_text('words')
    lines = {}
    for w in words:
        lines.setdefault(round((w[1] + w[3]) / 2 / 3), []).append(w)
    labels = {}
    for k in sorted(lines):
        ws = sorted(lines[k], key=lambda w: w[0])
        lead = []                         # the label: the line's words before its first figure
        for w in ws:
            if re.fullmatch(r'<?[\d.,]+', w[4]) or w[0] > 200:
                break
            lead.append(w)
        text = ' '.join(w[4] for w in lead)
        for key, pat in ROWS:
            if lead and key not in labels and re.match(pat, text) and not text.startswith('Calories from'):
                labels[key] = ((ws[0][1] + ws[0][3]) / 2, max(w[2] for w in lead))
    if 'cal' not in labels or 'p' not in labels:
        return None
    # value tokens right of each label, on (about) the same line; "less than 1 gram" style cells kept together
    def cells(y, xmin):
        near = sorted((w for w in words if abs((w[1] + w[3]) / 2 - y) <= 5 and w[0] > xmin), key=lambda w: w[0])
        out = []
        for w in near:
            if out and w[0] - out[-1][2] < 6 and not re.fullmatch(r'<?[\d.]+', w[4]):
                out[-1] = (out[-1][0], out[-1][1], w[2], w[3], out[-1][4] + ' ' + w[4])
            elif out and re.fullmatch(r'less|than', out[-1][4].split()[-1]):
                out[-1] = (out[-1][0], out[-1][1], w[2], w[3], out[-1][4] + ' ' + w[4])
            else:
                out.append(w)
        return [w for w in out if re.match(r'<?[\d.]+|less than', w[4])]
    ycal, xlab = labels['cal']
    cal_cells = cells(ycal, xlab + 5)
    if not cal_cells:          # the label sits a little above its figures
        ycal += 3
        cal_cells = cells(ycal, xlab + 5)
    colx = [(w[0] + w[2]) / 2 for w in cal_cells]
    cols = [{} for _ in colx]
    for key, (y, xr) in labels.items():
        cs = cells(y, xr + 5) or cells(y + 3, xr + 5)
        for w in cs:
            i = min(range(len(colx)), key=lambda i: abs(colx[i] - (w[0] + w[2]) / 2))
            if abs(colx[i] - (w[0] + w[2]) / 2) < 22:
                cols[i][key] = num(w[4])
    # serving headers: words above the calories row, under each column
    yserve = next(((w[1] + w[3]) / 2 for w in words if w[4] == 'Serving'), ycal - 30)
    heads = []
    for x in colx:
        hw = sorted((w for w in words if yserve - 8 <= (w[1] + w[3]) / 2 < ycal - 4 and abs((w[0] + w[2]) / 2 - x) < 26),
                    key=lambda w: (round((w[1] + w[3]) / 2 / 4), w[0]))
        heads.append(' '.join(w[4] for w in hw))
    text = page.get_text()
    rev = re.search(r'Revised:?\s*(\d{1,2}/\d{1,2}/\d{4})', text)
    return {'title': title_of(page), 'cols': list(zip(heads, cols)), 'text': text, 'revised': rev.group(1) if rev else None}


def size_of(head):
    m = re.search(r'(\d+)\s*fl\.?\s*oz', head)
    return f'{m.group(1)} oz' if m else None


def main():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    products = []
    for menu, cat in MENUS:
        data = rsc(get(f'{SITE}/menu/{menu}/all').decode('utf-8', 'replace'))
        found = re.findall(r'"href":"all/([^"]+)","trackingData":\{"type":"product"[^}]*"text":"([^"]*)"', data)
        if not found:
            raise SystemExit(f'Krispy Kreme: no products found on /menu/{menu}/all')
        for slug, name in dict.fromkeys(found):
            products.append((menu, cat, slug, name))

    items, names, dropped, skipped, revised, seen_pdf = [], set(), [], [], [], set()
    for menu, cat, slug, name in products:
        if SKIP_SLUG.search(slug):
            skipped.append(name)
            continue
        html = get(f'{SITE}/menu/{menu}/all/{slug}').decode('utf-8', 'replace')
        m = re.search(r'nutrition-cta\\?".*?linkUrl\\?":\\?"(https?://[^"\\]+?\.pdf)', html)
        if not m:
            skipped.append(name)
            continue
        url = m.group(1)
        if url in seen_pdf:
            continue
        seen_pdf.add(url)
        path = PDF_DIR / (hashlib.md5(url.encode()).hexdigest()[:12] + '.pdf')
        path.write_bytes(get(url))
        sheet = parse(pymupdf.open(path)[0])
        if not sheet:
            skipped.append(name)
            continue
        title = sheet['title'] or tidy(name)
        pname, tl = tidy(name).lower(), title.lower()
        if set(tl.split()) < set(pname.split()):      # a short title ("Mocha") for the product's own sheet
            title = re.sub(r'\s*-\s*\d+ct$', '', tidy(name).replace(' Specialty', ''))
        elif any(k in pname and k not in tl for k in KEY_WORDS):
            skipped.append(f'{name} (links the {title} sheet)')
            continue
        if sheet['revised']:
            revised.append(datetime.strptime(sheet['revised'], '%m/%d/%Y').date())
        title = re.sub(r'\s+(\d+) Count$', r' (\1)', title)
        multi = len(sheet['cols']) > 1
        for head, v in sheet['cols']:
            if 'brew box' in head.lower() or 'servings' in head.lower():
                continue
            if any(v.get(k) is None for k in ('cal', 'p', 'c', 'f')):
                continue
            size = size_of(head)
            count = re.match(r'(\d+)\s+Doughnut', head)
            if count and int(count.group(1)) > 10:
                continue                       # 24-count box column
            if size:
                rname, serve = f'{title} ({size})', f'{size.replace(" oz", " fl oz")}'
            elif count:
                n = int(count.group(1))
                unit = 'dot' if 'Dot' in head or 'Dots' in title else 'roll' if 'Roll' in title else 'doughnut'
                rname = f'{title} ({n} {unit}{"s" if n > 1 else ""})' if multi else title
                serve = f'{n} {unit}{"s" if n > 1 else ""}'.replace('dots', 'doughnut dots')
            else:
                sm = re.search(r'\n\s*(\d+)\s*\n?\s*(Doughnuts?|Rolls?)\s*\n', sheet['text'])
                n = int(sm.group(1)) if sm else 1
                if 'Doughnut Dots' in title:
                    serve = f'{n} doughnut dots'
                else:
                    serve = f'{n} doughnut{"s" if n > 1 else ""}' if 'Roll' not in title else '1 roll'
                rname = title
            est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
            if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
                dropped.append(rname)
                continue
            if v.get('sat') is not None and v['sat'] > v['f']:
                dropped.append(rname)
                continue
            if rname in names:
                continue
            names.add(rname)
            items.append({
                'name': rname, 'cat': cat, 'serve': serve, 'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
                'sat': v.get('sat'), 'sugar': v.get('sugar'), 'fibre': v.get('fibre'), 'sodium': v.get('sodium'), 'salt': None,
                'contains': None, 'may': None, 'vg': None, 'meat': None,
            })

    span = f"revised {min(revised):%-d %b %Y} to {max(revised):%-d %b %Y}" if revised else 'undated'
    src = (f"Krispy Kreme per-item Nutritional & Allergen Info sheets (US), linked from each product page on krispykreme.com/menu, "
           f"{span}. Drinks are as published (lattes with 2% milk unless the name says oat milk). Allergens left out: the "
           f"sheets cover only peanuts, tree nuts, soy, milk, eggs and wheat. Left out: {', '.join(skipped)}")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-krispykreme', 'name': 'Krispy Kreme', 'how': 'Official per-item nutrition sheets (PDF)', 'url': SITE + '/menu',
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Krispy Kreme: {len(items)} items, {len(dropped)} dropped, {len(skipped)} skipped -> {OUT.name}')


if __name__ == '__main__':
    main()
