#!/usr/bin/env python3
"""Simply Asia (South Africa) -> za-simplyasia-source.json (normalised format, see SOURCE-FORMAT.md).

Source: the allergen and nutrition schedule linked from simplyasia.co.za/our-menu/ ("Allergens-Menu-2024.pdf", headed
"SIMPLY ASIA MENU AUGUST 2024"). One row per dish as served: energy (kcal), protein, carbohydrate, fat, fibre, sodium,
then YES marks under each allergen (gluten, wheat, dairy, soya, egg, fish, shellfish, peanuts, tree nuts, sesame,
sulphur dioxide and more). The list covers the major allergens including sesame, so allergens are carried.

Left out: the "Rice to ..." and "NO VEG" rows (they are changes to a dish, not dishes), the 6-piece combo platter, plain
vegetable ingredients, and rows whose energy is far (more than a third) from 4p + 4c + 9f. Sodium figures over 8,000 mg
for a single dish are misprints in the schedule and are left blank. "-" in a macro column is read as 0.

Run: python3 ios/Scripts/intl/za-simplyasia-fetch.py   (needs pymupdf)
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
OUT = HERE / 'za-simplyasia-source.json'
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir()))
PDF_URL = 'https://simplyasia.co.za/wp-content/uploads/Allergens-Menu-2024.pdf'
PAGE_URL = 'https://simplyasia.co.za/our-menu/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

ALLERGENS = {'Gluten': 'gluten', 'Wheat': 'wheat', 'Dairy': 'milk', 'Soya': 'soy', 'Egg': 'egg', 'Fish': 'fish',
             'Shellfish': 'shellfish', 'Peanuts': 'peanut', 'Tree nuts': 'treenut', 'Sesame Seeds': 'sesame',
             'sulphur dioxide': 'sulphites'}

# rows without a menu number that are worth keeping: first column -> (name, cat, serve)
EXTRAS = {
    'Beef': ('Extra Beef (with sauce)', 'extra', '1 portion'),
    'Calamari': ('Extra Calamari (with sauce)', 'extra', '1 portion'),
    'Chicken': ('Extra Chicken (with sauce)', 'extra', '1 portion'),
    'Crumbed Chicken': ('Extra Crumbed Chicken (with sauce)', 'extra', '1 portion'),
    'Duck': ('Extra Duck (with sauce)', 'extra', '1 portion'),
    'Egg': ('Extra Egg', 'extra', '1 egg'),
    'Extra Gravy': ('Extra Gravy Sauce', 'extra', '1 portion'),
    'Extra Roasted Chicken': ('Extra Roasted Chicken', 'extra', '1 portion'),
    'Flavoured Soya Sauce': ('Flavoured Soya Sauce', 'extra', '1 portion'),
    'Green Curry Sauce': ('Green Curry Sauce', 'extra', '1 portion'),
    'Vegetarian Green Curry Sauce': ('Vegetarian Green Curry Sauce', 'extra', '1 portion'),
    'Red Curry Sauce': ('Red Curry Sauce', 'extra', '1 portion'),
    'Mee Yok Sauce': ('Mee Yok Sauce', 'extra', '1 portion'),
    'Stirfry Sauce': ('Stir-Fry Sauce', 'extra', '1 portion'),
    'Vegetarian Stirfry Sauce': ('Vegetarian Stir-Fry Sauce', 'extra', '1 portion'),
    'Plum Sauce T25': ('Plum Sauce (dip)', 'extra', '1 tub'),
    'Satay Sauce T25': ('Satay Sauce (dip)', 'extra', '1 tub'),
    'Sweet Chilli T25': ('Sweet Chilli Sauce (dip)', 'extra', '1 tub'),
    'Thai Atchar': ('Thai Atchar', 'extra', '1 portion'),
    'Prawn Each': ('Extra Prawn (each, with sauce)', 'extra', '1 prawn'),
    'Prawns': ('Extra Prawns (with sauce)', 'extra', '1 portion'),
    'Seafood': ('Extra Seafood (with sauce)', 'extra', '1 portion'),
    'Tofu': ('Extra Tofu', 'extra', '1 portion'),
    'Cashew Nuts': ('Extra Cashew Nuts', 'extra', '1 portion'),
    'Scoop of Ice Cream': ('Scoop of Ice Cream', 'sweet', '1 scoop'),
    'Linguine Noodles': ('Linguine Noodles (side)', 'side', '1 portion'),
    'Rice Noodle Small': ('Small Rice Noodles (side)', 'side', '1 portion'),
    'Rice Noodles Big': ('Large Rice Noodles (side)', 'side', '1 portion'),
    'Yellow Noodles': ('Yellow Noodles (side)', 'side', '1 portion'),
    'Mung Bean Noodle': ('Mung Bean Noodles (side)', 'side', '1 portion'),
}
SKIP_CODES = {'113', 'WON2'}  # 6-piece combo platter; second Kyogrob row (a double portion with no label)


def download():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'simplyasia-allergens-menu.pdf'
    req = urllib.request.Request(PDF_URL, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        path.write_bytes(r.read())
    time.sleep(0.3)
    return path


def num(v):
    v = (v or '').replace(',', '').strip()
    if v in ('-', '–', ''):
        return 0.0
    return float(v) if re.fullmatch(r'\d+(\.\d+)?', v) else None


def energy_ok(cal, p, c, f):
    est = 4 * p + 4 * c + 9 * f
    if est < 10 and cal < 10:
        return True
    return abs(cal - est) <= est / 3


MEAT_WORDS = [(r'\bchicken\b', 'chicken'), (r'\bbeef\b', 'beef'), (r'\b(prawns?|seafood|calamari)\b', 'seafood'),
              (r'\bfish\b', 'fish'), (r'\bpork\b', 'pork')]


PROTEIN_CHOICE = {'Chicken': ['chicken'], 'Beef': ['beef'], 'Duck': None, 'Prawn': ['seafood'], 'Seafood': ['seafood'],
                  'Tofu': None, 'Vegetarian': None, 'Vegetable': None, 'Vegetables': None}


def meats(name):
    # most dishes end with the protein chosen ("Tom Yum Prawn Linguine Tofu"): go by that word
    last = re.sub(r' \(half\)$', '', name).split()[-1]
    if last in PROTEIN_CHOICE:
        return PROTEIN_CHOICE[last]
    found = []
    for pat, m in MEAT_WORDS:
        if re.search(pat, name, re.I) and m not in found:
            found.append(m)
    return found or None


def category(code):
    m = re.match(r'(\d+)', code)
    n = int(m.group(1)) if m else 0
    if 100 <= n < 200 or n in (201, 202):
        return 'side'
    if 224 <= n <= 231:
        return 'side'
    if 900 <= n < 1000:
        return 'sweet'
    return 'main'


def main():
    pdf = download()
    doc = pymupdf.open(pdf)
    items, dropped, seen = [], [], set()
    for page in doc:
        for table in page.find_tables().tables:
            rows = table.extract()
            header = None
            for r in rows:
                if r and r[2] == 'Energy (kcal)':
                    header = [(h or '').replace('\n', ' ').strip() for h in r]
                    continue
                if header is None or not r[0] or not r[1] or not r[2]:
                    continue
                code = r[0].replace('\n', ' ').strip()
                desc = r[1].replace('\n', ' ').strip()
                if code in SKIP_CODES or desc.startswith('Rice to') or 'NO VEG' in desc or 'Change' in desc or 'No Charge' in desc:
                    continue
                has_number = bool(re.match(r'\d', code))
                if not has_number and code not in EXTRAS:
                    continue  # plain vegetable ingredients
                cal, p, c, f, fibre, sodium = (num(x) for x in r[2:8])
                if None in (cal, p, c, f):
                    dropped.append(f'{desc} (unreadable figures)')
                    continue
                if has_number:
                    name = re.sub(r' Half$', ' (half)', desc)
                    cat, serve = category(code), ('half portion' if desc.endswith(' Half') else '1 portion')
                else:
                    name, cat, serve = EXTRAS[code]
                if not energy_ok(cal, p, c, f):
                    dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
                    continue
                if name in seen:
                    continue
                seen.add(name)
                contains = []
                for h, v in zip(header[8:], r[8:]):
                    key = ALLERGENS.get(h)
                    if key and (v or '').strip().upper() == 'YES' and key not in contains:
                        contains.append(key)
                if sodium is not None and sodium > 8000:
                    sodium = None
                items.append({
                    'name': name, 'cat': cat, 'serve': serve,
                    'cal': int(cal + 0.5), 'kj': None, 'p': p, 'c': c, 'f': f,
                    'sat': None, 'sugar': None, 'fibre': fibre,
                    'sodium': sodium, 'salt': None,
                    'contains': contains, 'may': None,
                    'vg': None, 'meat': meats(name),
                })
    src = ("Simply Asia allergen and nutrition schedule (Allergens-Menu-2024.pdf, dated August 2024), per dish as served. "
           "Calories as published; kilojoules are worked out. Allergens as marked in the schedule (it covers sesame). "
           "Changes to a dish (\"Rice to ...\", \"NO VEG\"), plain vegetable ingredients and the 6-piece combo platter are left out; "
           "sodium over 8,000 mg for one dish is a misprint and left blank. "
           f"Left out {len(dropped)} row(s) whose calories don't match their macros" + (': ' + '; '.join(dropped) if dropped else '') + '.')
    out = {
        'chain': 'za-simplyasia', 'name': 'Simply Asia', 'how': 'Official allergen and nutrition schedule (PDF)',
        'url': PAGE_URL, 'src': src, 'checked': date.today().isoformat(),
        'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Simply Asia: {len(items)} items -> {OUT.name}; dropped {len(dropped)}')


if __name__ == '__main__':
    main()
