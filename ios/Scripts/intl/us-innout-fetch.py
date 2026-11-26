#!/usr/bin/env python3
"""In-N-Out Burger (US): the Nutrition Facts PDF that in-n-out.com publishes for download, saved as us-innout-source.json.

in-n-out.com's pages sit behind a bot check (Incapsula) that refuses plain requests from outside the US, but the guide itself is
a document published for download at a fixed address (/docs/default-source/downloads/nutrition_info.pdf), which a plain
request can fetch. The guide gives each burger (with onion, with mustard & ketchup instead of spread, and Protein Style),
fries, shakes and hot drinks with serving weight, calories, calories from fat, fat, saturated fat, trans fat, cholesterol,
sodium, carbs, fibre, sugars and protein; fountain drinks have calories, fat, sodium, carbs, sugars and protein for each cup
size with and without ice (the guide says the missing figures are 0 for drinks).

Kept: every burger, fries, shake and hot drink, and each fountain drink per cup size as served (with ice).
Left out: the without-ice drink figures (the same cup filled with no ice), and rows whose calories are far from
4p + 4c + 9f (more than a third out), which are counted in `src`. Allergens aren't in the guide (it points to the
in-n-out.com/nutrition page, which we can't reach from here), so contains/may are null for every item.

Run: python3 ios/Scripts/intl/us-innout-fetch.py
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
OUT = HERE / 'us-innout-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
PAGE = 'https://www.in-n-out.com/nutrition'
PDF = 'https://www.in-n-out.com/docs/default-source/downloads/nutrition_info.pdf'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
FOOD = ['g', 'cal', 'calfat', 'f', 'sat', 'trans', 'chol', 'sodium', 'c', 'fibre', 'sugar', 'p']
DRINK = ['oz', 'cal', 'f', 'sodium', 'c', 'sugar', 'p']
SIZES = {'Sm': 'small', 'Med': 'medium', 'Lg': 'large', 'X-Lg': 'extra large'}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    s = s.strip().replace('<1', '0.5')
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def is_num(s):
    return num(s) is not None or re.fullmatch(r'\d+oz\.', s.strip()) is not None


def tidy(name):
    return re.sub(r'\s+', ' ', name.replace('®', '').replace('’', "'").replace('*', '')).strip()


def main():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'us-innout.pdf'
    path.write_bytes(get(PDF))
    page = pymupdf.open(path)[0]
    text = page.get_text()
    edition = re.search(r'\n((?:January|February|March|April|May|June|July|August|September|October|November|December) \d{4})\n', text)
    edition = edition.group(1) if edition else 'current'
    lines = [l.strip() for l in text.split('\n') if l.strip()]

    rows, dropped = [], []
    # Food: a name line, then 12 figures (shakes and hot drinks give fluid ounces in place of grams)
    base = None
    i = lines.index('Protein (g)') + 1
    while i < len(lines) and 'Nutrition Facts' not in lines[i]:
        name = lines[i]
        vals = lines[i + 1:i + 13]
        if len(vals) < 12 or not all(is_num(v) for v in vals):
            i += 1
            continue
        i += 13
        v = {k: (vals[n] if k == 'g' else num(vals[n])) for n, k in enumerate(FOOD)}
        n = tidy(name)
        if re.match(r'with mustard', n):
            n, note = f'{base} (mustard & ketchup instead of spread)', 'with onion'
        elif n.startswith('Protein Style'):
            n, note = f'{base}, Protein Style', 'bun replaced with lettuce, with onion'
        elif n.startswith('with Marshmallows'):
            n, note = f'{base} with Marshmallows', None
        else:
            note = 'with onion' if 'w/Onion' in n else None
            n = base = n.replace(' w/Onion', '')
        oz = re.fullmatch(r'(\d+)oz\.', v['g'])
        if oz:
            serve = f'{oz.group(1)} oz'
        else:
            serve = f"1 serving ({v['g']} g)" + (f', {note}' if note else '')
        rows.append((n, serve, v))

    # Fountain drinks: a name line, then per size: label, with-ice cup (oz + 6 figures), without-ice cup (oz + 6 figures)
    i = len(lines) - 1 - lines[::-1].index('Protein (g)') + 1
    name = None
    while i < len(lines):
        l = lines[i]
        if l in SIZES and name:
            with_ice = lines[i + 1:i + 8]
            v = {k: (with_ice[n] if k == 'oz' else num(with_ice[n])) for n, k in enumerate(DRINK)}
            v.update(sat=0, fibre=0)
            oz = with_ice[0].replace('oz.', '')
            rows.append((f'{name} ({SIZES[l]})', f'{SIZES[l]} ({oz} oz with ice)', v))
            i += 15
            continue
        if not is_num(l) and l not in ('With Ice', 'Without Ice'):
            name = tidy(l)
        i += 1

    items = []
    for name, serve, v in rows:
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
            dropped.append(name)
            continue
        n = name.lower()
        if re.search(r'shake|coffee|cocoa|milk|coke|cola|7up|pepper|root beer|lemonade|\btea\b', n):
            cat = 'drink'
        elif 'fries' in n:
            cat = 'side'
        else:
            cat = 'main'
        items.append({
            'name': name, 'cat': cat, 'serve': serve,
            'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
            'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None,
            'contains': None, 'may': None, 'vg': None, 'meat': ['beef'] if cat == 'main' else None,
        })

    src = (f"In-N-Out Burger Nutrition Facts (PDF), {edition} edition. Fountain drinks are the with-ice figures for each cup; "
           f"the guide gives the drinks' missing figures (saturated fat, fibre) as 0. No allergens: the guide points to "
           f"in-n-out.com/nutrition for those. Left out: the without-ice drink figures")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-innout', 'name': 'In-N-Out Burger', 'how': 'Official nutrition facts (PDF)', 'url': PAGE,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'In-N-Out: {len(items)} items, {len(dropped)} dropped -> {OUT.name}')


if __name__ == '__main__':
    main()
