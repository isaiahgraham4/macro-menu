#!/usr/bin/env python3
"""Jimmy John's (US): the Nutrition & Allergen Guide that jimmyjohns.com links in its footer, saved as us-jimmyjohns-source.json.

jimmyjohns.com's footer links "Nutrition & Allergen Guide" to restaurant.nutritionix.com/jimmy-johns/landing, an interactive
nutrition menu that Nutritionix hosts for the chain. That page loads its whole menu from one public data file
(nix-vue-inm.s3.amazonaws.com/restaurant/jimmy-johns/data/menu-latest.json.gz, no key) plus settings.json, whose
"menuLastUpdated" is the edition date. Each item carries its nutrition (summed from its standard build) and allergen flags for
the nine US majors, sesame included, which the guide shows as Contains; there is no may-contain list.

The data file holds unrounded figures; the guide shows them rounded the FDA way (settings "useFdaRounding"), so this script
applies the same rounding (calories to 10, fat to 0.5 g / 1 g, sodium to 5 / 10 mg, other grams to 1 g; "<1 g" is saved as 1).

Left out: the guide's Preview category (items it flags as preview only, not on the menu), the three drink rows (fountain and
bottled drinks have no figures), items in no menu category (old or test items still in the data file), and rows whose
calories are more than a third away from 4p + 4c + 9f, which are counted in `src`.

Run: python3 ios/Scripts/intl/us-jimmyjohns-fetch.py
"""
import gzip
import html
import json
import pathlib
import re
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-jimmyjohns-source.json'
SITE = 'https://www.jimmyjohns.com/'
GUIDE = 'https://restaurant.nutritionix.com/jimmy-johns/landing'
DATA = 'https://nix-vue-inm.s3.amazonaws.com/restaurant/jimmy-johns/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

ALLERGENS = {'gluten': ['gluten'], 'wheat': ['wheat'], 'milk': ['milk'], 'eggs': ['egg'], 'soy': ['soy'], 'sesame': ['sesame'],
             'peanuts': ['peanut'], 'treeNuts': ['treenut'], 'fish': ['fish'], 'shellfish': ['shellfish']}
MEATS = [('ham', 'pork'), ('capocollo', 'pork'), ('salami', 'pork'), ('bacon', 'pork'), ('pork', 'pork'), ('turkey', 'turkey'),
         ('roast beef', 'beef'), ('sirloin', 'beef'), ('prime rib', 'beef'), ('gyro meat', 'lamb'), ('chicken', 'chicken'),
         ('tuna', 'fish')]


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def site_links_guide():
    """The guide must still be the one jimmyjohns.com links: its address is in the site's main script."""
    page = get(SITE).decode('utf-8', 'replace')
    m = re.search(r'src="(/assets/index-[^"]+\.js)"', page)
    if not m or 'restaurant.nutritionix.com/jimmy-johns' not in get(SITE.rstrip('/') + m.group(1)).decode('utf-8', 'replace'):
        raise SystemExit("Jimmy John's: jimmyjohns.com no longer links the Nutritionix guide; check the site's footer")


def step(v, s):
    return int(round(v / s) * s) if s >= 1 else round(round(v / s) * s, 1)


def fda(key, v):
    """FDA label rounding, as the guide shows it."""
    if v is None:
        return None
    if key == 'cal':
        return 0 if v < 5 else step(v, 5) if v <= 50 else step(v, 10)
    if key in ('f', 'sat'):
        r = 0 if v < 0.5 else step(v, 0.5) if v < 5 else step(v, 1)
        return int(r) if r == int(r) else r
    if key == 'sodium':
        return 0 if v < 5 else step(v, 5) if v <= 140 else step(v, 10)
    return 0 if v < 0.5 else 1 if v < 1 else step(v, 1)          # carbs, fibre, sugar, protein


def tidy(name):
    name = html.unescape(name).replace('®', '').replace('™', '').replace('’', "'")
    name = re.sub(r'(\S)\(', r'\1 (', name)
    name = re.sub(r'\(Little John - ([\d.]+")\)', r'(Little John, \1)', name)
    name = re.sub(r', (Small|Large)$', lambda m: f' ({m.group(1).lower()})', name)
    return re.sub(r'\s+', ' ', name).strip()


def category(name, section):
    n = name.lower()
    if section == 'Dessert' or re.search(r'cookie|brownie', n):
        return 'sweet'
    if re.search(r'ranch|spread', n) and section == 'Sides & Sauces':
        return 'extra'
    if section == 'Sides & Sauces' or 'chips' in n:
        return 'side'
    return 'main'


def meat(name, parts):
    text = ' '.join([name] + parts).lower()
    out = []
    for word, m in MEATS:
        if re.search(r'\b' + word, text) and m not in out:
            out.append(m)
    return out or None


def main():
    site_links_guide()
    settings = json.loads(get(DATA + 'settings.json'))
    data = json.loads(gzip.decompress(get(DATA + 'data/menu-latest.json.gz')))
    edition = settings['menuLastUpdated'][:10]
    modname = {m['id']: html.unescape(m['name']) for m in data['modifiers']}
    for g in data['groups']:
        for m in g.get('modifiers', []):
            if isinstance(m, dict) and 'id' in m and 'name' in m:
                modname.setdefault(m['id'], html.unescape(m['name']))
    byid = {i['id']: i for i in data['items']}

    items, dropped, seen = [], [], set()
    for cat in data['categories']:
        if cat.get('previewOnly') or cat['name'] == 'Drinks':
            continue
        for iid in cat['items']:
            it = byid.get(iid)
            if not it or not it.get('isActive') or it.get('zeroNutrition'):
                continue
            n = it['nutrition']
            val = lambda k: n.get('calculated' + k[0].upper() + k[1:]) if n.get('calculated' + k[0].upper() + k[1:]) is not None else n.get(k)
            raw = {'cal': val('calories'), 'p': val('protein'), 'c': val('totalCarb'), 'f': val('totalFat'), 'sat': val('saturatedFat'),
                   'sugar': val('sugars'), 'fibre': val('fiber'), 'sodium': val('sodium')}
            v = {k: fda(k, x) for k, x in raw.items()}
            name = tidy(it['name'])
            if name in seen or not v['cal']:
                continue
            seen.add(name)
            est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
            if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
                dropped.append(name)
                continue
            if v['sat'] is not None and v['sat'] > v['f']:
                dropped.append(name)
                continue
            al = it.get('allergens') or {}
            known = all(al.get(k, {}).get('presence', -1) in (0, 1) for k in ALLERGENS)
            contains = sorted({a for k, keys in ALLERGENS.items() if al.get(k, {}).get('presence') == 1 for a in keys}) if known else None
            unit = html.unescape(it.get('servingUnitName') or 'serving').lower()
            g = n.get('calculatedServingWeight') or n.get('servingWeight')
            serve = f'1 {unit}' + (f' ({round(g)} g)' if g else '')
            parts = [modname.get(dm['id'], '') for dm in it.get('defaultModifiers', [])]
            items.append({
                'name': name, 'cat': category(name, cat['name']), 'serve': serve,
                'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
                'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None,
                'contains': contains, 'may': None, 'vg': None, 'meat': meat(name, parts),
            })

    src = (f"Jimmy John's Nutrition & Allergen Guide (US), the Nutritionix-hosted guide jimmyjohns.com links, menu last updated "
           f"{edition}. Figures are the guide's per-item values with FDA label rounding; allergens are its Contains flags for the nine "
           f"US majors (no may-contain list is published). Left out: Preview items, fountain and bottled drinks (no figures) and items "
           f"in no menu category")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-jimmyjohns', 'name': "Jimmy John's", 'how': 'Official nutrition and allergen guide (Nutritionix data)',
        'url': GUIDE, 'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"Jimmy John's: {len(items)} items, {len(dropped)} dropped -> {OUT.name}")


if __name__ == '__main__':
    main()
