#!/usr/bin/env python3
"""Mary Brown's Chicken (Canada): downloads the "Allergen and Nutritionals" PDF linked from marybrowns.com/menu/ and writes
ca-marybrowns-source.json beside this file.

Each row is a name, a serving description, then 11 figures (g, calories, fat, sat fat, trans fat, cholesterol, sodium, carbs,
fibre, sugar, protein). Rows printed "per serving" of a box that holds 2 or more servings (large sides, 4- to 27-piece
buckets) are left out: they give a share, not what the box holds.

Mary Brown's allergen chart groups items differently from the nutrition table (e.g. "Chicken Pieces (Regular and Spicy)"),
so allergens are left out rather than guessed.

Run: python3 ios/Scripts/intl/ca-marybrowns-fetch.py
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
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'mbca'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
MENU = 'https://marybrowns.com/menu/'
NUM = re.compile(r'^\d+(\.\d+)?$')
SECTIONS = {'SIDES': 'side', 'CHICKEN': 'main', 'SANDWICHES & EXTRAS': 'main', 'SNACK MENU': 'main', 'SAUCES': 'extra', 'DESSERTS': 'sweet'}


def fetch(url):
    time.sleep(0.3)
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': '*/*', 'Accept-Language': 'en-CA,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def pdf_url():
    html = fetch(MENU).decode('utf-8', 'replace')
    m = re.search(r'href="([^"]+\.pdf)"[^>]*>\s*Nutritional Information', html)
    return m.group(1)


def tidy(name, section):
    name = re.sub(r'\s+', ' ', name).strip()
    m = re.match(r'^(\d+) PC: (.*)$', name)
    if m:
        n, rest = m.groups()
        if 'Tenders' in rest:
            return f'{rest} ({n} pc)'
        return f'{n} Piece Chicken ({rest})'
    if section == 'CHICKEN':
        return f'Chicken {name}'
    name = re.sub(r'\((Small|Medium|Large|Regular|Individual|Kids)\)', lambda m: f'({m.group(1).lower()})', name)
    if section == 'SAUCES' and not re.search(r'(?i)sauce|ketchup|vinegar|mayo|ranch', name):
        name += ' Sauce'
    if name == 'Apple Pies':
        return 'Apple Pie'
    return name


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    url = pdf_url()
    path = PDFS / url.rsplit('/', 1)[1]
    path.write_bytes(fetch(url))
    doc = pymupdf.open(path)
    ls = [l.strip() for p in doc for l in p.get_text().split('\n') if l.strip()]
    items, dropped, shares, section, j = [], [], [], None, 0
    while j < len(ls):
        if j + 12 < len(ls) and not NUM.match(ls[j]) and not NUM.match(ls[j + 1]) and all(NUM.match(x) for x in ls[j + 2:j + 13]):
            raw, serving = ls[j], ls[j + 1]
            g, cal, fat, sat, trans, chol, na, carb, fibre, sugar, prot = (float(x) for x in ls[j + 2:j + 13])
            j += 13
            name = tidy(raw, section)
            if re.match(r'^([2-9]|\d\d) servings$', serving):
                shares.append(name)
                continue
            if cal > 20 and (abs(4 * prot + 4 * carb + 9 * fat - cal) > cal / 3 or sat > fat + 0.5):
                dropped.append(name)
                continue
            cat = SECTIONS.get(section, 'main')
            if name.startswith('Gravy'):
                cat = 'extra'
            elif 'Pop-ins' in name or 'Pulled Chicken' in name:
                cat = 'main'
            num = lambda v: int(v) if v == int(v) else round(v, 2)
            meat = ['chicken'] if cat == 'main' and section != 'SIDES' or 'Chicken' in name or 'Pop-ins' in name else None
            items.append({
                'name': name, 'cat': cat, 'serve': f'{serving} ({num(g)} g)',
                'cal': num(cal), 'kj': None, 'p': num(prot), 'c': num(carb), 'f': num(fat),
                'sat': num(sat), 'sugar': num(sugar), 'fibre': num(fibre), 'sodium': num(na), 'salt': None,
                'contains': None, 'may': None, 'vg': None, 'meat': meat,
            })
        else:
            if ls[j] in SECTIONS:
                section = ls[j]
            j += 1
    month = re.search(r'(January|February|March|April|May|June|July|August|September|October|November|December)-(\d{4})', url, re.I)
    src = (f"Mary Brown's Allergen and Nutritionals PDF ({month.group(1).title() + ' ' + month.group(2) if month else 'undated'}), "
           f'linked from marybrowns.com/menu. Left out: {len(shares)} rows printed per share of a multi-serving box '
           f'(large sides and 4- to 27-piece buckets)'
           + (f', and {len(dropped)} rows whose figures do not add up ({"; ".join(dropped)})' if dropped else '')
           + ". No allergens: the allergen chart groups items differently from the nutrition table.")
    out = {'chain': 'ca-marybrowns', 'name': "Mary Brown's Chicken", 'how': 'Official nutrition guide (PDF)', 'url': MENU,
           'src': src, 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items}
    (HERE / 'ca-marybrowns-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'ca-marybrowns: {len(items)} items, shares {len(shares)}, dropped {dropped}')


if __name__ == '__main__':
    main()
