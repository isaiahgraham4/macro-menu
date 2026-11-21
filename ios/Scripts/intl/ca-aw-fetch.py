#!/usr/bin/env python3
"""A&W Canada: fetches the menu feed web.aw.ca loads (/api/menu/ for the item list, /api/menu/<slug> for each item's
nutrition and allergen table) and writes ca-aw-source.json beside this file.

Every size or variant A&W lists under an item's "options" is fetched as its own row. Allergens come from the per-component
table on each item page: P = contains, M = may contain (peanuts, tree nuts, sesame, milk, wheat, soy, eggs, fish,
shellfish, sulphites; mustard has no key here and is ignored).

Run: python3 ios/Scripts/intl/ca-aw-fetch.py
"""
import json
import pathlib
import re
import time
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
BASE = 'https://web.aw.ca/api/menu/'

ALLERGENS = {'peanuts': ['peanut'], 'treenuts': ['treenut'], 'sesame': ['sesame'], 'milk': ['milk'], 'wheat': ['gluten', 'wheat'],
             'soy': ['soy'], 'eggs': ['egg'], 'fish': ['fish'], 'shellfish': ['shellfish'], 'sulphites': ['sulphites']}
ORDER = ['gluten', 'wheat', 'milk', 'egg', 'soy', 'sesame', 'peanut', 'treenut', 'fish', 'shellfish', 'lupin', 'sulphites']
EXTRA = {'chipotle-mayonnaise', 'gravy', 'dipping-sauce', 'kraft-table-spreads'}
SWEET = {'apple-turnover', 'root-beer-lollipops'}
CAT = {'Breakfast': 'breakfast', 'Burgers': 'main', 'Chicken': 'main', 'Value': 'main', 'Kidspack': 'main', 'Featured': 'main',
       'Cold Drinks': 'drink', 'Hot Drinks': 'drink', 'Sides': 'side'}


def get(path):
    time.sleep(0.25)
    req = urllib.request.Request(BASE + path, headers={'User-Agent': UA, 'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode('utf-8'))


def num(v):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return int(x) if x == int(x) else x


def clean(name):
    name = re.sub(r'[™®]', '', name).replace('Jalapeo', 'Jalapeño').replace('diet Coke', 'Diet Coke')
    name = re.sub(r'\s+', ' ', name).strip()
    m = re.match(r'^(.*) \(([^()]*)\)$', name)
    if m:   # sizes in brackets, lower case: "Latte (Small - 2% Milk)" -> "Latte (small, 2% milk)"
        base, inner = m.groups()
        if re.match(r"(?i)^(small|regular|large|single|double|kid's size|\d+ ?oz|\d+ ?pc|each|\d+|zero sugar)\b", inner):
            inner = inner.replace(' - ', ', ').lower().replace("kid's", "kids'")
            inner = re.sub(r'^(\d+)oz$', r'\1 oz', inner)
            inner = re.sub(r'^(\d+)pc$', r'\1 pieces', inner)
            inner = {'each': '1 piece'}.get(inner, inner)
            if re.match(r'^\d+$', inner):
                inner += ' pieces'
            name = f'{base} ({inner})'
    return {'Teas': 'Tea'}.get(name, name)


def kids(name):
    """Kids' packs list each part of the meal as an option: keep the main, and the apple slices / milk once."""
    m = re.match(r"^(Kids' .*?) \((.*)\)$", name)
    if not m:
        return name
    base, part = m.groups()
    if part in ('Apple Slices', 'MadeGood Bar', 'Milk2Go'):
        return part
    n = re.match(r'^Chicken Strips - (\d+)$', part)
    return f'{base} ({n.group(1)} pieces)' if n else base


def meat_of(d):
    names = ' '.join(c['en']['name'] for c in d.get('components') or []).lower()
    out = []
    for word, m in [('beef', 'beef'), ('chicken', 'chicken'), ('bacon', 'pork'), ('sausage', 'pork'), ('ham ', 'pork'),
                    ('pork', 'pork'), ('fish', 'fish'), ('pollock', 'fish'), ('cod', 'fish')]:
        if word in names and m not in out and 'plant' not in names:
            out.append(m)
    return out or None


def allergens(d):
    contains, may = set(), set()
    n = 1
    while f'allergen{n}' in d or f'sesame{n}' in d:
        for k, keys in ALLERGENS.items():
            v = (d.get(f'{k}{n}') or '').strip().upper()
            if v == 'P':
                contains.update(keys)
            elif v == 'M':
                may.update(keys)
        n += 1
    return [a for a in ORDER if a in contains], [a for a in ORDER if a in may and a not in contains]


def main():
    menu = get('')
    seen, done, items, dropped = set(), set(), [], []
    for section, block in menu.items():
        for entry in block['items']:
            top = entry['slug']
            if top in seen:
                continue
            seen.add(top)
            d = get(top)
            slugs = [o['slug'] for o in d.get('options') or []] or [top]
            for s in slugs:
                if s in seen and s != top:
                    continue
                seen.add(s)
                x = d if s == top else get(s)
                cal, p, c, f = (num(x.get(k)) for k in ('calories', 'protein', 'carbohydrates', 'fat'))
                name = clean(x['item'])
                if section == 'Kidspack':
                    name = kids(name)
                    if name in done:
                        continue
                done.add(name)
                zero_drink = cal == 0 and section in ('Cold Drinks', 'Hot Drinks') and num(x.get('servingsize'))
                if (not cal and not zero_drink) or p is None or c is None or f is None:
                    dropped.append(f'{name} (no figures)')
                    continue
                if abs(4 * p + 4 * c + 9 * f - cal) > cal / 3 and cal > 30:
                    dropped.append(f'{name} (energy does not add up)')
                    continue
                cat = CAT.get(section, 'main')
                if name == 'Apple Slices':
                    cat = 'side'
                elif name == 'MadeGood Bar':
                    cat = 'sweet'
                elif name == 'Milk2Go':
                    cat = 'drink'
                if top in EXTRA:
                    cat = 'extra'
                elif top in SWEET:
                    cat = 'sweet'
                elif 'float' in top:
                    cat = 'drink'
                ml = section in ('Cold Drinks', 'Hot Drinks') or 'float' in top or name == 'Milk2Go'
                g = num(x.get('servingsize'))
                contains, may = allergens(x)
                items.append({
                    'name': name, 'cat': cat, 'serve': f'1 serving ({g} {"ml" if ml else "g"})' if g else '1 serving',
                    'cal': cal, 'kj': None, 'p': p, 'c': c, 'f': f,
                    'sat': num(x.get('satfat')), 'sugar': num(x.get('sugar')), 'fibre': num(x.get('fibre')),
                    'sodium': num(x.get('sodium')), 'salt': None,
                    'contains': contains, 'may': may, 'vg': None,
                    'meat': meat_of(x) if cat in ('main', 'breakfast') else None,
                })
    src = ('A&W Canada menu and nutrition pages (feed behind web.aw.ca/en/our-menu), per item and per size as listed. '
           'Kids\' packs are split into their parts (burger or strips, apple slices, MadeGood bar, Milk2Go). '
           f'Left out: {len(dropped)} rows with no nutrition figures (plush toys, table spreads) or whose energy does not add up'
           + (f' ({"; ".join(dropped)})' if dropped else '') + '. Allergens from A&W\'s per-ingredient allergen table.')
    out = {'chain': 'ca-aw', 'name': 'A&W', 'how': 'Official menu nutrition feed', 'url': 'https://web.aw.ca/en/our-menu',
           'src': src, 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items}
    (HERE / 'ca-aw-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'ca-aw: {len(items)} items, dropped {len(dropped)}: {dropped}')


if __name__ == '__main__':
    main()
