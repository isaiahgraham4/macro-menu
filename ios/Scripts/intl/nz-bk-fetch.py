#!/usr/bin/env python3
"""Burger King New Zealand: downloads the nutrition PDFs linked from burgerking.co.nz/nutrition (the page's text lives in
Burger King's public Sanity dataset prod_bk_nz, which the site itself reads) and writes nz-bk-source.json beside this file.

The PDFs' text stream puts names in the wrong order, so rows are read by position: each table row (store status or size,
then serving size and seven per-serve figures, then seven per-100 g figures) takes the name printed nearest above it in the
left column (or beside it, for the drinks list), and the "Contains" / "May Contain" lines printed under that name.

Run: python3 ios/Scripts/intl/nz-bk-fetch.py
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
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'bknz'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
SANITY = 'https://czqk28jt.apicdn.sanity.io/v1/graphql/prod_bk_nz/default'
PAGE_ID = 'b5d7457f-821d-4bcd-b145-2f21e70cc19f'   # the static page at burgerking.co.nz/nutrition

CAT = {'Core Beef': 'main', 'Core Chicken': 'main', 'Plant-Based': 'main', 'Core Sides': 'side', 'Desserts': 'sweet',
       'Drinks': 'drink', 'Limited Time Offers': 'main', 'King Junior Meals': 'main'}
LABELS = {'Permanent', 'Limited Time', 'Small', 'Medium', 'Large', 'Regular'}
ALLERGEN_WORDS = [('gluten', 'gluten'), ('wheat', 'wheat'), ('milk', 'milk'), ('egg', 'egg'), ('soy', 'soy'), ('sesame', 'sesame'),
                  ('peanut', 'peanut'), ('tree nut', 'treenut'), ('almond', 'treenut'), ('fish', 'fish'), ('crustacea', 'shellfish'),
                  ('shellfish', 'shellfish'), ('mollusc', 'shellfish'), ('lupin', 'lupin'), ('sulphite', 'sulphites'), ('sulfite', 'sulphites')]
ORDER = ['gluten', 'wheat', 'milk', 'egg', 'soy', 'sesame', 'peanut', 'treenut', 'fish', 'shellfish', 'lupin', 'sulphites']
NUM = re.compile(r'^(\d{1,3}(,\d{3})+|\d+)(\.\d+)?$')
STATEMENT = re.compile(r'(?i)^(may contain|contains:? ?(none|gluten|wheat|milk|egg|soy|sesame|peanut|tree|fish|sulph|crust|lupin))')


def fetch(url, data=None, headers=None):
    time.sleep(0.3)
    req = urllib.request.Request(url, data=data, headers={'User-Agent': UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def pdf_links():
    q = '{ StaticPage(id:"%s"){ widgets{ ... on LocaleBlockTextWidget { localeBlockTextContent { enRaw } } } } }' % PAGE_ID
    d = json.loads(fetch(SANITY, json.dumps({'query': q}).encode(), {'content-type': 'application/json'}))
    links, label = [], None
    for w in d['data']['StaticPage']['widgets']:
        for b in (w or {}).get('localeBlockTextContent', {}).get('enRaw') or []:
            hrefs = {m['_key']: m.get('href') for m in b.get('markDefs', [])}
            text = ''.join(c.get('text', '') for c in b.get('children', [])).strip()
            href = next((hrefs[m] for c in b.get('children', []) for m in c.get('marks', []) if m in hrefs), None)
            if href and href.endswith('.pdf'):
                links.append((label, href))
            elif text:
                label = text
    return links


def lines(page):
    out = []
    for b in page.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ' '.join(s['text'] for s in l['spans']).strip()
            x0, y0, x1, _ = l['bbox']
            if t and (x1 - x0) > len(t) * 2:   # skips the sideways section labels
                out.append({'y': y0, 'x': x0, 't': t, 's': l['spans'][0]['size']})
    return sorted(out, key=lambda r: (round(r['y']), r['x']))


def rows_of(ls):
    """Groups numbers printed on the same baseline into table rows of 15 figures."""
    rows = []
    for l in ls:
        if not NUM.match(l['t']):
            continue
        for r in rows:
            if abs(r['y'] - l['y']) < 3:
                r['nums'].append(l)
                break
        else:
            rows.append({'y': l['y'], 'nums': [l]})
    good = []
    for r in rows:
        nums = sorted(r['nums'], key=lambda n: n['x'])
        if len(nums) == 15:
            label = next((l['t'] for l in ls if abs(l['y'] - r['y']) < 4 and l['t'] in LABELS), None)
            good.append({'y': r['y'], 'v': [float(n['t'].replace(',', '')) for n in nums], 'label': label})
    return good


def is_name(l):
    t = l['t']
    return (l['s'] >= 10.5 and l['x'] < 140 and not NUM.match(t) and t not in LABELS and not t.startswith(('PER ', 'Burger King Nutrition'))
            and not re.match(r'(?i)^(contains|may contain|ingredients|information|our restaurants|tm )', t) and len(t) < 70)


def allergens(text):
    found = []
    for word, key in ALLERGEN_WORDS:
        if word in text.lower() and key not in found:
            found.append(key)
    return [a for a in ORDER if a in found]


def read_row(section, ls, names, g, r, carry):
    grp_start, grp_end = g[0]['y'], g[-1]['y']
    beside = sorted((n for n in names if grp_start - 4 <= n['y'] <= grp_end + 4), key=lambda n: abs(n['y'] - r['y']))
    above = [n for n in names if n['y'] < grp_start - 4]
    if beside or above:
        name_line = beside[0] if beside else above[-1]
        block = [l for l in ls if name_line['y'] < l['y'] < grp_start]
    else:   # the name and ingredients were printed at the foot of the previous page
        name_line, block = carry[0], carry[1] + [l for l in ls if l['y'] < grp_start]
    text = ' '.join(l['t'] for l in block if STATEMENT.match(l['t']))
    ingredients = ' '.join(l['t'] for l in block if not STATEMENT.match(l['t']))
    m_may = re.search(r'(?i)may contain:?(.*)', text)
    m_con = re.search(r'(?i)(?<!may )contains:?(.*?)(?:may contain|$)', text)
    return {'section': section, 'name': name_line['t'], 'label': r['label'], 'v': r['v'],
            'contains': allergens(m_con.group(1)) if m_con else [], 'may': allergens(m_may.group(1)) if m_may else [],
            'has_statement': bool(m_con or m_may), 'ingredients': ingredients}


def parse(path, section):
    out = []
    doc = pymupdf.open(path)
    carry = ({'y': 0, 't': '?'}, [])
    for page in doc:
        ls = lines(page)
        rows = rows_of(ls)
        names = [l for l in ls if is_name(l)]
        sizes = ('Small', 'Medium', 'Large', 'Regular')
        groups = []
        for r in rows:   # size rows printed together (Small, Medium, Large) share one name
            g = groups[-1] if groups else None
            if (g and r['label'] in sizes and g[-1]['label'] in sizes and r['y'] - g[-1]['y'] < 22
                    and r['label'] not in [x['label'] for x in g]):
                g.append(r)
            else:
                groups.append([r])
        for g in groups:
            for r in g:
                out.append(read_row(section, ls, names, g, r, carry))
        last_row = rows[-1]['y'] if rows else 0
        tail = [n for n in names if n['y'] > last_row]
        if tail:
            carry = (tail[-1], [l for l in ls if l['y'] > tail[-1]['y'] and l['x'] < 300 and not l['t'].startswith(('Burger King Nutrition', 'Information correct', 'Our restaurants'))])
    return out


def tidy(name, label):
    name = re.sub(r'[®™]', '', name).replace('  ', ' ').strip()
    m = re.match(r'^(.*?) - (Small|Regular|Large|Medium)$', name)
    if m:
        name = f'{m.group(1)} ({m.group(2).lower()})'
    m = re.match(r'^(.*?) - (\d+) ?(?:pk|pack)$', name)
    if m:
        name = f'{m.group(1)} ({m.group(2)} pack)'
    m = re.match(r'^Rodeo Mega Stackers - (Beef|Chicken) (Single|Double|Triple)$', name)
    if m:
        name = f'Rodeo Mega Stacker {m.group(1)} ({m.group(2).lower()})'
    name = name.replace('Kings Collection - ', 'Kings Collection ').replace('WHOPPER', 'Whopper').replace(' - ', ' ')
    if label in ('Small', 'Medium', 'Large', 'Regular') and '(' not in name:
        name = f'{name} ({label.lower()})'
    return name


def per100_ok(v):
    """The PDFs print each item per serve and per 100 g; a row whose two halves disagree has a typo in one of them."""
    g = v[0]
    for i in (0, 1, 2, 4):   # energy, protein, fat, carbohydrate
        serve, per100 = v[1 + i], v[8 + i]
        want = per100 * g / 100
        if max(serve, want) > 2 and abs(serve - want) > max(3, 0.15 * max(serve, want)):
            return False
    return True


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    raw = []
    for label, href in pdf_links():
        path = PDFS / href.rsplit('/', 1)[1]
        if not path.exists():
            path.write_bytes(fetch(href))
        raw += parse(path, label)
    items, dropped, seen = [], [], set()
    for r in raw:
        name = tidy(r['name'], r['label'])
        g, kj, p, f, sat, c, sugar, na = r['v'][:8]
        if r['section'] == 'King Junior Meals' or name.startswith('King Box') or 'King Box' in name:
            dropped.append(f'{name} (meal or box)')
            continue
        if name in seen:
            continue
        seen.add(name)
        cal = kj / 4.184
        if not kj or (cal > 20 and abs(4 * p + 4 * c + 9 * f - cal) > cal / 3):
            dropped.append(f'{name} (energy does not add up)')
            continue
        if not per100_ok(r['v']):
            dropped.append(f'{name} (per serve and per 100 g figures disagree)')
            continue
        cat = CAT.get(r['section'], 'main')
        if 'Dip Pot' in name:
            cat = 'extra'
        elif r['section'] == 'Limited Time Offers':
            if 'Shake' in name:
                cat = 'drink'
            elif 'Fusion' in name or 'Sundae' in name:
                cat = 'sweet'
            elif 'Fries' in name:
                cat = 'side'
        ml = cat == 'drink' and 'Shake' not in name
        lower, ing = name.lower(), r['ingredients'].lower()
        meat = None
        if cat in ('main', 'side') and not any(w in lower for w in ('plant based', 'salad burger', 'vege')):
            meat = [m for w, m in (('beef', 'beef'), ('chicken', 'chicken'), ('bacon', 'pork'), ('ham ', 'pork'), ('pork', 'pork'))
                    if w in ing or w in lower]
            meat = sorted(set(meat), key=meat.index) or None
        items.append({
            'name': name, 'cat': cat, 'serve': f'1 serving ({g:g} {"ml" if ml else "g"})',
            'cal': None, 'kj': round(kj), 'p': p, 'c': c, 'f': f, 'sat': sat, 'sugar': sugar, 'fibre': None,
            'sodium': round(na), 'salt': None,
            'contains': r['contains'] if r['has_statement'] else None, 'may': r['may'] if r['has_statement'] else None,
            'vg': None, 'meat': meat,
        })
    # if one size of a drink or side fails the checks, the other sizes of it are not trusted either
    bad = {re.sub(r' \((small|medium|large|regular)\)$', '', d.split(' (energy')[0].split(' (per serve')[0]) for d in dropped if 'meal or box' not in d}
    for it in list(items):
        family = re.sub(r' \((small|medium|large|regular)\)$', '', it['name'])
        if family != it['name'] and family in bad:
            items.remove(it)
            dropped.append(f"{it['name']} (other sizes do not add up)")
    for it in items:
        for k in ('p', 'c', 'f', 'sat', 'sugar'):
            if isinstance(it[k], float) and it[k] == int(it[k]):
                it[k] = int(it[k])
    src = ('Burger King NZ Nutrition Information PDFs (Core Beef, Core Chicken, Core Sides, Plant-Based, Desserts, Drinks, '
           'Limited Time Offers), effective 11 November 2026 (Desserts and Drinks 31 July 2026). Per serve figures. '
           f'Left out: King Jr meals and King Boxes (bundles), and {sum("meal or box" not in d for d in dropped)} rows whose energy '
           'does not add up or whose per serve and per 100 g figures disagree '
           f'({"; ".join(d for d in dropped if "meal or box" not in d)}). Allergens are the "Contains" / "May contain" lines printed '
           'for each item; BK NZ says its restaurants handle gluten, wheat, egg, milk, soy, sesame, peanuts, tree nuts and sulphites.')
    out = {'chain': 'nz-bk', 'name': 'Burger King', 'how': 'Official nutrition PDFs', 'url': 'https://www.burgerking.co.nz/nutrition',
           'src': src, 'checked': date.today().isoformat(), 'energy': 'kj', 'halal': False, 'items': items}
    (HERE / 'nz-bk-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'nz-bk: {len(items)} items; dropped {dropped}')


if __name__ == '__main__':
    main()
