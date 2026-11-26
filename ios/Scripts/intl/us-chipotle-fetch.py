#!/usr/bin/env python3
"""Chipotle (US): the "Full Nutrition Facts" PDF that chipotle.com's nutrition calculator links, saved as us-chipotle-source.json.

chipotle.com/nutrition-calculator's "Full Nutrition Facts" button opens a PDF whose address the page reads from a public
content fragment (chipotle.com/graphql/execute.json/chipotle/nutrition-facts;region=en-us; no key), so a plain request finds
the current edition. (The calculator's own menu feed needs a key embedded in the web app, so it is not used.)
The PDF is the paper menu: page 1 is the menu board (calorie ranges only), page 2 the nutrition chart for restaurants
pouring Coca-Cola drinks (code ...-US-CK) and page 3 the same chart for Pepsi restaurants (...-US-PPS). Each row gives the
portion, calories, calories from fat, fat, saturated fat, trans fat, cholesterol, sodium, carbs, fibre, sugar and protein.

Chipotle is build-your-own and publishes no figures for whole burritos or bowls, so every ingredient is an "extra" row with
Chipotle's standard portion (the app adds them up); chips, large guacamole and queso sides are "side" rows, and drinks are one
row per cup size, from both charts (drinks on both are kept once). "<1 g" is saved as 1.

Left out: the Kid's Menu (smaller kids' portions of the same ingredients, sold as kids' meals), page 1's calorie-only menu
board, and rows whose figures can't be read or whose calories are more than a third away from 4p + 4c + 9f (counted in `src`).
No allergens: the PDF has none (chipotle.com/allergens is a separate filter page).

Run: python3 ios/Scripts/intl/us-chipotle-fetch.py
"""
import json
import os
import pathlib
import re
import tempfile
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-chipotle-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
PAGE = 'https://www.chipotle.com/nutrition-calculator'
FRAGMENT = 'https://www.chipotle.com/graphql/execute.json/chipotle/nutrition-facts;region=en-us;'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
KEYS = ['cal', 'calfat', 'f', 'sat', 'trans', 'chol', 'sodium', 'c', 'fibre', 'sugar', 'p']
PORTION = re.compile(r'^(\d+(?:\.\d+)?)\s*(fl oz|oz|ea)$')
SIDES = {'Chips (regular)', 'Chips (large)', 'Guacamole (large)', 'Queso Blanco (side)', 'Queso Blanco (large)'}
NAMES = {'Queso Blanco (entreé)': 'Queso Blanco (entrée)', 'Guacamole (topping/side)': 'Guacamole',
         'Fajita Vegetables': 'Fajita Veggies', 'Coca Cola Life': 'Coca-Cola Life'}
MEATS = {'Barbacoa': ['beef'], 'Steak': ['beef'], 'Chicken': ['chicken'], 'Carnitas': ['pork']}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    s = s.replace('<', '').replace(' ', '')
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def chart(page):
    """[(name, portion, {key: value or None})] for the adult part of one chart page."""
    lines = [l.strip() for l in page.get_text().split('\n') if l.strip()]
    start = lines.index('Protein (g)') + 1
    end = next(i for i, l in enumerate(lines) if l.lower() == 'kids menu')
    lines = lines[start:end]
    rows, name, i = [], None, 0
    while i < len(lines):
        m = PORTION.match(lines[i])
        if m and i + 11 < len(lines) + 0 and name:
            vals = lines[i + 1:i + 12]
            rows.append((name, f'{m.group(1)} {m.group(2)}', dict(zip(KEYS, (num(v) for v in vals))), vals))
            i += 12
            continue
        name = lines[i]
        i += 1
    return rows


def main():
    frag = json.loads(get(FRAGMENT))
    path = frag['data']['nutritionFactsList']['items'][0]['nutritionFactsSheetReference']['_path']
    pdf_url = 'https://www.chipotle.com' + path
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    pdf_path = PDF_DIR / 'us-chipotle.pdf'
    pdf_path.write_bytes(get(pdf_url))
    pdf = pymupdf.open(pdf_path)
    codes = re.findall(r'[A-Z]{3}-\d{4}-US-[A-Z]+', ''.join(p.get_text() for p in pdf))

    items, dropped, unread, seen = [], [], [], set()
    for page in pdf:
        if 'Protein (g)' not in page.get_text():
            continue
        for raw, portion, v, texts in chart(page):
            raw = re.sub(r'\s+', ' ', raw)
            is_drink = portion.endswith('fl oz') and int(float(portion.split()[0])) in (22, 32)
            base = NAMES.get(raw, raw)
            name = f'{base} ({portion})' if is_drink else base
            if name in seen:
                continue
            if any(v[k] is None for k in KEYS):
                unread.append(name)
                continue
            seen.add(name)
            est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
            if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15 or v['sat'] > v['f']:
                dropped.append(name)
                continue
            cat = 'drink' if is_drink else 'side' if raw in SIDES else 'extra'
            serve = f'{portion} cup' if is_drink else '1 tortilla' if portion == '1 ea' else portion
            items.append({
                'name': name, 'cat': cat, 'serve': serve,
                'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
                'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None,
                'contains': None, 'may': None, 'vg': None, 'meat': MEATS.get(base),
            })

    edition = re.sub(r'.*Paper-Menu-?', '', path).replace('.pdf', '').replace('-', '/') or path.rsplit('/', 1)[-1]
    src = (f"Chipotle US Nutrition Facts (paper menu PDF linked from chipotle.com's nutrition calculator, file dated {edition}; "
           f"chart codes {', '.join(sorted(set(codes)))}). Chipotle publishes figures per ingredient, not per burrito or bowl, so "
           f"ingredients are extras at Chipotle's standard portions; drinks come from both the Coca-Cola and Pepsi charts. No "
           f"allergens in the PDF. Left out: the Kid's Menu portions and the calorie-only menu board")
    if unread:
        src += f"; {len(unread)} row(s) with an unreadable figure ({', '.join(unread)})"
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-chipotle', 'name': 'Chipotle', 'how': 'Official nutrition facts (PDF)', 'url': PAGE,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Chipotle: {len(items)} items, {len(dropped)} dropped, {len(unread)} unreadable -> {OUT.name}')


if __name__ == '__main__':
    main()
