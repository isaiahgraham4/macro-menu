#!/usr/bin/env python3
"""Subway Canada: downloads the Canada Nutrition Information PDF linked from subway.com/en-CA/MenuNutrition/Nutrition and writes
ca-sub-source.json beside this file.

Each row in the PDF is a name followed by 13 figures (serving g, calories, fat, sat fat, trans fat, cholesterol, sodium, carbs,
fibre, sugars, protein, calcium %DV, iron %DV); the section heading above it (6" Classics Subs, Classics Wraps, Salads, ...) says
what kind of item it is. Subs are per 6-inch (Subway says to double for a footlong; footlongs aren't printed, so not added).

Subway Canada's allergen chart lists ingredients (breads, meats, sauces), not finished subs, so allergens are left out.

Run: python3 ios/Scripts/intl/ca-sub-fetch.py
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
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'subca'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
PAGE = 'https://www.subway.com/en-CA/MenuNutrition/Nutrition'
NUM = re.compile(r'^\d+(\.\d+)?$')

# section heading -> (category, how the name is written, serve); None = not a menu item (bread, vegetables, seasonings, proteins)
SECTIONS = {
    '6" Steak Subs': ('main', '{} (6-inch)', '6-inch sub'),
    '6" Chicken Subs': ('main', '{} (6-inch)', '6-inch sub'),
    '6" Classics Subs': ('main', '{} (6-inch)', '6-inch sub'),
    '6" Deli Subs': ('main', '{} (6-inch)', '6-inch sub'),
    '6" Veggie Subs': ('main', '{} (6-inch)', '6-inch sub'),
    '6" Fresh Fit': ('main', '{} Fresh Fit (6-inch)', '6-inch sub'),
    'Snackwiches': ('main', '{} Snackwich', '1 snackwich'),
    'Classics Wraps': ('main', '{} Wrap', '1 wrap'),
    'SALADS': ('main', '{} Salad', '1 salad, no dressing'),
    '6" Limited Time Offer/Regional Salads**': ('main', '{} Salad', '1 salad, no dressing'),
    'Power Bowls': ('main', '{} Power Bowl', '1 bowl'),
    '6" Breakfast Sandwiches': ('breakfast', '{} Breakfast Sub (6-inch)', '6-inch sub'),
    'Breakfast Wraps': ('breakfast', '{} Breakfast Wrap', '1 wrap'),
    'Breakfast Ciabatta': ('breakfast', '{} Breakfast Ciabatta', '1 ciabatta'),
    'Sandwich Condiments & Add ons': ('extra', '{}', 'amount on a 6-inch sub'),
    'Cookies & Desserts': ('sweet', '{}', '1 cookie'),
    'Sides': ('side', '{}', '1 serving'),
}
SKIP = ('Breads', 'Seasonings', 'Vegetables', 'Cheese', 'Individual Proteins', 'Soup')


def fetch(url):
    time.sleep(0.3)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': '*/*', 'Accept-Language': 'en-CA,en;q=0.9'}), timeout=60) as r:
        return r.read()


def pdf_url():
    html = fetch(PAGE).decode('utf-8', 'replace')
    return re.findall(r'href="(https://media\.subway\.com/[^"]+CAN_Nutrition_ENG[^"]+\.pdf)"', html)[0]


def tidy(name):
    name = re.sub(r'[®™]|\*+|\s+1\b', '', name).strip()
    name = name.replace('Tuna (includes Mayonnaise)', 'Tuna').replace('Sweet Onion chicken', 'Sweet Onion Chicken')
    name = name.replace('Mini Cookie, Chocolate Chip with M&M Candies Cook', 'Mini Cookie, Chocolate Chip with M&M Candies')
    name = name.replace('Mini Cookie, White Chip Macadamia Nut Cookie', 'Mini Cookie, White Chip Macadamia Nut')
    m = re.match(r'^Mini Cookie, (.*)$', name)
    if m:
        name = f'{m.group(1)} Mini Cookie'
    return re.sub(r'\s+', ' ', name)


def meat_of(name):
    n = name.lower()
    out = []
    for words, m in ((('chicken',), 'chicken'), (('steak', 'brisket'), 'beef'), (('ham', 'bacon', 'b.l.t', 'blt', 'sausage', 'b.m.t', 'pizza'), 'pork'),
                     (('tuna',), 'fish'), (('turkey', 'great canadian club'), 'turkey')):
        if any(w in n for w in words) and m not in out:
            out.append(m)
    return out or None


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    url = pdf_url()
    path = PDFS / url.rsplit('/', 1)[1]
    path.write_bytes(fetch(url))
    doc = pymupdf.open(path)
    edition = next((l for l in doc[0].get_text().split('\n') if re.match(r'^[A-Z][a-z]+ 20\d\d$', l.strip())), '').strip()
    ls = [l.strip() for p in doc for l in p.get_text().split('\n') if l.strip()]
    items, dropped, section, j = [], [], None, 0
    while j < len(ls):
        if j + 13 < len(ls) and not NUM.match(ls[j]) and all(NUM.match(x) for x in ls[j + 1:j + 14]):
            g, cal, fat, sat, trans, chol, na, carb, fibre, sugar, prot = (float(x) for x in ls[j + 1:j + 12])
            j += 14
            spec = SECTIONS.get(section)
            if not spec:
                continue
            cat, fmt, serve = spec
            name = fmt.format(tidy(ls[j - 14]))
            if cal > 20 and abs(4 * prot + 4 * carb + 9 * fat - cal) > cal / 3:
                dropped.append(name)
                continue
            num = lambda v: int(v) if v == int(v) else v
            if '(4 oz)' in name:
                serve = '1 serving'
            name = name.replace('Potato Rings (4)', 'Potato Rings (4 pieces)')
            items.append({
                'name': name, 'cat': cat, 'serve': f'{serve} ({num(g)} g)',
                'cal': num(cal), 'kj': None, 'p': num(prot), 'c': num(carb), 'f': num(fat),
                'sat': num(sat), 'sugar': num(sugar), 'fibre': num(fibre), 'sodium': num(na), 'salt': None,
                'contains': None, 'may': None,
                'vg': None, 'meat': meat_of(name) if cat in ('main', 'breakfast') else None,
            })
        else:
            if ls[j] in SECTIONS or ls[j].startswith(SKIP):
                section = ls[j]
            j += 1
    src = (f'Subway Canada Nutrition Information PDF ({edition or "edition not printed"}), linked from subway.com/en-CA. '
           'Subs are per 6-inch; salads without dressing. Left out: breads, single vegetables, cheeses, seasonings, '
           'individual proteins and soups' + (f', and {len(dropped)} rows whose energy does not add up ({"; ".join(dropped)})' if dropped else '')
           + '. No allergens: the Canadian allergen chart covers ingredients, not finished items.')
    out = {'chain': 'ca-sub', 'name': 'Subway', 'how': 'Official nutrition guide (PDF)', 'url': PAGE, 'src': src,
           'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items}
    (HERE / 'ca-sub-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'ca-sub: {len(items)} items, dropped {dropped}')


if __name__ == '__main__':
    main()
