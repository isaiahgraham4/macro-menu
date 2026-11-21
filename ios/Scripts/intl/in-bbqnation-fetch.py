#!/usr/bin/env python3
"""Barbeque Nation (India) -> in-bbqnation-source.json (normalised format, see SOURCE-FORMAT.md).

Source: "Nutritive value of served food items", the PDF linked from barbequenation.com
(barbequenation.com/documents/nutrition-information.pdf, "effective from 30th August, 2025"). One row per dish with its
serving size (mostly per 100 g, as the buffet is self-served), energy (kcal), protein, fat, saturated fat, carbohydrate,
sugars, fibre and sodium. It covers the buffet, UBQ (Barbeque Nation's delivery menu) and the monthly food festivals.

Left out: cocktails (alcohol); meals, mini meals and platters (combos); repeated dishes (an item marked NEW replaces the
older row of the same name); rows whose energy is far (more than a third) from 4p + 4c + 9f.
Allergens are not carried: the list follows India's FSSAI set, which has no sesame.
No beef or pork on the menu; "mutton" is goat. Dishes before the menu's NON VEGETARIAN heading (and in the delivery VEG
list) are marked vegetarian, as the menu groups them.

Run: python3 ios/Scripts/intl/in-bbqnation-fetch.py   (needs pymupdf)
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
OUT = HERE / 'in-bbqnation-source.json'
PDF_DIR = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir()))
PDF_URL = 'https://www.barbequenation.com/documents/nutrition-information.pdf'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

SWEET = re.compile(r'KULFI|HALWA|GULAB JAMUN|KHEER|PAYASAM|PAYSAM|PRADAMAN|PHIRNI|PHIRNEE|PASTRY|BROWNIE|CAKE|PUDDING|MOUSSE|'
                   r'CUSTARD|TART\b|TRUFFLE|GATEAU|JALEBI|RABDI|MALPUVA|CHURMA|SHAHI TUKDA|MELKTERT|ICE CREAM|CUT MANGO|'
                   r'RAS BHARE MOTI|CHOCOLATE BALL|THIAKRY|MAWA|SHRIKHAND|RASMALAI|LADDU|BARFI|DESSERT')
DRINK = re.compile(r'MOCKTAIL|SHAKE|LASSI|\bCHAI\b|ICED TEA|COOLER|CHAAS|SHARBAT|SHARABAT|AAM PANNA|JALJEERA|LIME\b|SATTU DRINK|'
                   r'REFRESHER|BLUE LAGOON|SHIRLEY TEMPLE|COFFEE|BUTTERMILK')
EXTRA = re.compile(r'CHUTNEY|PICKLE|\bDIP\b|SALSA|RAITA|LAUNGI')
SIDE = re.compile(r'\bROTI\b|NAAN|STEAM RICE|JEERA RICE|PARATHA|PAROTHA|\bPURI\b|LUCHI|SALAD|PAPAD|KACHUMBER|PULAO')
COMBO = re.compile(r'\bMEALS?\b|PLATTER|COMBO|THALI')
ALCOHOL = re.compile(r'\(COCKTAIL\)|\bBEER\b|\bWINE\b|WHISKY|VODKA|SANGRIA|MARTINI|MARGARITA|DAIQUIRI')
MEAT_WORDS = [(r'CHICKEN|MURGH|KUKKAD|TANGDI|WINGS', 'chicken'), (r'MUTTON|GOSHT|RAAN|LAL MASS|KALEJI|NIHARI|NIHAARI', 'lamb'),
              (r'FISH|MAACH|ANCHOVI|SEER|BANGRA|PATURI|AMRITSARI', 'fish'),
              (r'PRAWN|JHINGA|SHRIMP|CRAB|LOBSTER|CALAMARI|OCTOPUS', 'seafood')]


def download():
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / 'barbequenation-nutrition-information.pdf'
    req = urllib.request.Request(PDF_URL, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=90) as r:
        path.write_bytes(r.read())
    time.sleep(0.3)
    return path


def num(v, dash=None):
    v = (v or '').replace(',', '').replace('\n', ' ').strip()
    if v in ('-', '_', '–', 'NA', 'N/A', ''):
        return dash
    return float(v) if re.fullmatch(r'\d+(\.\d+)?', v) else None


def energy_ok(cal, p, c, f):
    est = 4 * p + 4 * c + 9 * f
    if est < 10 and cal < 10:
        return True
    return abs(cal - est) <= est / 3


def nice(name):
    name = re.sub(r'\s+', ' ', name).strip()
    name = re.sub(r'\s*\((MOCKTAILS?)\)', '', name, flags=re.I)
    t = name.title()
    t = re.sub(r"'S\b", "'s", t)
    t = t.replace(' - Ubq', ' (UBQ delivery)').replace('Ubq ', 'UBQ ').replace('(With ', '(with ')
    t = re.sub(r'\bBbq\b', 'BBQ', t)
    return t


def serve_text(s):
    s = re.sub(r'\s+', ' ', (s or '').replace('\n', ' ')).strip()
    s = re.sub(r'\bG\b', 'g', s).replace('grams', 'g').replace('GLASS', 'glass').replace('STICK', 'stick')
    s = re.sub(r'\(\s+', '(', s).lower()
    return s or '1 serving'


def meats(raw):
    found = [m for pat, m in MEAT_WORDS if re.search(pat, raw)]
    if re.search(r'\bEGG\b|DIMER', raw) and not found:
        return None  # egg dishes: no meat
    return found or None


def main():
    doc = pymupdf.open(download())
    items, by_name, dropped, combos, alcohol, repeats = [], {}, [], 0, 0, 0
    veg_zone = True      # until the NON VEGETARIAN heading
    section = ''
    for page in doc:
        for table in page.find_tables().tables:
            rows = table.extract()
            cols = None
            for r in rows:
                cells = [(c or '').replace('\n', ' ').strip() for c in r]
                if cells and cells[0].startswith('S.No'):
                    cols = {h: i for i, h in enumerate(cells)}
                    continue
                if cols is None:
                    continue
                name_raw = cells[cols['FOOD ITEMS*']]
                cal = num(cells[cols['ENERGY [kcal]**']])
                if cal is None:
                    # a heading row
                    head = ' '.join(c for c in cells[:2] if c).upper()
                    if head:
                        section = head
                        if head.startswith('NON VEGETARIAN') or head.startswith('NON VEG'):
                            veg_zone = False
                        if head == 'VEG':
                            veg_zone = True
                    continue
                if not name_raw:
                    continue
                raw = re.sub(r'\s+', ' ', name_raw).upper()
                if ALCOHOL.search(raw):
                    alcohol += 1
                    continue
                if COMBO.search(raw):
                    combos += 1
                    continue
                p = num(cells[cols['PROTEIN [g]']], 0.0)
                f = num(cells[cols['FAT [g]']], 0.0)
                c = num(cells[cols['CARBOHYD RATE [g]']], 0.0)
                serve = serve_text(cells[cols['SERVING SIZE']])
                is_new = bool(re.search(r'\bNEW$', raw))
                raw = re.sub(r'\s+NEW$', '', raw)
                name = nice(raw)
                if None in (p, c, f):
                    dropped.append(f'{name} (unreadable figures)')
                    continue
                if not energy_ok(cal, p, c, f):
                    dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
                    continue
                if 'ml' in serve.lower() or DRINK.search(raw) or 'BEVERAGE' in section:
                    cat = 'drink'
                elif 'DESSERT' in section or SWEET.search(raw):
                    cat = 'sweet'
                elif EXTRA.search(raw):
                    cat = 'extra'
                elif SIDE.search(raw) or 'BREADS' in section:
                    cat = 'side'
                else:
                    cat = 'main'
                item = {
                    'name': name, 'cat': cat, 'serve': serve,
                    'cal': int(cal + 0.5), 'kj': None, 'p': p, 'c': c, 'f': f,
                    'sat': num(cells[cols['SATURATED FAT[g]']]), 'sugar': num(cells[cols['TOTAL SUGAR [g]']]),
                    'fibre': num(cells[cols['TOTAL DIETARY FIBRE [g]']]),
                    'sodium': num(cells[cols['SODIUM [mg]']]), 'salt': None,
                    'contains': None, 'may': None,
                    'vg': 'vegetarian' if veg_zone and cat != 'drink' and not meats(raw) and not re.search(r'\bEGG\b', raw) else None,
                    'meat': meats(raw),
                }
                if name in by_name:
                    repeats += 1
                    if is_new:
                        items[by_name[name]] = item
                    continue
                by_name[name] = len(items)
                items.append(item)
    src = ("Barbeque Nation \"Nutritive value of served food items\" (barbequenation.com/documents/nutrition-information.pdf, "
           "effective 30 August 2025), mostly per 100 g as served from the buffet; also UBQ delivery dishes and monthly festival "
           "dishes. Calories as published; kilojoules are worked out. No allergens: the list has no sesame. No beef or pork; "
           "mutton is goat. Dishes the menu lists under VEGETARIAN are marked vegetarian. "
           f"Left out {alcohol} cocktails, {combos} meals/mini meals/platters, {repeats} repeated rows (the NEW version kept), "
           f"and {len(dropped)} row(s) whose calories don't match their macros"
           + (': ' + '; '.join(dropped) if len(dropped) <= 10 else
              ', mostly the soya chaap dishes and the chicken tangdi (drumstick) dishes, whose calories run 60-80% above '
              'their macros') + '.')
    out = {
        'chain': 'in-bbqnation', 'name': 'Barbeque Nation', 'how': 'Official nutrition information (PDF)',
        'url': PDF_URL, 'src': src, 'checked': date.today().isoformat(),
        'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Barbeque Nation: {len(items)} items -> {OUT.name}; cocktails {alcohol}, combos {combos}, repeats {repeats}, dropped {len(dropped)}')


if __name__ == '__main__':
    main()
