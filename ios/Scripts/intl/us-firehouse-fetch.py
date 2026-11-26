#!/usr/bin/env python3
"""Firehouse Subs (US): the Interactive Nutrition Menu in the Nutrition Portal that firehousesubs.com links, saved as
us-firehouse-source.json.

firehousesubs.com's menu pages link "For additional nutrition information" to nutritionix.com/firehouse-subs/portal, the
chain's Nutrition Portal hosted by Nutritionix. Its Interactive Nutrition Menu (nutritionix.com/firehouse-subs/menu/premium) is
one server-rendered table with a "Last Updated" date and, for every item, calories, fat, saturated fat, trans fat, cholesterol,
sodium, carbs, fibre, sugars, added sugars and protein, rounded the FDA way. "<1 g" is saved as 1.

Allergens are null: the portal's allergen tool only lists items free of the allergens you tick, behind an agreement to its
allergen notice, and gives no per-item list.

Left out: catering platters and boxed lunches (multi-serve or meal bundles), the Kid's Subs and kids' drinks, the sub-builder
rows (breads, meats, cheeses, toppings and condiments listed per sub size, not menu items), the 12 oz kids' cup, the Freestyle
flavour-shot drinks and flavoured Dasani waters (only the core fountain drinks are kept, one row per cup size), and rows whose
calories are more than a third away from 4p + 4c + 9f, which are counted in `src`.

Run: python3 ios/Scripts/intl/us-firehouse-fetch.py
"""
import html
import json
import pathlib
import re
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-firehouse-source.json'
SITE = 'https://www.firehousesubs.com/menu'
PORTAL = 'https://www.nutritionix.com/firehouse-subs/portal'
INM = 'https://www.nutritionix.com/firehouse-subs/menu/premium'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'

COLS = ['cal', 'f', 'sat', 'trans', 'chol', 'sodium', 'c', 'fibre', 'sugar', 'added', 'p']
KEEP = {'Hot Specialty Subs': 'main', 'Single Meat Subs': 'main', 'Cold Subs': 'main', 'Chopped Salads': 'main', 'Soups': 'side',
        'Sides & Chips': 'side', 'Salad Add-On Toppings': 'extra', 'Salad Dressings': 'extra'}
DRINK_SIZES = ('22 oz', '32 oz', '44 oz')
CORE_DRINKS = ['Coca-Cola', 'Diet Coke', 'Coke Zero', 'Caffeine Free Diet Coke', 'Sprite', 'Sprite Zero', "Barq's Root Beer",
               "Diet Barq's Root Beer", "Seagram's Ginger Ale", "Diet Seagram's Ginger Ale", 'Fanta Orange', 'Fanta Zero Orange',
               'Hi-C Fruit Punch', 'POWERade Fruit Punch', 'POWERade Zero Fruit Punch', 'Mello Yello', 'Mello Yello Zero',
               'Pibb Xtra', 'Pibb Zero', 'Minute Maid Lemonade', 'Minute Maid Light Lemonade', 'Minute Maid Pink Lemonade',
               'FUZE Sweet Tea', 'FUZE Unsweetened Tea', 'Sweet Tea', 'Unsweet Tea', 'Cherry Lime-Aid', 'Cherry Lime-Aid Zero Sugar']
# signature subs whose names don't say the meat (Firehouse's menu descriptions)
SUB_MEATS = {'Hook & Ladder': ['turkey', 'pork'], 'Engineer': ['turkey'], 'Hero': ['beef', 'turkey', 'pork'],
             'New York Steamer': ['beef'], 'Club on a Sub': ['turkey', 'pork', 'beef'], 'Italian': ['pork'],
             'Corned Beef': ['beef'], 'Pastrami': ['beef']}
MEATS = [('chicken', 'chicken'), ('turkey', 'turkey'), ('ham', 'pork'), ('bacon', 'pork'), ('salami', 'pork'), ('pork', 'pork'),
         ('beef', 'beef'), ('brisket', 'beef'), ('steak', 'beef'), ('prime rib', 'beef'), ('tuna', 'fish')]


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read().decode('utf-8', 'replace')


def site_links_portal():
    """The portal must still be the one firehousesubs.com links: its address is in the site's main script."""
    page = get(SITE)
    m = re.search(r'src="(/_expo/static/js/web/entry-[^"]+\.js)"', page)
    if not m or 'nutritionix.com/firehouse-subs/portal' not in get('https://www.firehousesubs.com' + m.group(1)):
        raise SystemExit('Firehouse Subs: firehousesubs.com no longer links the Nutritionix portal; check the menu pages')


def num(s):
    s = html.unescape(re.sub(r'<[^>]+>', '', s)).replace(',', '').replace('<', '').strip()
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def tidy(name, section):
    name = html.unescape(name).replace('®', '').replace('™', '').replace('’', "'")
    name = re.sub(r'\s*\*.*$', '', name).strip()
    m = re.match(r'(.*?) - (Large|Medium|Small)$', name)
    if m:
        base = m.group(1)
        if section in ('Single Meat Subs', 'Cold Subs'):
            base += ' Sub'
        return f'{base} ({m.group(2).lower()})', m.group(2).lower()
    m = re.match(r'(.*?), (\d+ oz)$', name)
    if m:
        return f'{m.group(1)} ({m.group(2)})', m.group(2)
    if section == 'Sides & Chips' and name == 'Chili':
        return 'Chili (side)', None
    return re.sub(r'\s+Add-On$', '', name), None


def category(name, section):
    n = name.lower()
    if section == 'Sides & Chips' and re.search(r'cookie|brownie', n):
        return 'sweet'
    return KEEP[section]


def meat(name):
    base = re.sub(r'\s*\(.*\)$', '', name)
    for b in (base, re.sub(r' Sub$', '', base)):
        if b in SUB_MEATS:
            return SUB_MEATS[b]
    out = []
    for word, m in MEATS:
        if re.search(r'\b' + word, name.lower()) and m not in out:
            out.append(m)
    return out or None


def main():
    site_links_portal()
    page = get(INM)
    m = re.search(r'Last Updated:</strong>\s*([\d/]+)', page)
    if not m:
        raise SystemExit('Firehouse Subs: no "Last Updated" date on the Interactive Nutrition Menu')
    mo, dy, yr = m.group(1).split('/')
    edition = f'{yr}-{mo}-{dy}'
    heads = [h.strip() for h in re.findall(r'<span aria-hidden="true">([^<]+)</span><span class="sr-only">Sort', page)]
    if heads != ['Calories', 'Total Fat (g)', 'Saturated Fat (g)', 'Trans Fat (g)', 'Cholesterol (mg)', 'Sodium (mg)',
                 'Total Carbohydrates (g)', 'Dietary Fiber (g)', 'Total Sugars (g)', 'Added Sugars (g)', 'Protein (g)']:
        raise SystemExit(f'Firehouse Subs: the menu table columns changed: {heads}')
    body = page[page.find('<tbody'):page.find('</tbody>')]

    items, dropped, seen, section = [], [], set(), ''
    for row in re.findall(r'<tr[^>]*>(.*?)</tr>', body, re.S):
        h = re.search(r'<h3>([^<]+)</h3>', row)
        if h:
            section = html.unescape(h.group(1)).strip()
            continue
        mn = re.search(r'class="nmItem" title="([^"]+)"', row)
        if not mn:
            continue
        cells = re.findall(r'<td class="col[^"]*"[^>]*>(.*?)</td>', row, re.S)
        v = dict(zip(COLS, (num(c) for c in cells)))
        raw = html.unescape(mn.group(1))
        size = None
        if section.endswith(' oz Beverages'):
            cup = section.replace(' Beverages', '')
            if cup not in DRINK_SIZES or raw not in CORE_DRINKS:
                continue
            name, cat, size = f'{raw} ({cup})', 'drink', cup
        elif section in KEEP:
            name, size = tidy(raw, section)
            cat = category(name, section)
        else:
            continue
        if v.get('cal') is None or any(v.get(k) is None for k in ('p', 'c', 'f')):
            continue
        if name in seen:
            continue
        seen.add(name)
        est = 4 * v['p'] + 4 * v['c'] + 9 * v['f']
        if abs(est - v['cal']) > v['cal'] / 3 and abs(est - v['cal']) > 15 or (v.get('sat') or 0) > v['f']:
            dropped.append(name)
            continue
        if cat == 'drink':
            serve = f'{size} cup'
        elif size and 'oz' in size:
            serve = f'1 bowl ({size})'
        elif size:
            serve = f'1 {size} sub' if section.endswith('Subs') else f'1 serving ({size})'
        else:
            serve = '1 serving'
        items.append({
            'name': name, 'cat': cat, 'serve': serve,
            'cal': v['cal'], 'kj': None, 'p': v['p'], 'c': v['c'], 'f': v['f'],
            'sat': v.get('sat'), 'sugar': v.get('sugar'), 'fibre': v.get('fibre'), 'sodium': v.get('sodium'), 'salt': None,
            'contains': None, 'may': None, 'vg': None, 'meat': meat(name) if cat in ('main', 'side') else None,
        })

    src = (f"Firehouse Subs Interactive Nutrition Menu (US), from the Nutritionix-hosted Nutrition Portal firehousesubs.com links, "
           f"last updated {edition}. Figures are as published (FDA rounding). No allergens: the portal gives no per-item allergen "
           f"list. Left out: catering, boxed lunches, Kid's Subs and kids' drinks, the per-size sub-builder ingredient rows, the "
           f"12 oz cup, Freestyle flavour-shot drinks and flavoured waters")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-firehouse', 'name': 'Firehouse Subs', 'how': 'Official interactive nutrition menu (Nutritionix)',
        'url': PORTAL, 'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Firehouse Subs: {len(items)} items, {len(dropped)} dropped -> {OUT.name}')


if __name__ == '__main__':
    main()
