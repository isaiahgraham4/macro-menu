#!/usr/bin/env python3
"""El Pollo Loco (US): the Nutrition Guide PDF linked from elpolloloco.com/nutrition, saved as us-epl-source.json.

elpolloloco.com/nutrition/ redirects (meta refresh) to the current guide, so a plain request finds it. The guide gives
serving size (oz), calories, calories from fat, fat, saturated fat, trans fat, cholesterol, sodium, carbs, fibre, sugars and
protein, and marks the nine US major allergens (sesame included) with an X.

Left out: meals with sides (2 pc Breast & Wing Meal ...), bottled water, the Combos and Kids Meals sections (they repeat
entrées listed elsewhere), and rows whose calories are far from 4p + 4c + 9f (more than a third out), counted in `src`.

Run: python3 ios/Scripts/intl/us-epl-fetch.py
"""
import json
import os
import pathlib
import re
import tempfile
import urllib.parse
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-epl-source.json'
# The PDF is a download, kept out of the repo: $PDF_DIR, or the system temp folder
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR') or tempfile.gettempdir())
PAGE = 'https://www.elpolloloco.com/nutrition/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
COLS = [('oz', 258), ('cal', 284), ('calfat', 312), ('f', 340), ('sat', 366), ('trans', 394), ('chol', 419), ('sodium', 443),
        ('c', 471), ('fibre', 500), ('sugar', 525), ('p', 551)]
ALLERGEN_COLS = [(576, ['egg']), (594, ['fish']), (612, ['milk']), (630, ['peanut']), (649, ['sesame']), (667, ['shellfish']),
                 (685, ['soy']), (703, ['treenut']), (721, ['gluten', 'wheat'])]


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def num(s):
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def tidy(name):
    name = re.sub(r'\*+|®|™|TM\b|TM(?=\s|$)', '', name).replace('’', "'")
    name = name.replace('SauceTM', 'Sauce').replace('ChataCoffeeTM', 'ChataCoffee').replace('Cinammon', 'Cinnamon')
    name = re.sub(r'\((\d+)\)', r'(\1 pc)', name)
    name = re.sub(r', (Small|Regular)$', lambda m: f' ({m.group(1).lower()})', name)
    name = name.replace('FUZE', 'Fuze').replace('VitaminWater XXX', 'vitaminwater XXX')
    return re.sub(r'\s+', ' ', name).strip()


def category(section, name):
    n = name.lower()
    if section.startswith('DRINKS'):
        return 'drink'
    if re.search(r'churro|flan|applechata', n):
        return 'sweet'
    if re.search(r'sauce|dressing|ranch|sour cream|^guacamole \(|^queso blanco \(|^gravy|^salsa \w+$|^avocado salsa', n):
        return 'extra'
    if section.startswith('SIDES') or re.search(r'tortilla chips|tortillas \(|chips &|soup', n):
        return 'side'
    return 'main'


def meat(name):
    n = name.lower()
    if 'chicken' in n or re.search(r'pollo bowl|al carb|breast', n):
        return ['chicken']
    return None


def main():
    html = get(PAGE).decode('utf-8', 'replace')
    m = re.search(r'url=(/content/pdfs/[^"\'\s>]+\.pdf)', html)
    if not m:
        raise SystemExit('El Pollo Loco: the nutrition guide link is missing from the page')
    pdf_url = urllib.parse.urljoin(PAGE, m.group(1))
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'us-epl.pdf'
    path.write_bytes(get(pdf_url))
    page = pymupdf.open(path)[0]
    edition = re.search(r'M\d+\s+\d{4}', page.get_text())
    lines = {}
    for w in page.get_text('words'):
        lines.setdefault(round((w[1] + w[3]) / 2 / 3), []).append(w)

    items, seen, dropped = [], set(), []
    section, base, header_seen = '', '', False
    for k in sorted(lines):
        ws = sorted(lines[k], key=lambda w: w[0])
        if any(w[4] == 'Serving' for w in ws):
            header_seen = True
            continue
        if not header_seen:
            continue
        size_w = [w[4] for w in ws if 210 <= w[0] < 250 and w[4] in ('Regular', 'Large', 'Original', 'Bottle')]
        name_w = [w for w in ws if w[0] < 250 and w[4] not in size_w]
        nums = [w for w in ws if 250 <= w[0] < 565 and re.fullmatch(r'[\d.]+', w[4])]
        marks = [(w[0] + w[2]) / 2 for w in ws if w[4] == 'X']
        text = ' '.join(w[4] for w in name_w)
        if len(nums) < 11:
            if name_w and name_w[0][0] < 60 and re.fullmatch(r"[A-Z0-9 &()\-’'Ée]+", text.replace('Entree', 'ENTREE').replace('Entrée', 'ENTREE').replace('Only', 'ONLY').replace('without', 'WITHOUT').replace('ice', 'ICE').replace('Small', 'SMALL')):
                section = text.upper()
            elif name_w and name_w[0][0] >= 60 and items and not size_w:
                # the second line of a wrapped drink name ("Minute Maid Aguas Frescas / Mango Lime")
                base = f'{base} {text}'
                items[-1]['name'] = tidy(f"{base} ({items[-1]['serve'].split(' (')[0]})")
            if text.startswith('*Dressing'):
                break
            continue
        if name_w:
            base = text
        if section.startswith(('FIRE-GRILLED COMBOS', 'KIDS MEALS')):
            continue
        if re.search(r'\bMeal\b|Bottled Water', base):
            continue
        cols = {min(COLS, key=lambda c: abs(c[1] - w[0]))[0]: w[4] for w in nums}
        v = {c: num(cols.get(c, '')) for c, _ in COLS}
        if v['cal'] is None or any(v[c] is None for c in ('p', 'c', 'f')):
            continue
        size = ' '.join(size_w).lower()
        name = tidy(base)
        cat = category(section, name)
        if size and size != 'bottle':
            name = f'{name} ({size})'
        elif section.startswith('SIDES') and cat == 'side' and '(' not in name:
            name = f'{name} (small)'
        contains = sorted({a for x in marks for a in min(ALLERGEN_COLS, key=lambda c: abs(c[0] - x))[1]})
        key = (name, v['cal'], v['p'], v['c'], v['f'])
        if key in seen:
            continue
        seen.add(key)
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15:
            dropped.append(name)
            continue
        serve = f"{size or '1 serving'} ({v['oz']} oz)"
        if '*' in base and 'Dressing' not in base and 'Salad' in base:
            serve += ', dressing not included'
        if '***' in base:
            serve += ', limited locations'
        elif '**' in base:
            serve += ', Texas and Louisiana only'
        items.append({
            'name': name, 'cat': cat, 'serve': serve, 'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
            'sat': v['sat'], 'sugar': v['sugar'], 'fibre': v['fibre'], 'sodium': v['sodium'], 'salt': None,
            'contains': contains, 'may': None, 'vg': None, 'meat': meat(name),
        })

    src = (f"El Pollo Loco Nutrition Guide ({edition.group(0) if edition else 'current'} edition). Allergens are the guide's X "
           f"marks. Drinks are without ice. Salads are without dressing (dressings are listed on their own). Left out: meals "
           f"with sides, bottled water, and the Combos and Kids Meals sections, which repeat entrées listed elsewhere")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-epl', 'name': 'El Pollo Loco', 'how': 'Official nutrition and allergen guide (PDF)', 'url': PAGE,
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'El Pollo Loco: {len(items)} items, {len(dropped)} dropped -> {OUT.name}')


if __name__ == '__main__':
    main()
