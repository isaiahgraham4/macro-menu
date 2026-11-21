#!/usr/bin/env python3
"""BurgerFuel (New Zealand): downloads the Nutritional Information PDF and the Allergen & Dietary Information Chart linked from
burgerfuel.com, and writes nz-burgerfuel-source.json beside this file.

Nutrition PDF: one sheet per item. Burgers are printed three ways (wholemeal bun, gluten-free bun, lower carb with salad
instead of the bun), each kept as its own row; sides, shakes, drinks and sauces have one panel each. Figures per serving.

Allergen chart: read by position (item name, core ingredients, allergens, vegetarian / vegan / halal columns). It covers
the full Australia New Zealand list (gluten cereals, crustacea, egg, fish, milk, molluscs, peanuts, sesame, soy, tree nuts,
lupin, sulphites). Its rows describe the standard item, so allergens and vegetarian / vegan marks go on the wholemeal-bun
burgers and on single-version items only; gluten-free-bun and lower-carb rows get null.

Run: python3 ios/Scripts/intl/nz-burgerfuel-fetch.py
"""
import json
import tempfile
import os
import pathlib
import re
import time
import urllib.parse
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'bfnz'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
HOME = 'https://www.burgerfuel.com/'
ALLERGENS = [('gluten', 'gluten'), ('wheat', 'wheat'), ('milk', 'milk'), ('egg', 'egg'), ('soy', 'soy'), ('sesame', 'sesame'),
             ('peanut', 'peanut'), ('almond', 'treenut'), ('cashew', 'treenut'), ('hazelnut', 'treenut'), ('macadamia', 'treenut'),
             ('pecan', 'treenut'), ('pistachio', 'treenut'), ('walnut', 'treenut'), ('tree nut', 'treenut'), ('fish', 'fish'),
             ('crustacea', 'shellfish'), ('mollusc', 'shellfish'), ('lupin', 'lupin'), ('sulphite', 'sulphites')]
ORDER = ['gluten', 'wheat', 'milk', 'egg', 'soy', 'sesame', 'peanut', 'treenut', 'fish', 'shellfish', 'lupin', 'sulphites']
FILLER = {'THE', 'AND', 'JUICE', 'ORGANICS', 'FRIENDLY', 'MEAL', 'KIDS', 'INK', 'THICKSHAKE', 'THICKSHAKES', 'BURGERFUEL', 'SAUCE', 'WITH'}
KEEP_UPPER = {'VTEC', 'BBQ', 'MOST', 'L&P', 'C', 'N', 'XL'}


def fetch(url):
    time.sleep(0.3)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': '*/*'}), timeout=120) as r:
        return r.read()


def links():
    html = fetch(HOME).decode('utf-8', 'replace')
    pdfs = re.findall(r'href="(https://cdn\.prod\.website-files\.com/[^"]+\.pdf)"', html)
    nutrition = next(u for u in pdfs if 'Nutritional' in urllib.parse.unquote(u))
    allergen = next(u for u in pdfs if 'allergen' in urllib.parse.unquote(u).lower())
    return nutrition, allergen


def tokens(name):
    t = name.upper().replace('Ū', 'U').replace('STANDARD', 'MILK').replace('L&P', 'LP')
    return frozenset(w for w in re.split(r'[^A-Z0-9]+', t) if w and w not in FILLER)


def title_case(s):
    out = []
    for w in s.split():
        out.append(w if w in KEEP_UPPER else '-'.join(x.capitalize() for x in w.split('-')) if w.isupper() else w)
    return ' '.join(out).replace('Kumara', 'Kūmara')


# ---------- allergen chart ----------

def chart(path):
    rows = []
    for page in pymupdf.open(path):
        ls = []
        for b in page.get_text('dict')['blocks']:
            for l in b.get('lines', []):
                t = ' '.join(s['text'] for s in l['spans']).strip()
                if t:
                    ls.append({'y': l['bbox'][1], 'x': l['bbox'][0], 't': t, 's': l['spans'][0]['size'], 'b': 'Bold' in l['spans'][0]['font']})
        ls = [l for l in ls if 60 < l['y'] < 515]
        names = sorted((l for l in ls if l['x'] < 60 and l['b'] and l['s'] < 8.5), key=lambda l: l['y'])
        groups = []
        for n in names:
            if groups and n['y'] - groups[-1][-1]['y'] < 10:
                groups[-1].append(n)
            else:
                groups.append([n])
        for i, g in enumerate(groups):
            y0 = g[0]['y']
            y1 = groups[i + 1][0]['y'] if i + 1 < len(groups) else 515
            flags = sorted((l for l in ls if 380 < l['x'] < 680 and l['t'] in ('Yes', 'No', '-') and abs(l['y'] - y0) < 8), key=lambda l: l['x'])
            alg = ' '.join(l['t'] for l in sorted(ls, key=lambda l: l['y'])
                           if 200 <= l['x'] < 380 and y0 - 6 <= l['y'] < y1 - 4 and (l['b'] or l['t'] == '-'))
            name = re.sub(r'\s*·\s*Limited.*$', '', ' '.join(n['t'] for n in g)).strip()
            if len(flags) != 3:
                continue
            found = [k for w, k in ALLERGENS if w in alg.lower()]
            vg = 'vegan' if flags[1]['t'] == 'Yes' else 'vegetarian' if flags[0]['t'] == 'Yes' else None
            ingredients = ' '.join(l['t'] for l in ls if 150 < l['x'] < 200 and y0 - 6 <= l['y'] < y1 - 4 and not l['b']).lower()
            meat = [m for w, m in (('beef', 'beef'), ('wagyu', 'beef'), ('bacon', 'pork'), ('chicken', 'chicken'), ('salmon', 'fish'),
                                   ('venison', 'venison')) if w in ingredients]
            meat = [m for m in dict.fromkeys(meat) if m != 'venison'] or None
            for variant in expand(name):
                rows.append({'tokens': tokens(variant), 'flat': flat(variant), 'contains': [a for a in ORDER if a in found], 'vg': vg, 'meat': meat})
    return rows


def flat(name):
    return re.sub(r'[^A-Z0-9]', '', name.upper().replace('Ū', 'U'))


def expand(name):
    m = re.match(r'^(.*) (\w+) / (\w+)$', name)
    return [f'{m.group(1)} {m.group(2)}', f'{m.group(1)} {m.group(3)}'] if m else [name]


def lookup(rows, *names):
    for name in names:
        tk = tokens(name)
        exact = [r for r in rows if r['tokens'] == tk or r['flat'] == flat(name)]
        if exact:
            return exact[0]
    return None


# ---------- nutrition sheets ----------

PANEL = re.compile(r'Per Serving \((\d+(?:\.\d+)?)g\) Per 100m?L?g? Energy ([\d.]+) kJ [\d.]+ kJ [\d.]+ kcal [\d.]+ kcal '
                   r'Protein ([\d.]+) g [\d.]+ g Fat, Total ([\d.]+) g [\d.]+ g - Saturated ([\d.]+) g [\d.]+ g '
                   r'Carbohydrates ([\d.]+) g [\d.]+ g - Sugars ([\d.]+) g [\d.]+ g Sodium ([\d.]+) mg')


def sheets(path):
    out = []
    for page in pymupdf.open(path):
        ls = [l.strip() for l in page.get_text().split('\n') if l.strip()]
        k = ls.index('burgerfuel.com/allergens')
        rest = ls[k + 1:]
        title = []
        for l in rest:
            if re.sub(r'[^A-Za-zŪū]', '', l) and l == l.upper():
                title.append(l)
            else:
                break
        starts = [j for j, l in enumerate(rest) if l == 'Content']
        prev_end = len(title)
        for j in starts:
            between = rest[prev_end:j]
            text = ' '.join(rest[j + 1:j + 28])
            m = PANEL.search(re.sub(r'\s+', ' ', text))
            if not m:
                continue
            note = next((n for n, l in enumerate(between) if l.startswith('*')), len(between))
            label = between[note - 1] if note else ''
            variant = 'gf' if any('Gluten Free Bun' in l for l in between) else 'lowcarb' if any('Lower Carb' in l for l in between) \
                else 'bun' if any(l.startswith('Served on a Wholemeal') for l in between) else None
            out.append({'title': title, 'label': label, 'variant': variant, 'v': [float(x) for x in m.groups()]})
            sod = next(n for n in range(j, len(rest)) if rest[n] == 'Sodium')
            prev_end = sod + 3
    return out


def name_of(s):
    title = [t for t in s['title'] if not re.match(r'^\(PAGE \d+ OF \d+\)$', t)]
    title = [re.sub(r'\s*\(PAGE \d+ OF \d+\)', '', t) for t in title]
    head = ' '.join(title)
    label = re.sub(r'\s+', ' ', s['label']).strip()
    if s['variant']:
        if head.startswith('KIDS INK.'):
            base = 'Kids ' + title_case(head.replace('KIDS INK.', '').replace('MEAL', '').strip())
        else:
            base = title_case(head)
            base = re.sub(r' (Single|Double|Large|Lightweight)$', lambda m: f' ({m.group(1).lower()})', base)
        suffix = {'bun': '', 'gf': 'gluten-free bun', 'lowcarb': 'lower carb'}[s['variant']]
        if suffix:
            base = base[:-1] + f', {suffix})' if base.endswith(')') else f'{base} ({suffix})'
        return base, head
    m = re.match(r'^(.*?) \((\d+)PC\) - No sauce$', label)
    if m:
        return f'{m.group(1)} ({m.group(2)} pc)', m.group(1)
    if label.endswith(' - No sauce'):
        return label[:-len(' - No sauce')], label[:-len(' - No sauce')]
    m = re.match(r'^(\w+)\s+\((Oat|Standard)\)$', label)
    if m:
        return f'{m.group(1)} Thickshake' + (' (oat)' if m.group(2) == 'Oat' else ''), f'{m.group(1)} {m.group(2)}'
    m = re.match(r'^Choppers with (BBQ|Sriracha) & BurgerFuel Aioli Sauce$', label)
    if m:
        return f'Southern Fried Choppers (with {m.group(1)} sauce and aioli)', 'SOUTHERN FRIED CHOPPERS'
    m = re.match(r'^(.*?) (\d+)ml$', label)
    if m:
        alias = re.match(r'^.*\((.*?)\) (\d+ml)$', label)
        return f'{m.group(1)} ({m.group(2)} ml)', f'{alias.group(1)} {alias.group(2)}' if alias else label
    if label == 'Small Choppers':
        return 'Kids Small Choppers', 'TEENY CHOPPERS'
    return label.replace('Kumara', 'Kūmara').replace('Burgerfuel', 'BurgerFuel'), label


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    n_url, a_url = links()
    n_path, a_path = PDFS / 'burgerfuel-nutrition.pdf', PDFS / 'burgerfuel-allergens.pdf'
    n_path.write_bytes(fetch(n_url))
    a_path.write_bytes(fetch(a_url))
    rows = chart(a_path)
    current = re.search(r'current as of (\d+ \w+ \d{4})', pymupdf.open(n_path)[0].get_text())
    issued = re.search(r'Issued: (\d\d/\d\d/\d{4})', pymupdf.open(a_path)[1].get_text())
    items, dropped, seen, unmatched = [], [], set(), []
    for s in sheets(n_path):
        name, key = name_of(s)
        if name.lower() in seen or 'Water' in name:
            continue
        seen.add(name.lower())
        g, kj, p, f, sat, c, sugar, na = s['v']
        cal = kj / 4.184
        if cal > 20 and abs(4 * p + 4 * c + 9 * f - cal) > cal / 3:
            dropped.append(name)
            continue
        low = name.lower()
        drink = 'ml)' in low or 'thickshake' in low
        cat = ('drink' if drink else 'main' if 'choppers' in low else 'extra' if any(w in low for w in ('aioli', 'tomato sauce')) else
               'side' if any(w in low for w in ('fries', 'rodders')) else 'main')
        short = s['title'][0] if s['title'] else key
        found = lookup(rows, key, re.sub(r'^KIDS INK\.\s*|\s*MEAL$', '', key), short)
        allergen_row = found if s['variant'] in ('bun', None) else None
        if s['variant'] in ('bun', None) and not found:
            unmatched.append(name)
        items.append({
            'name': name, 'cat': cat, 'serve': f'1 serving ({g:g} {"ml" if "ml)" in low else "g"})',
            'cal': None, 'kj': round(kj), 'p': p, 'c': c, 'f': f, 'sat': sat, 'sugar': sugar, 'fibre': None,
            'sodium': round(na), 'salt': None,
            'contains': allergen_row['contains'] if allergen_row else None, 'may': None,
            'vg': allergen_row['vg'] if allergen_row else None,
            'meat': ['chicken'] if 'choppers' in low else found['meat'] if found and cat == 'main' else None,
        })
    for it in items:
        for k in ('p', 'c', 'f', 'sat', 'sugar'):
            if it[k] == int(it[k]):
                it[k] = int(it[k])
    src = (f'BurgerFuel Nutritional Information PDF (current as of {current.group(1) if current else "?"}) and Allergen & Dietary '
           f'Information Chart (issued {issued.group(1) if issued else "?"}), both linked from burgerfuel.com. Burgers are listed on '
           'the wholemeal bun, on the gluten-free bun and as the lower-carb option (salad instead of the bun). Kids burgers are the '
           'burger only, not the meal. Left out: bottled water'
           + (f', and {len(dropped)} rows whose energy does not add up ({"; ".join(dropped)})' if dropped else '')
           + '. Allergens and vegetarian / vegan marks from the chart, for the standard (wholemeal bun) version only; '
           f'gluten-free-bun and lower-carb rows, and items the chart does not list ({len(unmatched)}), have none.')
    out = {'chain': 'nz-burgerfuel', 'name': 'BurgerFuel', 'how': 'Official nutrition and allergen PDFs', 'url': 'https://www.burgerfuel.com/',
           'src': src, 'checked': date.today().isoformat(), 'energy': 'kj', 'halal': False, 'items': items}
    (HERE / 'nz-burgerfuel-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'nz-burgerfuel: {len(items)} items, dropped {dropped}, no allergen row: {unmatched}')


if __name__ == '__main__':
    main()
