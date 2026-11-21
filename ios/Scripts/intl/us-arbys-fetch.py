#!/usr/bin/env python3
"""Arby's (US): the Nutrition & Allergen Information PDF linked from arbys.com/nutrition, saved as us-arbys-source.json.

arbys.com/nutrition embeds the guide's address (a Contentful asset) in the page, so a plain request finds the current edition.
The guide lists each item with "Contains:" / "May contain:" allergens (the nine US majors, sesame included), then serving
weight, calories, calories from fat, fat, saturated fat, trans fat, cholesterol, sodium, carbs, fibre, sugars and protein.

Left out: bottled water, items listed twice (the Kids Menu and Value Menu repeat sliders, fries and sauces), and rows whose
calories are far from 4p + 4c + 9f (more than a third out), which are counted in `src`.

Run: python3 ios/Scripts/intl/us-arbys-fetch.py
"""
import json
import os
import pathlib
import tempfile
import re
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-arbys-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
PAGE = 'https://www.arbys.com/nutrition/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

# x position (pt) of each number column in the guide
COLS = [('g', 400), ('cal', 428), ('calfat', 461), ('f', 493), ('sat', 526), ('trans', 557), ('chol', 587), ('sodium', 617),
        ('c', 651), ('fibre', 683), ('sugar', 714), ('p', 745)]
ALLERGENS = {'milk': ['milk'], 'egg': ['egg'], 'eggs': ['egg'], 'wheat': ['gluten', 'wheat'], 'soy': ['soy'], 'sesame': ['sesame'],
             'fish': ['fish'], 'shellfish': ['shellfish'], 'crustacean shellfish': ['shellfish'], 'peanut': ['peanut'],
             'peanuts': ['peanut'], 'tree nuts': ['treenut'], 'tree nut': ['treenut'], 'coconut': ['treenut']}
SIZES = {'small': 'small', 'medium': 'medium', 'med': 'medium', 'large': 'large', 'xl': 'XL'}


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    s = s.replace('+', '').replace('<', '')
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def allergen_list(text, where):
    out = set()
    for w in re.split(r'[,;]|\band\b', text):
        w = re.sub(r'\(.*?\)', '', w).strip().lower()
        if not w:
            continue
        if w not in ALLERGENS:
            raise SystemExit(f'{where}: unknown allergen "{w}"')
        out.update(ALLERGENS[w])
    return sorted(out)


def rows(pdf):
    """Yield (page, section, words-left-of-numbers, {column: text}) for every line of the guide."""
    for pn, page in enumerate(pdf):
        lines = {}
        for w in page.get_text('words'):
            if (w[1] + w[3]) / 2 < 135:          # page header
                continue
            lines.setdefault(round((w[1] + w[3]) / 2 / 3), []).append(w)
        for k in sorted(lines):
            ws = sorted(lines[k], key=lambda w: w[0])
            left = [(w[4], w[0], w[2]) for w in ws if w[0] < 385]
            cols = {}
            for w in ws:
                if w[0] >= 385:
                    key = min(COLS, key=lambda c: abs(c[1] - w[0]))[0]
                    cols[key] = (cols.get(key, '') + ' ' + w[4]).strip()
            yield pn, left, cols


def tidy(name):
    name = name.replace('‘', "'").replace('’', "'").replace('®', '').replace('™', '').replace('°', '')
    name = re.sub(r'^[•*\s]+', '', name)
    name = re.sub(r'\s+u$|\s+u\s', ' ', name).replace('†', '')
    name = re.sub(r'\s+', ' ', name).strip()
    name = re.sub(r'\s+Adds$', '', name)
    name = re.sub(r'\((\d+)\)', r'(\1 pc)', name)
    name = name.replace('Sausage Gravy Biscuit-Double', 'Sausage Gravy Biscuit (double)')
    m = re.match(r'(.*?)\s*–\s*(Small|Medium|Large|XL)$', name)
    if m:
        name = f'{m.group(1)} ({SIZES[m.group(2).lower()]})'
    return name


def category(name, section):
    n = name.lower()
    if section == 'TOPPINGS' or re.search(r'sauce|ketchup', n) and 'mac' not in n:
        return 'extra'
    if 'DRINKS' in section or re.search(r'shake|lemonade|tea\b|coffee|juice|milk\b|shirley|water', n):
        return 'drink'
    if re.search(r'turnover|cobbler', n):
        return 'sweet'
    if re.search(r'fries|potato cakes|mozzarella sticks|jalapeno bites|mac .n cheese|applesauce', n):
        return 'side'
    if section == 'BREAKFAST':
        return 'breakfast'
    return 'main'


def meat(name):
    n = name.lower()
    out = []
    for word, m in (('beef', 'beef'), ('angus', 'beef'), ('steak', 'beef'), ('gyro', 'beef'), ('reuben', 'beef'), ('arbyq', 'beef'),
                    ('chicken', 'chicken'), ('turkey', 'turkey'), ('ham', 'pork'), ('bacon', 'pork'), ('sausage', 'pork')):
        if re.search(r'\b' + word, n) and m not in out:
            out.append(m)
    if 'french dip' in n or "arby's melt" in n:
        out.append('beef')
    return out or None


def main():
    page = get(PAGE).decode('utf-8', 'replace')
    m = re.search(r'(//assets\.ctfassets\.net/[^"\s]+?Arbys_Nutritional_and_Allergen[^"\s]*?\.pdf)', page)
    if not m:
        raise SystemExit("Arby's: the Nutrition & Allergen guide link is missing from arbys.com/nutrition")
    pdf_url = 'https:' + m.group(1)
    edition = re.sub(r'.*Allergen_?', '', pdf_url).replace('.pdf', '').replace('_', ' ')
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'us-arbys.pdf'
    path.write_bytes(get(pdf_url))
    pdf = pymupdf.open(path)

    items, seen, dropped, section = [], set(), [], ''
    for pn, left, cols in rows(pdf):
        # The shared-fryer list is a separate right-hand block ending "Fish (where available)"; it can follow a dagger.
        fryer = []
        wi = next((i for i, w in enumerate(left) if w[0] == '(where'), None)
        if wi is not None:
            j = wi - 1
            while j >= 0 and left[j][0] != '†' and (j == wi - 1 or left[j][2] + 5 >= left[j + 1][1]):
                j -= 1
            fryer = [w[0] for w in left[j + 1:wi]]
            left = left[:j + 1] + left[wi + 2:]
        text = ' '.join(w[0] for w in left if w[0] != '†')
        if 'cal' not in cols:
            if left and text.replace('’', '').replace('/', '').replace(' ', '').isupper() and len(text) > 3:
                section = text.replace('’', "'")
            continue
        name_part, contains, may = text, [], []
        star = text.lstrip('• ').startswith('*')
        text = text.replace('Wheat/May', 'Wheat; May').replace('May Contain', 'May contain')
        mm = re.search(r'\bContains:', text)
        if mm:
            name_part, rest = text[:mm.start()], text[mm.end():]
            if 'May contain' in rest:
                rest, mayt = rest.split('May contain', 1)
                may = allergen_list(mayt.strip(' :'), name_part)
            if '**' in rest:          # **Milk: only where buttered buns are served (two US markets)
                rest, bun = rest.split('**', 1)
                may = sorted(set(may) | set(allergen_list(bun, name_part)))
            contains = allergen_list(rest.strip(' ;'), name_part)
        if fryer:
            may = sorted((set(may) | set(allergen_list(' '.join(fryer), name_part))) - set(contains))
        if star:
            may = sorted(set(may) | {'peanut', 'treenut'})
        name = tidy(name_part)
        size = None
        serve_txt = cols.get('g', '')
        if 'DRINKS' in section and section != 'MISCELLANEOUS DRINKS':
            size = SIZES[section.split()[0].lower()]
            name = f'{name} ({size})'
        vals = {k: num(cols.get(k, '')) for k, _ in COLS if k != 'g'}
        if vals['cal'] is None or any(vals[k] is None for k in ('p', 'c', 'f')):
            continue
        if re.search(r'(?i)bottled water', name):
            continue
        key = (name, vals['cal'], vals['p'], vals['c'], vals['f'])
        nums = (vals['cal'], vals['p'], vals['c'], vals['f'], vals['sodium'], serve_txt)
        if key in seen or section == 'KIDS MENU' and nums in seen:
            continue
        seen.add(nums)
        seen.add(key)
        est = 4 * vals['p'] + 4 * vals['c'] + 9 * vals['f']
        if abs(est - vals['cal']) > vals['cal'] / 3 and abs(est - vals['cal']) > 15:
            dropped.append(name)
            continue
        g = num(serve_txt)
        mt = re.match(r'(.*?)-\s*(\d.*)$', name)          # toppings: "Bacon- 3 half strips"
        if mt:
            name, serve = mt.group(1).strip(), mt.group(2).strip()
            if g:
                serve += f' ({g} g)'
        elif size:
            serve = f'{size}, 50% ice fill' if 'Tea' not in name else size
        elif g:
            serve = f'1 serving ({g} g)'
        else:
            serve = re.sub(r'(\d)oz', r'\1 oz', serve_txt) if serve_txt else '1 serving'
        if any(i['name'] == name for i in items):
            name = f'{name} ({mt.group(2).strip()})' if mt else f'{name} ({section.title()})'
        items.append({
            'name': name, 'cat': category(name, section), 'serve': serve,
            'cal': vals['cal'], 'kj': None, 'p': vals['p'], 'c': vals['c'], 'f': vals['f'],
            'sat': vals['sat'], 'sugar': vals['sugar'], 'fibre': vals['fibre'], 'sodium': vals['sodium'], 'salt': None,
            'contains': contains, 'may': may, 'vg': None, 'meat': meat(name),
        })

    src = (f"Arby's Nutrition & Allergen Information (U.S.), {edition} edition. Allergens are the guide's Contains / May contain "
           f"lists; items marked as made in a facility that handles peanuts or tree nuts have those as may-contain, and fried "
           f"sides cooked in shared oil have the oil's allergens as may-contain, and milk from the buttered buns a few markets use is may-contain. Drinks are with 50% ice fill. Left out: bottled "
           f"water and items the guide repeats in the Kids and Value menus")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-arbys', 'name': "Arby's", 'how': 'Official nutrition and allergen guide (PDF)', 'url': PAGE,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"Arby's: {len(items)} items, {len(dropped)} dropped -> {OUT.name}")


if __name__ == '__main__':
    main()
