#!/usr/bin/env python3
"""Jack in the Box (US): the Nutrition Facts poster PDF that jackinthebox.com links as its nutrition guide, saved as
us-jitb-source.json.

jackinthebox.com embeds the guide's address (a Sanity CDN file) as "nutritionUrl" in its pages, so a plain request finds the
current edition. The poster has two panels; each item gives allergen letters (S soy, E egg, M milk, W wheat, F fish,
C shellfish, P peanut, T tree nut, ss sesame), then serving weight, calories, calories from fat, fat, saturated fat, trans fat,
cholesterol, sodium, potassium, carbs, fibre, sugars and protein.

The poster's text layer is imperfect, so every row is checked before it's kept:
- a row must have calories, protein, carbs and fat in their columns (a missing sodium or saturated fat is saved as null);
- a row whose figures are exactly another item's (the text layer repeats the Hash Brown's figures on one burrito) is dropped;
- items listed in more than one panel (Kids, Jack's Deals, Better for You) must agree; a serving weight that can't be right
  (over 9.5 Cal per gram) is taken from the other listing, or left out;
- calories must be within a third of 4p + 4c + 9f.
Left out as well: the Munchie Meal panel's meal-only sizes, bottled water, and rows whose name isn't in the text layer.

Run: python3 ios/Scripts/intl/us-jitb-fetch.py
"""
import json
import os
import pathlib
import re
import tempfile
import urllib.request
from collections import Counter
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-jitb-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
SITE = 'https://www.jackinthebox.com/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
KEYS = ['g', 'cal', 'calfat', 'f', 'sat', 'trans', 'chol', 'sodium', 'potassium', 'c', 'fibre', 'sugar', 'p']
PANELS = [
    {'name': (60, 240), 'alg': (240, 280), 'num': (278, 630), 'cols': [284, 313, 343, 374, 401, 428, 452, 481, 513, 542, 569, 590, 614]},
    {'name': (660, 840), 'alg': (840, 875), 'num': (870, 1225), 'cols': [879, 908, 937, 969, 996, 1022, 1048, 1076, 1108, 1138, 1164, 1185, 1209]},
]
LETTERS = {'S': ['soy'], 'E': ['egg'], 'M': ['milk'], 'W': ['gluten', 'wheat'], 'F': ['fish'], 'C': ['shellfish'], 'P': ['peanut'],
           'T': ['treenut'], 'ss': ['sesame']}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    if s is None:
        return None
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def allergens(tokens):
    text = ''.join(tokens).replace(',', '')
    out = set()
    if 'ss' in text:
        out.update(LETTERS['ss'])
        text = text.replace('ss', '')
    for ch in text:
        if ch not in LETTERS:
            raise SystemExit(f'Jack in the Box: unknown allergen letter "{ch}" in {tokens}')
        out.update(LETTERS[ch])
    return sorted(out)


def parse(page):
    """[(panel, y, section, name, allergen tokens, {key: text})] for every row with figures and a name."""
    words = page.get_text('words')
    rows = []
    for pi, P in enumerate(PANELS):
        lines = {}
        for w in words:
            if P['name'][0] <= w[0] < P['num'][1]:
                lines.setdefault(round((w[1] + w[3]) / 2 / 4), []).append(w)
        names, nums = [], []
        for k in sorted(lines):
            ws, y = sorted(lines[k], key=lambda w: w[0]), k * 4
            nm = [w for w in ws if P['name'][0] <= w[0] < P['name'][1]]
            al = [w[4] for w in ws if P['alg'][0] <= w[0] < P['alg'][1]]
            nu = [w for w in ws if P['num'][0] <= w[0] < P['num'][1] and re.fullmatch(r'[\d.]+', w[4])]
            text = ' '.join(w[4] for w in nm)
            if nm and not re.match(r'[\^*#>~]', text):
                names.append({'y': y, 'text': text, 'alg': list(al) if len(nu) < 8 else [], 'used': False})
            if len(nu) >= 8:
                nums.append({'y': y, 'nums': nu, 'alg': al})
            elif al and names and abs(names[-1]['y'] - y) <= 4:
                names[-1]['alg'] += al
        for r in nums:
            near = [n for n in names if abs(n['y'] - r['y']) <= 5]
            if not near:
                continue
            n = min(near, key=lambda n: (abs(n['y'] - r['y']), -n['y']))
            n['used'] = True
            toks = []       # digits of one number the text layer split in two ("3" "2" -> 32)
            for w in r['nums']:
                if toks and w[0] - toks[-1][2] < 2.5 and re.fullmatch(r'\d+', w[4]):
                    toks[-1] = (toks[-1][0], toks[-1][1], w[2], w[3], toks[-1][4] + w[4])
                else:
                    toks.append(w)
            vals = {}
            for w in toks:
                ci = min(range(13), key=lambda i: abs(P['cols'][i] - w[0]))
                vals[KEYS[ci]] = None if KEYS[ci] in vals else w[4]     # two numbers in one column: unreadable
            rows.append([pi, r['y'], n['text'], r['alg'] or n['alg'], vals])
        # section headings are the name-column lines that got no figures
        heads = [(n['y'], n['text']) for n in names if not n['used'] and len(n['text']) < 40]
        for row in rows:
            if row[0] == pi:
                above = [t for y, t in heads if y < row[1]]
                row.insert(2, section(above[-1] if above else ''))
    return rows


def section(text):
    t = text.replace(' ', '').lower()
    if 'kids' in t:
        return 'kids'
    if 'deals' in t:
        return 'deals'
    if t.startswith("jack'") or 'munch' in t:
        return 'munchie'
    if 'breakfast' in t:
        return 'breakfast'
    if 'beverages' in t:
        return 'drinks'
    return t


def tidy(name):
    name = re.sub(r'[®™^*#]', '', name).replace('ﬀ', 'ff').replace('ﬂ.', 'fl.').replace('’', "'")
    name = re.sub(r'\s+', ' ', name).strip()
    name = {'Taco, Regular (1 Taco)': 'Taco', 'Tacos, Regular (2 Tacos)': 'Tacos (2)', 'Taco, Tiny (13 pc.)': 'Tiny Tacos (13 pc)',
            'Taco, Tiny (Sauced & Loaded)': 'Tiny Tacos, Sauced & Loaded'}.get(name, name)
    m = re.match(r'(Rg|Lg) (.*?) with Whipped Topping ?- ?(\d+) ?oz', name)
    if m:
        return f"{m.group(2)} ({'regular' if m.group(1) == 'Rg' else 'large'}, {m.group(3)} oz)"
    name = re.sub(r'^Shake, Vanilla with Boba & Whipped Topping - 16 fl\. oz\.', 'Vanilla Shake with Boba (16 oz)', name)
    name = re.sub(r'\s*-\s*Rg\.$', ' (regular)', name)
    name = re.sub(r'\s*-\s*Lg\.$', ' (large)', name)
    name = re.sub(r'\s*-\s*(\d+) fl\. oz\.$', r' (\1 oz)', name)
    name = name.replace('Gold Peak Fresh Brewed Iced Tea', 'Gold Peak Iced Tea')
    name = name.replace('Jack Wrap- ', 'Jack Wrap - ').replace('(a al carte)', '').replace('pc.)', 'pc)')
    name = re.sub(r'\((\d+)pc\)', r'(\1 pc)', name)
    name = re.sub(r'\((Small|Medium|Large)\)', lambda m: f'({m.group(1).lower()})', name)
    name = name.replace("(Kid's)", "(kids)").replace('(Seasonal)', '(seasonal)')
    return re.sub(r'\s+', ' ', name).strip()


def category(name, sec):
    n = name.lower()
    if sec == 'drinks' or re.search(r'shake|coffee|tea\b|juice|red bull|milk$|water', n):
        return 'drink'
    if re.search(r'\bcake\b|churros|cheesecake', n):
        return 'sweet'
    if re.search(r'\bsauce\b|dip cup|dipping|dressing|cheese$|syrup|jelly|\bjam\b|ketchup|mustard|mayo|^fire roasted salsa|'
                 r'spread|herb butter|grilled onions|croutons|tortilla strips', n) and 'sandwich' not in n:
        return 'extra'
    if re.search(r'fries|onion rings|egg roll|jalape|side salad|hash brown|halfsies|tiny tacos', n):
        return 'side'
    if sec == 'breakfast' or 'breakfast' in n or 'croissant' in n:
        return 'breakfast'
    return 'main'


MEATS = [(r'chicken|nugget|cluck|jack wrap', 'chicken'),
         (r'burger|jumbo jack|buttery jack|smashed jack|double jack|sourdough jack|\btacos?\b', 'beef'),
         (r'bacon|sausage|\bham\b|meat lovers', 'pork'), (r'\bfish\b', 'fish')]


def meat(name):
    n = name.lower()
    out = [m for pat, m in MEATS if re.search(pat, n)]
    if n.startswith('breakfast jack') and 'pork' not in out:
        out.append('pork')          # ham
    return out or None


def main():
    html = get(SITE).decode('utf-8', 'replace')
    m = re.search(r'nutritionUrl\\?":\\?"(https://cdn\.sanity\.io/files/[^"\\]+\.pdf)', html)
    if not m:
        raise SystemExit('Jack in the Box: the nutrition guide link (nutritionUrl) is missing from jackinthebox.com')
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'us-jitb.pdf'
    path.write_bytes(get(m.group(1)))
    page = pymupdf.open(path)[0]
    edition = re.search(r'effective\s+as\s+of\s+([A-Z][a-z]+ \d{4})', re.sub(r'\s+', ' ', page.get_text()))
    edition = edition.group(1) if edition else 'current'

    raw, skipped = [], Counter()
    for pi, y, sec, text, alg, vals in parse(page):
        name = tidy(text)
        v = {k: num(vals.get(k)) for k in KEYS}
        if sec == 'munchie' and re.search(r'Munchie Meal|Two Tacos', name) or re.search(r'Water Bottle|^Sweet N$', name):
            skipped['meal or other'] += 1
            continue
        if any(v[k] is None for k in ('cal', 'p', 'c', 'f')):
            skipped['unreadable'] += 1
            continue
        raw.append({'name': name, 'sec': sec, 'alg': allergens(alg), 'v': v})

    # the same figures under two different names: the text layer's repeat, not the item's figures
    vec = lambda r: tuple(r['v'][k] for k in ('g', 'cal', 'f', 'sat', 'sodium', 'c', 'fibre', 'sugar', 'p'))
    first_name = {}
    kept = []
    for r in raw:
        owner = first_name.setdefault(vec(r), r['name'])
        if owner != r['name']:
            skipped['repeated figures'] += 1
            continue
        kept.append(r)

    items, by_name, dropped = [], {}, []
    for r in kept:
        v, name = r['v'], r['name']
        if name in by_name:
            prev = by_name[name]
            pv = prev['_v']
            if all(pv[k] == v[k] for k in ('cal', 'p', 'c', 'f')):
                if (not pv['g'] or pv['cal'] / pv['g'] > 9.5) and v['g'] and v['cal'] / v['g'] <= 9.5:
                    prev['serve'] = f"1 serving ({v['g']} g)"
                    pv['g'] = v['g']
                continue
            name = f"{name} ({'kids' if r['sec'] == 'kids' else r['sec']})"
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
            dropped.append(name)
            continue
        portion = re.search(r'\s*\((\d*\.?\d+ (?:fl\. )?oz)\.\)|\s*\((1 (?:packet|cup))\)', name)
        if portion:
            name = (name[:portion.start()] + name[portion.end():]).strip()
            portion = (portion.group(1) or portion.group(2)).replace('fl. oz', 'fl oz')
        g = v['g'] if v['g'] and (v['cal'] == 0 or v['cal'] / v['g'] <= 9.5) else None
        item = {
            'name': name, 'cat': category(name, r['sec']),
            'serve': f"{portion or '1 serving'} ({g} g)" if g else portion or '1 serving',
            'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'], 'sat': v['sat'], 'sugar': v['sugar'],
            'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None, 'contains': r['alg'], 'may': None, 'vg': None,
            'meat': meat(name), '_v': dict(v),
        }
        by_name.setdefault(r['name'], item)
        items.append(item)
    names = Counter()
    for i in items:
        del i['_v']
        names[i['name']] += 1
        if names[i['name']] > 1:            # e.g. Ketchup as a dip cup portion and as a packet
            i['name'] = f"{i['name']} ({i['serve'].split(' (')[0]})"


    left = ', '.join(f'{n} {k}' for k, n in skipped.items())
    src = (f"Jack in the Box Nutrition Facts poster (effective {edition}). Allergens are the poster's letters (the nine US "
           f"majors, sesame included). The poster's text layer is imperfect, so rows were checked against each other and "
           f"against their macros; left out: {left} row(s), bottled water and Munchie Meal-only sizes")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-jitb', 'name': 'Jack in the Box', 'how': 'Official nutrition facts poster (PDF)', 'url': SITE + 'menu',
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Jack in the Box: {len(items)} items, {len(dropped)} dropped, skipped {dict(skipped)} -> {OUT.name}')


if __name__ == '__main__':
    main()
