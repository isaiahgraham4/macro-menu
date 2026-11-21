#!/usr/bin/env python3
"""Del Taco (US): the Nutritional List and Allergen List PDFs linked from deltaco.com/nutrition and deltaco.com/allergens,
saved as us-deltaco-source.json.

deltaco.com/nutrition.html and allergens.html redirect (meta refresh) to the current PDFs, so a plain request finds them.
The Nutritional List gives serving weight (or fl oz for drinks), calories, fat, saturated fat, trans fat, cholesterol, sodium,
carbs, fibre, sugars and protein. The Allergen List marks the nine US majors (sesame included), gluten, and Vegetarian /
Vegan claims; items are matched to it by name.

Left out: meals (the guide gives only calorie ranges), the chicken & fries box (a bundle), bottled water, and rows whose
calories are far from 4p + 4c + 9f (more than a third out), which are counted in `src`.

Run: python3 ios/Scripts/intl/us-deltaco-fetch.py
"""
import difflib
import json
import os
import pathlib
import re
import tempfile
import urllib.parse
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-deltaco-source.json'
# The PDFs are downloads, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
SITE = 'https://deltaco.com/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
NUM_COLS = [('cal', 378), ('f', 397), ('sat', 415), ('trans', 434), ('chol', 450), ('sodium', 470), ('c', 491), ('fibre', 513),
            ('sugar', 531), ('p', 551)]
ALLERGEN_KEYS = {'Milk': ['milk'], 'Eggs': ['egg'], 'Fish': ['fish'], 'Shellfish': ['shellfish'], 'Tree Nuts': ['treenut'],
                 'Peanuts': ['peanut'], 'Wheat': ['wheat'], 'Soybeans': ['soy'], 'Sesame': ['sesame'], 'Gluten': ['gluten']}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def pdf_link(page):
    html = get(SITE + page).decode('latin-1')
    m = re.search(r'url=(files/pdf/[^"\'?]+\.pdf)', html)
    if not m:
        raise SystemExit(f'Del Taco: no PDF link on {page}')
    return urllib.parse.urljoin(SITE, m.group(1))


def num(s):
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def lines(page, step=2.5):
    out = {}
    for w in page.get_text('words'):
        out.setdefault(round((w[1] + w[3]) / 2 / step), []).append(w)
    return {k * step: sorted(v, key=lambda w: w[0]) for k, v in sorted(out.items())}


def nutrition(pdf):
    """[(section, name, serving, {col: value})]"""
    rows = []
    for page in pdf:
        ls = lines(page)
        numrows, names, labels = [], [], []
        for y, ws in ls.items():
            vals = [w for w in ws if w[0] >= 370 and re.fullmatch(r'[\d.]+', w[4])]
            if len(vals) >= 10:
                serve = ' '.join(w[4] for w in ws if 340 <= w[0] < 370)
                cols = {min(NUM_COLS, key=lambda c: abs(c[1] - w[0]))[0]: w[4] for w in vals}
                numrows.append({'y': y, 'serve': serve, 'cols': cols, 'words': []})
            for w in ws:
                if w[0] < 135:
                    labels.append((y, w[0], w[4]))
                elif 135 <= w[0] < 340:
                    names.append((y, w))
        for y, w in names:
            near = min(numrows, key=lambda r: abs(r['y'] - y), default=None)
            if near and abs(near['y'] - y) <= 6:
                near['words'].append(w)
        sec_rows = {}
        for y, x, t in labels:
            sec_rows.setdefault(y, []).append(t)
        for r in numrows:
            if not r['words']:
                continue
            name = ' '.join(w[4] for w in sorted(r['words'], key=lambda w: w[0]))
            above = [y for y in sec_rows if y <= r['y'] + 3]
            sec = ' '.join(sec_rows[max(above)]) if above else ''
            rows.append((sec, name, r['serve'], r['cols']))
    return rows


def allergens(pdf):
    """{name: (contains, vg)} from the X marks under each column."""
    out = {}
    for page in pdf:
        ls = lines(page)
        heads = {}
        for y, ws in ls.items():
            t = [w[4] for w in ws]
            if 'Vegetarian' in t and 'Sesame' in t:
                i = 0
                while i < len(ws):
                    word = ws[i][4]
                    x0, x1 = ws[i][0], ws[i][2]
                    if word == 'Tree':
                        word, x1, i = 'Tree Nuts', ws[i + 1][2], i + 1
                    heads[word] = (x0 + x1) / 2
                    i += 1
        if not heads:
            continue
        top = min(y for y, ws in ls.items() if any(w[4] == 'Vegetarian' for w in ws))
        name_lines, marks = [], []
        for y, ws in ls.items():
            if y <= top + 3:
                continue
            nm = [w for w in ws if 115 <= w[0] < 265]
            if nm:
                name_lines.append({'y': y, 'words': nm, 'x0': nm[0][0], 'marks': set()})
            marks += [(y, (w[0] + w[2]) / 2) for w in ws if w[4] == 'X' and w[0] > 265]
        # a line that starts right of the name column is the wrapped part of the name beside it
        merged = []
        for ln in name_lines:
            if ln['x0'] > 121 and merged and abs(merged[-1]['y'] - ln['y']) <= 5:
                merged[-1]['words'] += ln['words']
            elif ln['x0'] > 121 and merged is not None:
                ln['pending'] = True
                merged.append(ln)
            else:
                if merged and merged[-1].get('pending') and abs(merged[-1]['y'] - ln['y']) <= 5:
                    prev = merged.pop()
                    ln['words'] += prev['words']
                merged.append(ln)
        for y, x in marks:
            near = min(merged, key=lambda r: abs(r['y'] - y))
            if abs(near['y'] - y) <= 5:
                near['marks'].add(min(heads, key=lambda h: abs(heads[h] - x)))
        for ln in merged:
            name = ' '.join(w[4] for w in sorted(ln['words'], key=lambda w: w[0]))
            contains = sorted({k for h in ln['marks'] if h in ALLERGEN_KEYS for k in ALLERGEN_KEYS[h]})
            vg = 'vegan' if 'Vegan' in ln['marks'] else 'vegetarian' if 'Vegetarian' in ln['marks'] else None
            out[name] = (contains, vg)
    return out


# Nutritional List name -> Allergen List name, where the two lists word an item differently
ALIASES = {'Carnitas Cheddar Quesadilla': 'Carnitas Quesadilla', 'Double Del® Cheeseburger with Bacon': 'Bacon Double Del® Cheeseburger'}


def key(name):
    n = name.lower().replace('®', '').replace('™', '').replace('*', '').replace('’', "'")
    n = re.sub(r'\b(steak|pc\.?|sized|regular)\b', ' ', n)
    return re.sub(r'[^a-z0-9]+', ' ', n).strip()


def tidy(name):
    name = name.replace('®', '').replace('™', '').replace('*', '').replace('’', "'")
    name = re.sub(r'\((\d+) Pc\.\)', r'(\1 pc)', name)
    name = re.sub(r'FLAMIN\' HOT', "Flamin' Hot", name)
    name = re.sub(r'\bJACK\'D UP\b', "Jack'd Up", name)
    name = re.sub(r'\((Large|Regular|Small)\)', lambda m: f'({m.group(1).lower()})', name)
    name = name.replace('(Regular-sized)', '(regular)').replace('Gold Peak Real Brewed Tea - Sweet Tea', 'Gold Peak Sweet Tea')
    name = name.replace('Gold Peak Real Brewed Tea - Unsweetened', 'Gold Peak Unsweetened Tea')
    name = re.sub(r'CHEETOS Flamin\' Hot Crunchy Cheese Flavored Snacks \(2 oz Bag\)', "Cheetos Flamin' Hot (2 oz bag)", name)
    return re.sub(r'\s+', ' ', name).strip()


def category(sec, name, serve):
    n = name.lower()
    if 'fl oz' in serve:
        return 'drink'
    if 'shake' in n:
        return 'drink'
    if sec.startswith('DESSERTS'):
        return 'sweet'
    if sec.startswith('SAUCE'):
        return 'extra'
    if sec.startswith('BREAKFAST'):
        return 'side' if 'hashbrown' in n else 'sweet' if 'donut' in n else 'breakfast'
    if sec.startswith('SIDES') or ('fries' in n and 'loaded' not in n and 'chili' not in n and 'carne' not in n
                                   and 'carnitas' not in n):
        return 'side'
    return 'main'


def meat(name):
    n = name.lower()
    out = []
    for word, m in (('beef', 'beef'), ('carne asada', 'beef'), ('burger', 'beef'), ('cheeseburger', 'beef'), ('chili', 'beef'),
                    ('chicken', 'chicken'), ('carnitas', 'pork'), ('bacon', 'pork'), ('fish', 'fish')):
        if word in n and m not in out:
            out.append(m)
    if re.search(r'\bthe del taco\b|\bsnack taco\b|del combo|del beef', n) and 'beef' not in out:
        out.append('beef')
    return out or None


def main():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    nut_url, all_url = pdf_link('nutrition.html'), pdf_link('allergens.html')
    (PDF_DIR / 'us-deltaco.pdf').write_bytes(get(nut_url))
    (PDF_DIR / 'us-deltaco-allergens.pdf').write_bytes(get(all_url))
    nut_pdf = pymupdf.open(PDF_DIR / 'us-deltaco.pdf')
    edition = re.search(r'\(([A-Za-z]+ \d{4})\)', nut_pdf[0].get_text()).group(1)
    rows = nutrition(nut_pdf)
    algs = allergens(pymupdf.open(PDF_DIR / 'us-deltaco-allergens.pdf'))
    akeys = {key(n): v for n, v in algs.items()}

    def lookup(name):
        base = re.sub(r'\s*\((Large|Regular|Small)\)$', '', name)
        base = ALIASES.get(base, base)
        base = re.sub(r'^(Large|Mini) Shake', 'Shake', base)
        base = re.sub(r'^(.*?) (?:Hot )?Sauce Packet$', r'\1 Sauce', base).replace('Ketchup Packet', 'Ketchup')
        for cand in (name, base, f'Fountain Drink ({base})'):
            if key(cand) in akeys:
                return akeys[key(cand)]
        m = difflib.get_close_matches(key(base), list(akeys), n=1, cutoff=0.88)
        return akeys[m[0]] if m else (None, None)

    items, dropped, unmatched = [], [], []
    for sec, raw, serve, cols in rows:
        if re.search(r'\bMeal\b|\bBox\b|Bottled Water', raw):
            continue
        v = {k: num(cols.get(k, '')) for k, _ in NUM_COLS}
        if v['cal'] is None or any(v[k] is None for k in ('p', 'c', 'f')):
            continue
        name = tidy(raw)
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
            dropped.append(name)
            continue
        contains, vg = lookup(raw)
        if contains is None:
            unmatched.append(name)
        g = re.fullmatch(r'([\d.]+)g', serve.replace(' ', ''))
        serving = f'1 serving ({g.group(1)} g)' if g else (serve.replace('fl oz', 'fl oz').strip() or '1 serving')
        if 'fl oz' in serve:
            size = re.search(r'\((large|regular)\)$', name)
            serving = f"{size.group(1) if size else '1 serving'} ({serve})"
        items.append({
            'name': name, 'cat': category(sec, name, serve), 'serve': serving, 'cal': v['cal'], 'kj': None,
            'p': v['p'], 'c': v['c'], 'f': v['f'], 'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'],
            'sodium': v['sodium'], 'salt': None, 'contains': contains, 'may': None, 'vg': vg, 'meat': meat(name),
        })

    src = (f"Del Taco Menu Items Nutritional List and Allergen List ({edition}). Allergens and Vegetarian/Vegan are the Allergen "
           f"List's marks, matched to each item by name. Left out: meals (calorie ranges only), the chicken & fries box and "
           f"bottled water")
    if unmatched:
        src += f"; {len(unmatched)} item(s) not on the Allergen List have no allergens ({', '.join(unmatched)})"
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-deltaco', 'name': 'Del Taco', 'how': 'Official nutrition and allergen lists (PDF)',
        'url': 'https://deltaco.com/nutrition', 'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal',
        'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Del Taco: {len(items)} items, {len(dropped)} dropped, {len(unmatched)} without allergens -> {OUT.name}')


if __name__ == '__main__':
    main()
