#!/usr/bin/env python3
"""St Pierre's Sushi (New Zealand): downloads the Nutrition Chart PDF linked from stpierres.co.nz/nutrition (the page's
Nuxt state names the file) and writes nz-stpierres-source.json beside this file.

Each table row holds 15 figures: per 100 g (kJ, protein, fat, sat fat, carbs, sugars, sodium), the serving size in grams,
then the same seven per serving. Names and portions ("8 pcs", "Small") sit in the left column and are matched to the
nearest row by position. Sushi servings include the condiments St Pierre's packs with them (the chart says so).

Left out: sharing platters (20 pieces or more) and combo deals. Allergens are left out: St Pierre's allergen chart has no
peanut or tree nut column.

Run: python3 ios/Scripts/intl/nz-stpierres-fetch.py
"""
import json
import tempfile
import os
import pathlib
import re
import time
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'spnz'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
PAGE = 'https://stpierres.co.nz/nutrition'
NUM = re.compile(r'^\d+(\.\d+)?$')
PORTION = re.compile(r'^(\d+ ?pcs?|Small|Medium|Large)$', re.I)


def fetch(url):
    time.sleep(0.3)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': '*/*'}), timeout=60) as r:
        return r.read()


def pdf_url():
    html = fetch(PAGE).decode('utf-8', 'replace')
    file_id = re.search(r'file1_title:"NUTRITION CHART",file1:"([0-9a-f-]{36})"', html).group(1)
    return f'https://stpierres.co.nz/cms/assets/{file_id}'


def rows_of(page):
    ls = []
    for b in page.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ' '.join(s['text'] for s in l['spans']).strip()
            if t:
                ls.append((l['bbox'][1], l['bbox'][0], t))
    nums = sorted((y, x, t) for y, x, t in ls if NUM.match(t))
    rows = []
    for y, x, t in nums:
        if rows and y - rows[-1]['y'] < 3:
            rows[-1]['cells'].append((x, t))
        else:
            rows.append({'y': y, 'cells': [(x, t)], 'names': [], 'portion': None})
    rows = [r for r in rows if len(r['cells']) == 15]
    if not rows:
        return []
    entries = []   # a name, and the portion printed on the line under it
    for y, x, t in sorted((y, x, t) for y, x, t in ls if x < 200 and not NUM.match(t) and y > 150):
        last = entries[-1] if entries else None
        if PORTION.match(t) and last and y - last['y1'] < 12 and last['portion'] is None:
            last['portion'], last['y1'] = t, y
        elif last and last['portion'] is None and last['names'][-1].endswith(('/', '-')):
            last['names'].append(t)
            last['y1'] = y
        else:
            entries.append({'y0': y, 'y1': y, 'names': [t], 'portion': None})
    for r in rows:
        near = min(entries, key=lambda e: abs((e['y0'] + e['y1']) / 2 - r['y'])) if entries else None
        if near and abs((near['y0'] + near['y1']) / 2 - r['y']) < 16:
            r['names'] = [(near['y0'], ' '.join(near['names']))]
            r['portion'] = near['portion']
    out = []
    for r in rows:
        v = [float(t) for x, t in sorted(r['cells'])]
        name = ' '.join(t for y, t in sorted(r['names']))
        out.append({'name': name, 'portion': r['portion'], 'v': v})
    return out


def tidy(name, portion):
    name = re.sub(r'\s+', ' ', name).strip()
    name = re.sub(r' ss katsu$', '', name)
    name = re.sub(r' SOD$', '', name)
    name = name.replace('Tempura Vegetable sushi', 'Tempura Vegetable Sushi').replace('with Mayo ', 'with Mayonnaise ')
    name = re.sub(r'with Mayo$', 'with Mayonnaise', name)
    m = re.match(r'^(.*) \((\d+)pc\)$', name)
    if m:
        name, portion = m.group(1), f'{m.group(2)} pcs'
    if portion:
        p = portion.lower().replace('pcs', ' pcs').replace('  ', ' ').replace('1 pc', '1 piece')
        p = re.sub(r'(\d+)\s*pcs', r'\1 pieces', p)
        name = f'{name} ({p})'
    return name


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    path = PDFS / 'stpierres-nutrition.pdf'
    path.write_bytes(fetch(pdf_url()))
    doc = pymupdf.open(path)
    revised = re.search(r'([A-Z][a-z]{2} 20\d\d)', doc[0].get_text())
    items, dropped, skipped, seen = [], [], [], set()
    for page in doc:
        for r in rows_of(page):
            per100 = r['v'][:7]
            g, kj, p, f, sat, c, sugar, na = r['v'][7:]
            pieces = re.match(r'(\d+)', r['portion'] or '')
            if (pieces and int(pieces.group(1)) >= 20) or 'Combo' in r['name'] or 'Platter' in r['name'] or ' and Double' in r['name']:
                skipped.append(r['name'])
                continue
            name = tidy(r['name'], r['portion'])
            if not r['name'] or name in seen:
                continue
            seen.add(name)
            cal = kj / 4.184
            off_100 = any(abs(per100[i] * g / 100 - v) > max(3, 0.15 * v) for i, v in ((0, kj), (1, p), (2, f), (4, c)))
            if (cal > 20 and abs(4 * p + 4 * c + 9 * f - cal) > cal / 3) or off_100:
                dropped.append(name)
                continue
            low = name.lower()
            cat = ('extra' if low.startswith(('soy sauce', 'japanese mayonnaise', 'wasabi')) or low == 'ginger'
                   else 'sweet' if 'mochi' in low else 'side' if any(w in low for w in ('edamame', 'miso', 'salad', 'nuggets', 'cocktail', 'spring roll', 'inari ('))
                   else 'main')
            meat = None
            if cat in ('main', 'side') and 'vegan' not in low and 'vegetarian' not in low:
                meat = [m for w, m in (('chicken', 'chicken'), ('salmon', 'fish'), ('tuna', 'fish'), ('prawn', 'seafood'), ('shrimp', 'seafood'),
                                       ('seafood', 'seafood'), ('crab', 'seafood'), ('california', 'seafood')) if w in low]
                meat = list(dict.fromkeys(meat)) or None
            num = lambda x: int(x) if x == int(x) else x
            items.append({
                'name': name, 'cat': cat, 'serve': f'1 serving ({num(g)} g)', 'cal': None, 'kj': round(kj),
                'p': num(p), 'c': num(c), 'f': num(f), 'sat': num(sat), 'sugar': num(sugar), 'fibre': None,
                'sodium': num(na), 'salt': None, 'contains': None, 'may': None,
                'vg': 'vegan' if low.startswith('vegan') else None, 'meat': meat,
            })
    src = ("St Pierre's Sushi Nutrition Information (PDF, CIS008" + (f', {revised.group(1)}' if revised else '') + '), linked from '
           'stpierres.co.nz/nutrition. Sushi servings include the condiments packed with them. '
           f'Left out: {len(skipped)} sharing platters and combo deals'
           + (f', and {len(dropped)} rows whose figures do not add up ({"; ".join(dropped)})' if dropped else '')
           + ". No allergens: St Pierre's allergen chart has no peanut or tree nut column.")
    out = {'chain': 'nz-stpierres', 'name': "St Pierre's Sushi", 'how': 'Official nutrition chart (PDF)', 'url': PAGE,
           'src': src, 'checked': date.today().isoformat(), 'energy': 'kj', 'halal': False, 'items': items}
    (HERE / 'nz-stpierres-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'nz-stpierres: {len(items)} items, skipped {len(skipped)}, dropped {dropped}')


if __name__ == '__main__':
    main()
