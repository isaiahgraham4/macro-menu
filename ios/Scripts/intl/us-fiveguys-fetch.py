#!/usr/bin/env python3
"""Five Guys (US): the Nutrition & Allergen Guide PDF linked from fiveguys.com/nutritional-allergy-information, saved as
us-fiveguys-source.json.

Five Guys builds every burger and dog to order, so its guide lists the parts: patties, buns, hot dogs, each topping, fries by
size, the shake base and each mix-in, drinks and sauces. Those parts are kept as published. Three plain items are also added
as the sum of their published parts, because they have no toppings to choose: Hamburger (bun + 2 patties), Little Hamburger
(bun + 1 patty) and Hot Dog (bun + hot dog). Where the guide lists the same part from two suppliers (bacon, hot dog, cheese,
mayonnaise, pickles, whipped cream), the first one listed is kept.

The allergen chart (blue dots per item) covers the nine US majors, sesame included; the guide has no may-contain column.
"<1" in the guide is saved as 0.5.

Run: python3 ios/Scripts/intl/us-fiveguys-fetch.py
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
OUT = HERE / 'us-fiveguys-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
PAGE = 'https://www.fiveguys.com/nutritional-allergy-information/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

COLS = [('g', 104), ('cal', 128), ('calfat', 153), ('f', 179), ('sat', 206), ('trans', 233), ('chol', 260), ('sodium', 287),
        ('c', 313), ('fibre', 338), ('sugar', 364), ('p', 389)]
# allergen dot x centre -> app keys (Milk, Eggs, Wheat, Soybean, Peanuts, Sesame, Tree Nuts, Shellfish, Fish)
DOTS = [(412, ['milk']), (431, ['egg']), (450, ['gluten', 'wheat']), (470, ['soy']), (493, ['peanut']), (514, ['sesame']),
        (535, ['treenut']), (553, ['shellfish']), (578, ['fish'])]


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    s = s.replace(' ', '')
    if s.startswith('<'):
        return 0.5
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def parse(pdf):
    """[(section, name, {col: value}, [allergens])] in guide order, up to the ingredient listing."""
    out = []
    for page in pdf:
        words = page.get_text('words')
        names, numbers, heads = [], [], []
        for w in words:
            y = (w[1] + w[3]) / 2
            if w[0] < 92:
                names.append((y, w[0], w[4]))
            elif w[0] < 400 and re.fullmatch(r'[<\d.\-]+', w[4]):
                numbers.append((y, w[0], w[4]))
        # group name words into lines
        lines = []
        for y, x, t in sorted(names):
            if lines and abs(lines[-1][0] - y) < 2.5:
                lines[-1][1].append((x, t))
            else:
                lines.append([y, [(x, t)]])
        rows = []
        for y, ws in lines:
            text = ' '.join(t for x, t in sorted(ws))
            rows.append({'y': y, 'text': text, 'nums': [], 'dots': set()})
        item_rows = [r for r in rows if not (r['text'].isupper() and len(r['text']) > 3) or re.search(r'[a-z]', r['text'])]
        for y, x, t in numbers:
            near = min(item_rows, key=lambda r: abs(r['y'] - y), default=None)
            if near and abs(near['y'] - y) < 5:
                near['nums'].append((x, t))
        for d in page.get_drawings():
            r = d['rect']
            if d.get('fill') and r.x0 > 400 and 5 < r.width < 9 and 5 < r.height < 9:
                cy, cx = (r.y0 + r.y1) / 2, (r.x0 + r.x1) / 2
                near = min(item_rows, key=lambda row: abs(row['y'] - cy), default=None)
                if near and abs(near['y'] - cy) < 5:
                    near['dots'].update(min(DOTS, key=lambda c: abs(c[0] - cx))[1])
        for r in rows:
            if not r['nums']:
                if re.match(r'[A-Z][A-Z \-%0-9]+(\(|$)', r['text']):
                    out.append(('SECTION', r['text'], None, None))
                continue
            # join "<" "1" written as two words, then put each value in the nearest column
            toks = sorted(r['nums'])
            merged = []
            for x, t in toks:
                if merged and merged[-1][1] == '<':
                    merged[-1] = (merged[-1][0], '<' + t)
                else:
                    merged.append((x, t))
            vals = {}
            for x, t in merged:
                vals[min(COLS, key=lambda c: abs(c[1] - x))[0]] = t
            out.append(('ITEM', r['text'], vals, sorted(r['dots'])))
    return out


def main():
    page = get(PAGE).decode('utf-8', 'replace')
    m = re.search(r'https://www\.fiveguys\.com/wp-content/uploads/[^"\']+?US-Nutrition-Allergen-Guide-English[^"\']*?\.pdf', page)
    if not m:
        raise SystemExit('Five Guys: the US Nutrition & Allergen Guide link is missing from the page')
    pdf_url = m.group(0)
    edition = re.search(r'English-?(.*)\.pdf', pdf_url).group(1).replace('-', ' ')
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'us-fiveguys.pdf'
    path.write_bytes(get(pdf_url))
    rows = parse(pymupdf.open(path))

    items, parts, dropped, kept_parts = [], {}, [], set()
    section, mini = '', False
    for kind, text, vals, dots in rows:
        if kind == 'SECTION':
            section = text.split(' (')[0].split(' - ')[0]
            if section == 'INGREDIENT LISTING':
                break
            if section == 'MINI MILKSHAKES':
                mini = True
            elif section == 'MILKSHAKES':
                mini = False
            continue
        v = {k: num(vals.get(k, '')) for k, _ in COLS}
        if v['cal'] is None or any(v[k] is None for k in ('p', 'c', 'f')):
            continue
        raw = text.replace('®', '').replace('’', "'")
        base = re.sub(r'\s*\(Supplier [A-Z]\)', '', raw)
        if (section, base, mini) in kept_parts:       # second supplier of the same part
            continue
        kept_parts.add((section, base, mini))
        name, cat, serve = base, 'extra', None
        g = v['g']
        fries = re.match(r'(Mini|Little|Regular|Large) (Five Guys|Cajun) Style', base)
        if section == 'FRIES' and fries:
            size, style = fries.group(1).lower(), fries.group(2)
            name = f"{'Cajun Fries' if style == 'Cajun' else 'Five Guys Style Fries'} ({size})"
            cat = 'side'
        elif section == 'MEAT':
            cat = 'extra'
            if base == 'Hot Dog':
                name = 'Hot Dog (sausage only)'
        elif base == 'Hot Dog Buns':
            name = 'Hot Dog Bun'
        elif section in ('MILKSHAKES', 'MINI MILKSHAKES'):
            if 'Shake Base' in base:
                name, cat = f"Vanilla Milkshake ({'mini' if mini else 'regular'}, no mix-ins)", 'drink'
            else:
                name = f"{base} (on a {'mini ' if mini else ''}shake)"
        elif section == 'MIX-INS':
            name = f"{base} (shake mix-in{', mini' if mini else ''})"
        elif section == 'DRINKS':
            cat = 'drink'
        elif section == 'PEANUTS':
            name = re.sub(r'\s*\(1oz\.\)', '', base)
            if name == 'Bulk Peanuts':
                name = 'Peanuts'
            serve, cat = '1 oz (30 g)' if g == 30 else None, 'side'
        elif base.startswith('Eggs'):
            name, cat = 'Eggs (2)', 'breakfast'
        elif base.startswith('Fry Sauce'):
            name = 'Fry Sauce (packet)' if base.endswith('PC') else 'Fry Sauce'
        name = re.sub(r'\(1tbs\)', '(1 tbsp)', name)
        if serve is None:
            serve = f'1 serving ({g} g)' if isinstance(g, (int, float)) else '1 serving'
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
            dropped.append(name)
            continue
        item = {
            'name': name, 'cat': cat, 'serve': serve, 'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
            'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None,
            'contains': dots, 'may': None, 'vg': None, 'meat': None,
        }
        if section == 'MEAT':
            item['meat'] = ['pork'] if 'Bacon' in name else ['beef']
        parts[(section, base, mini)] = item
        items.append(item)

    def built(name, serve, pieces, meat):
        ps = [parts[p] for p in pieces]
        tot = {k: round(sum(p[k] or 0 for p in ps), 1) for k in ('cal', 'p', 'c', 'f', 'sat', 'sugar', 'fibre', 'sodium')}
        tot = {k: int(x) if x == int(x) else x for k, x in tot.items()}
        return {'name': name, 'cat': 'main', 'serve': serve, 'cal': tot['cal'], 'kj': None, 'p': tot['p'], 'c': tot['c'], 'f': tot['f'],
                'sat': tot['sat'], 'sugar': tot['sugar'], 'fibre': tot['fibre'], 'sodium': tot['sodium'], 'salt': None,
                'contains': sorted(set().union(*(p['contains'] for p in ps))), 'may': None, 'vg': None, 'meat': meat}
    bun, patty = ('BUN', 'Hamburger Bun', False), ('MEAT', 'Hamburger Patty', False)
    made = [built('Hamburger', 'bun + 2 patties, no toppings', [bun, patty, patty], ['beef']),
            built('Little Hamburger', 'bun + 1 patty, no toppings', [bun, patty], ['beef']),
            built('Hot Dog', 'bun + all-beef hot dog, no toppings', [('BUN', 'Hot Dog Buns', False), ('MEAT', 'Hot Dog', False)], ['beef'])]
    items = made + items

    # The guide's Cajun group repeats "Mini Five Guys Style" with different figures; it's left out rather than guessed at.
    src = (f"Five Guys Nutrition & Allergen Guide, USA, {edition} edition. Burgers and dogs are built to order, so the guide lists "
           f"their parts (patties, buns, each topping); Hamburger, Little Hamburger and Hot Dog here are the sums of their "
           f"published parts with no toppings. Where a part comes from two suppliers the first listed is kept. \"<1\" is saved "
           f"as 0.5. Fries are cooked in refined peanut oil, which the guide doesn't count as a peanut allergen. Left out: a second "
           f"\"Mini Five Guys Style\" fries row in the guide's Cajun group (its label doesn't say which fries it is)")
    if dropped:
        src += f"; {len(dropped)} row(s) left out whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-fiveguys', 'name': 'Five Guys', 'how': 'Official nutrition and allergen guide (PDF)', 'url': PAGE,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Five Guys: {len(items)} items, {len(dropped)} dropped -> {OUT.name}')


if __name__ == '__main__':
    main()
