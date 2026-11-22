#!/usr/bin/env python3
"""Builds the United States restaurant menu, ios/MacroMenu/MenuData-US.json (bundled with the app), in the same format as ios/MacroMenu/MenuData.json.

Each chain's own published figures, read by the scraper beside this file:
  McDonald's   mcd-us-scrape.js     (browser)  -> mcd-us-source.json
  Chick-fil-A  cfa-us-scrape.py     (requests) -> cfa-us-source.json
  Wendy's      wendys-us-scrape.js  (browser)  -> wendys-us-source.json
  Taco Bell    tacobell-us-scrape.py (requests) -> tacobell-us-source.json
  Panda Express  read in Chrome (the page refuses scripts) -> panda-us-source.txt
  Burger King  bk.com/nutrition-explorer's feed, saved from the browser -> bk-us-source.json (read with intl/menu_feeds.py)
  Popeyes      popeyes.com Nutrition Guide PDF, via intl/extract-pdf-tables.py -> plk-us-source.json

US chains publish Calories, so `cal` is the published figure and `kj` is worked out from it (x 4.184). Chain IDs start with
"us-" so they can never collide with the Australian chains (McDonald's is "mcd" there, "us-mcd" here).
Allergens use the app's keys (Diet.swift); meats come from the item's name, and items whose name doesn't say are left without.

Run: python3 ios/Scripts/us/build-us-menu.py
"""
import hashlib
import importlib.util
import math
import json
import pathlib
import re
import sys
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent / 'intl'))
import menu_feeds  # noqa: E402
OUT = HERE.parent.parent / 'MacroMenu' / 'MenuData-US.json'

CHAINS = [
    {'id': 'mine', 'name': 'My foods'},
    {'id': 'us-mcd', 'name': "McDonald's", 'how': 'Official website item pages', 'url': 'https://www.mcdonalds.com/us/en-us/full-menu.html',
     'src': "mcdonalds.com (US) item nutrition, every size McDonald's lists for an item ({checked}). Allergens are the ones McDonald's lists for each part of the item"},
    {'id': 'us-cfa', 'name': 'Chick-fil-A', 'how': 'Official nutrition and allergen table', 'url': 'https://www.chick-fil-a.com/nutrition-allergens',
     'src': "Chick-fil-A Nutrition & Allergens ({checked}). Salads are as Chick-fil-A lists them for each protein. Chick-fil-A cooks in refined peanut oil, which the FDA doesn't count as an allergen, so its table doesn't list it"},
    {'id': 'us-wendys', 'name': "Wendy's", 'how': 'Official online menu item pages', 'url': 'https://order.wendys.com/us/en/national/menu',
     'src': "Wendy's US online menu, national (no store chosen) ({checked}). The national menu shows one size: Jr. fries and Frosty, small drinks. Full-sugar fountain drinks are left out because that menu lists them at 0 Cal. Salads come without and with their dressing packet, which Wendy's lists on its own"},
    {'id': 'us-tacobell', 'name': 'Taco Bell', 'how': 'Official website item nutrition labels', 'url': 'https://www.tacobell.com/food',
     'src': "tacobell.com item pages and the Nutritionix label each one links under Nutrition Info, every drink size ({checked}). Rounded the way Taco Bell's label rounds them (FDA rules)"},
    {'id': 'us-panda', 'name': 'Panda Express', 'how': 'Official nutrition and allergen table', 'url': 'https://www.pandaexpress.com/nutritioninformation',
     'src': "Panda Express Nutrition & Allergen Information ({checked}). Sides and entrées are listed on their own, as Panda does; a bowl is one side and one entrée. Drinks are by cup size in fl oz"},
    {'id': 'us-bk', 'name': 'Burger King', 'how': 'Official Nutrition Explorer', 'url': 'https://www.bk.com/nutrition-explorer',
     'src': "Burger King Nutrition Explorer ({checked}), each item as served with its standard toppings. Allergens are the ones Burger King lists as contained; may-contain includes shared cooking equipment"},
    {'id': 'us-popeyes', 'name': 'Popeyes', 'how': 'Official nutrition guide', 'url': 'https://www.popeyes.com/nutritional-information',
     'src': "Popeyes USA Nutrition Guide ({edition}, checked {checked}). Classic and spicy chicken share one row, as Popeyes lists them. No allergens yet: they're in a separate chart"},
]

ALLERGENS = {'gluten', 'wheat', 'milk', 'egg', 'soy', 'sesame', 'peanut', 'treenut', 'fish', 'shellfish', 'lupin', 'sulphites'}
WORDS = {'milk': 'milk', 'dairy / milk': 'milk', 'dairy': 'milk', 'egg': 'egg', 'eggs': 'egg', 'soy': 'soy', 'wheat': 'wheat',
         'sesame': 'sesame', 'peanut': 'peanut', 'peanuts': 'peanut', 'tree nut': 'treenut', 'tree nuts': 'treenut', 'tree-nuts': 'treenut',
         'nuts': 'treenut', 'tree': 'treenut', 'gluten': 'gluten', 'fish': 'fish', 'fish (pollock)': 'fish', 'shellfish': 'shellfish', 'crustacean shellfish': 'shellfish'}


def allergen_keys(words, where):
    out = set()
    for w in words:
        key = WORDS.get(w.strip().lower())
        if not key:
            raise SystemExit(f'{where}: allergen "{w}" is not one of the app\'s keys; add it to WORDS')
        out.add(key)
        if key == 'wheat':
            out.add('gluten')
    return sorted(out)


# Meats from the name, as the Australian menus do when that's all there is. First match per meat; no match = unknown.
MEATS = [
    ('chicken', r'chicken|nugget|nuggs|mccrispy|mcchicken|tender|chick-n|filet(?!-o)|strips?\b|deluxe sandwich|cool wrap|asiago ranch club|royal crispy|wings?\b|^leg\b|^thigh\b|^breast\b'),
    ('beef', r'beef|burger|big mac|quarter pounder|mcdouble|daily double|steak|dave|^(son of )?baconator$|double stack|big bacon classic|chili|whopper|bacon king|rodeo burger'),
    ('pork', r'bacon|sausage|\bham\b'),
    ('fish', r'fish'),
    ('seafood', r'shrimp|prawn'),
]
NO_MEAT = r'no meat|no chicken|impossible|plant[- ]based|veggie'


# Meats a restaurant's own description names outright. Narrower than the name patterns: a description is prose, so only the plain words count.
DESC_MEATS = {'chicken': r'\bchicken\b', 'beef': r'\bbeef\b', 'pork': r'\bbacon\b|\bsausage\b|\bham\b|\bpork\b|\bpepperoni\b',
              'fish': r'\bfish\b', 'seafood': r'\bshrimp\b|\bprawns?\b'}


def meats(name, desc=None):
    n = name.lower()
    if re.search(NO_MEAT, n):
        return []
    d = (desc or '').lower()
    return [m for m, pat in MEATS if re.search(pat, n) or (d and re.search(DESC_MEATS[m], d))]


def clean(name):
    name = re.sub(r'[®™*^]', '', name).replace('’', "'").replace('w/ ', 'with ')
    name = re.sub(r'\bMccrispy\b', 'McCrispy', name)
    return re.sub(r'\s+', ' ', name).strip()


def slug(s):
    return re.sub(r'^-|-$', '', re.sub(r'[^a-z0-9]+', '-', s.lower()))


def food(chain, name, cat, cal, p, c, f, serve, nut, al=None, may=None, src='labels', vg=None, desc=None):
    kj = round(cal * 4.184)
    row = {'id': f'{chain}:{slug(name)}', 'chain': chain, 'name': name, 'cat': cat, 'kj': kj, 'cal': cal,
           'p': p, 'c': c, 'f': f, 'serve': serve or '1 serving'}
    nut = {k: v for k, v in (nut or {}).items() if v is not None}
    if nut:
        row['nut'] = nut
    diet = {}
    m = meats(name, desc) if cat in ('main', 'breakfast', 'side') else []
    if m or (cat in ('main', 'breakfast', 'side') and re.search(NO_MEAT, name.lower())):
        diet['meat'] = m
    if al is not None:
        diet['al'] = al
        if may:
            diet['may'] = [k for k in may if k not in al]
            if not diet['may']:
                del diet['may']
    if vg:
        diet['meat'] = []
        diet['vg'] = vg
    if diet:
        diet['src'] = src
        row['diet'] = diet
    row['modifiers'] = []
    return row


# ---------- McDonald's ----------
# McDonald's own marketing names, where they read backwards or carry a size.
MCD_RENAME = {'Quarter Pounder with Cheese Bacon': 'Bacon Quarter Pounder with Cheese', 'Bagel Plain': 'Plain Bagel',
              'Latte Iced Caramel': 'Iced Caramel Latte', 'Mocha Iced': 'Iced Mocha', 'Latte Caramel': 'Caramel Latte',
              'Latte French Vanilla': 'French Vanilla Latte', 'Latte Iced': 'Iced Latte', 'Coffee Decaf': 'Decaf Coffee',
              'Snack Wrap McCrispy Ranch': 'McCrispy Ranch Snack Wrap', 'Snack Wrap McCrispy Spicy': 'Spicy McCrispy Snack Wrap',
              'McCrispy Strips (3 Piece)': 'McCrispy Strips (3 pc)', "McDonald's Lemonade (16 Oz.)": "McDonald's Lemonade (16 oz)",
              'Mayonnaise (Package)': 'Mayonnaise Packet', 'Mustard (Package)': 'Mustard Packet'}


def mcd():
    data = json.loads((HERE / 'mcd-us-source.json').read_text())
    items = {o['id']: o for o in data['items'] if not o.get('err')}
    # Size groups: name each member after the group's first size, plus its own size label.
    size_of, base_of = {}, {}
    for o in items.values():
        if o['sizes']:
            first = next((items[s['id']] for s in o['sizes'] if s['id'] in items), o)
            for s in o['sizes']:
                size_of[s['id']] = s['label']
                base_of[s['id']] = first
    rows = []
    for o in items.values():
        base = base_of.get(o['id'], o)
        name = clean(base['marketing'] or base['name'])
        name = re.sub(r'^McCafé ', '', name)
        name = MCD_RENAME.get(name, name)
        # Sizes written into the name ("Iced Coffee (Small)", "Cookie Butter Latte Small", "16 Oz") become "(small)".
        m = re.search(r'\s*\(?\b(Extra Small|Small|Medium|Large|\d+ Oz\.?)\b\s*\)?\s*(No Ice)?$', name, re.I)
        size = size_of.get(o['id'])
        if m:
            size = size or m.group(1)
            name = name[:m.start()].strip()
            if m.group(2):
                size += ', no ice'
        elif re.search(r'No Ice$', o['name']):
            size = (size or '') + ', no ice'
        name = re.sub(r'\s*\((Small|Medium|Large)\s*\)\s*No Ice$', '', name)
        if re.match(r'^\d+ (Piece|piece) ', name):
            name = re.sub(r'^\d+ (Piece|piece) ', '', name)
        if size:
            label = size.lower().replace(' piece', ' pc').replace('.', '').strip(', ')
            name = f'{name} ({label})'
        cats = ' '.join(o['cats'])
        low = name.lower()
        if 'Condiments' in cats or 'sauce' in low:
            cat = 'extra'
            if 'Sauce' in name:
                name = 'Dipping Sauce: ' + name.replace(' Sauce', '').replace('Mccrispy', 'McCrispy')
        elif 'Breakfast' in cats or 'bagel' in low:
            cat = 'breakfast'
        elif re.search(r'shake|frapp|smoothie|coffee|latte|mocha|cappuccino|macchiato|americano|tea\b|chocolate \(|coke|coca|sprite|pepper|hi-c|fanta|'
                       r'lemonade|refresher|red bull|juice|water|swirl|dream|punch|splash|blast|hot chocolate', low):
            cat = 'drink'
        elif 'Desserts' in cats:
            cat = 'sweet'
        elif 'Snacks & Sides' in cats:
            cat = 'side'
        else:
            cat = 'main'
        n = o['n']
        nut = {'sat': n.get('saturated_fat'), 'sugar': n.get('sugars'), 'fibre': n.get('fibre'), 'sodium': n.get('sodium')}
        # Sizes of one drink share their ingredients, but McDonald's sometimes leaves a size's list empty (small Cappuccino):
        # every size gets the allergens listed for any of them.
        group = [items[s['id']] for s in o['sizes'] if s['id'] in items] or [o]
        al = allergen_keys(sorted({w for g in group for w in g['al']}), f"McDonald's {name}")
        may = allergen_keys(sorted({w for g in group for w in g['may']}), f"McDonald's {name}")
        rows.append(food('us-mcd', name, cat, n['calories'], n['protein'], n.get('carbohydrate'), n.get('fat'), size and size.split(',')[0].lower(), nut, al, may))
    return rows, data['checked']


# ---------- Chick-fil-A ----------
CFA_SKIP_MENUS = {"Kid's Meals (nutrition per entrée only)", 'Buns', 'Proteins', 'Salad Toppings', 'Sandwich Toppings', 'Soup Toppings',
                  'Trays', 'Catering Entrées', 'Catering Drinks'}
CFA_CATS = {'Breakfast': 'breakfast', 'Entrées': 'main', 'Salads': 'main', 'Sides': 'side', 'Treats': 'sweet', 'Drinks': 'drink',
            'Coffee': 'drink', 'Dipping Sauces': 'extra', 'Dressings': 'extra'}
SIZE_WORDS = r'(Small|Medium|Large|Cup of|Bowl of|\d+ ct|6 pack)'


def cfa_name(row):
    title = clean(row['title'])
    parent = clean(row.get('parent', ''))
    bare = lambda s: re.sub(r'^Chick-fil-A ', '', s)
    m = re.match(SIZE_WORDS + r' (.+)$', title)
    if m and parent and bare(m.group(2)) == bare(parent):
        size = m.group(1).replace('Cup of', 'cup').replace('Bowl of', 'bowl').replace(' ct', ' ct').lower()
        return f'{parent} ({size})'
    m = re.match(r'^(\d+) ct (.+)$', title)
    if m:
        title = f'{m.group(2)} ({m.group(1)} ct)'
    return title.replace(' - no hash browns', ', no hash browns').replace(' - no hash brown', ', no hash browns')


def cfa():
    data = json.loads((HERE / 'cfa-us-source.json').read_text())
    rows, seen = [], set()
    skip = lambda title: re.search(r'^Gallon |Bag of Ice|Whipped Topping|^6 pack ', title)
    titles = {r['id']: r['title'] for r in data['items']}
    for r in data['items']:
        if r['menu'] in CFA_SKIP_MENUS:
            continue
        # A parent row repeats its default sub-item, unless none of its sub-items are kept (S'mores Milkshake's only sub is a topping).
        if r['subs'] and any(not skip(titles[i]) for i in r['subs']):
            continue
        title = r['title']
        if skip(title):
            continue
        # "Sunjoy (1/2 Sweet Tea, 1/2 Lemonade)" -> "Sunjoy Sweet Tea & Lemonade"
        name = re.sub(r'Sunjoy \((?:1/2 )?([^,]+), (?:1/2 )?([^)]+)\)', r'Sunjoy \1 & \2', cfa_name(r))
        if name in seen:
            continue
        seen.add(name)
        cat = CFA_CATS[r['menu']]
        if cat == 'sweet' and re.search(r'Lemonade|Frosted (Coffee|Dr|Diet|Barq|Coke|Coca|Hi-C|Sprite|Fanta|Powerade|Mello)|Milkshake|Float|Frosted Coffee', name):
            cat = 'drink'
        if r['menu'] == 'Dipping Sauces':
            name = 'Dipping Sauce: ' + re.sub(r' Sauce$', '', name)
        if r['menu'] == 'Dressings':
            name = 'Dressing: ' + re.sub(r' Dressing$', '', name)
        n = r['n']
        nut = {'sat': n.get('Sat. Fat (g)'), 'sugar': n.get('Sugar (g)'), 'fibre': n.get('Fiber (g)'), 'sodium': n.get('Sodium (mg)')}
        al = None
        if r.get('a'):
            al = allergen_keys([k for k, v in r['a'].items() if v], f'Chick-fil-A {name}')
        serve = n.get('Serving Size') or ''
        serve = re.sub(r'(\d)g$', r'\1 g', serve)
        rows.append(food('us-cfa', name, cat, n['Calories'], n['Protein (g)'], n.get('Carbohydrates (g)'), n.get('Fat (g)'), serve, nut, al))
    return rows, data['checked']


# ---------- Wendy's ----------
WENDYS_CATS = {'hamburgers': 'main', 'chicken-nuggets-more': 'main', 'tenders': 'main', 'fresh-made-salads': 'main', 'fries-sides': 'side',
               'coffee': 'drink', 'beverages': 'drink', 'frosty': 'sweet', 'bakery': 'sweet', 'croissants': 'breakfast', 'biscuits': 'breakfast',
               'classics': 'breakfast', 'breakfast-burrito': 'breakfast', 'sides-and-sweets': 'breakfast'}
# The national menu lists every full-sugar fountain drink at 0 Cal, which can't be right; only these zero-calorie ones are kept.
WENDYS_ZERO_OK = {'coca-cola-zero-sugar', 'diet-coke', 'diet-dr-pepper', 'pure-life-bottled-water'}
# Salad dressing packets, from each salad's page (Entree / Dressing (Per Pkt.) columns): cal, fat, sat, sodium, carbs, fibre, sugar, protein, allergens.
WENDYS_DRESSINGS = {
    'parmesan-caesar-salad': (240, 25, 4.5, 450, 2, 0, 1, 2, ['Dairy / Milk', 'Egg', 'Fish']),
    'cobb-salad': (250, 26, 4.5, 310, 2, 0, 1, 1, ['Dairy / Milk', 'Egg']),
    'apple-pecan-salad': (90, 3, 0, 190, 16, 0, 15, 0, []),
    'taco-salad': (150, 15, 3, 330, 3, 0, 1, 1, ['Dairy / Milk', 'Egg']),
}


def wendys():
    data = json.loads((HERE / 'wendys-us-source.json').read_text())
    rows = []
    for s, o in data['items'].items():
        if o.get('err'):
            continue
        if o['cal'] == 0 and o['cat'] == 'beverages' and s not in WENDYS_ZERO_OK:
            continue
        name = clean(o['name'])
        size = ''
        m = re.match(r'^(Jr\.|Small) (.+)$', name)
        if m:
            name, size = m.group(2), 'jr' if m.group(1) == 'Jr.' else 'small'
        name = re.sub(r'^(\d+) PC\. (.+)$', r'\2 (\1 pc)', name)
        name = re.sub(r', (\d+) PC$', r' (\1 pc)', name)
        if size:
            name = f'{name} ({size})'
        cat = WENDYS_CATS[o['cat']]
        if cat == 'main' and re.search(r'Party Pack', name):
            cat = 'main'
        nut = {'sat': o['sat'], 'sugar': o['sugar'], 'fibre': o['fibre'], 'sodium': o['sodium']}
        words = [w for w in (o['al'] or []) if w not in ('Entree', 'Dressing')]
        al = allergen_keys(words, f"Wendy's {name}") if o['al'] is not None else None
        if s in WENDYS_DRESSINGS:
            # The allergen list mixes salad and dressing ("Entree" ... "Dressing" ...); split it where Wendy's does.
            raw = o['al'] or []
            if 'Dressing' in raw:
                entree = allergen_keys([w for w in raw[:raw.index('Dressing')] if w != 'Entree'], f"Wendy's {name}")
            else:
                entree = al
            rows.append(food('us-wendys', f'{name} (no dressing)', cat, o['cal'], o['protein'], o['carbs'], o['fat'], 'salad without dressing', nut, entree, desc=o.get('desc')))
            dc, dfat, dsat, dna, dcarb, dfib, dsug, dp, dal = WENDYS_DRESSINGS[s]
            add = lambda a, b: None if a is None else round(a + b, 1)
            nut2 = {'sat': add(o['sat'], dsat), 'sugar': add(o['sugar'], dsug), 'fibre': add(o['fibre'], dfib), 'sodium': add(o['sodium'], dna)}
            both = sorted(set(al) | set(allergen_keys(dal, f"Wendy's {name} dressing")))
            rows.append(food('us-wendys', f'{name} (with dressing)', cat, o['cal'] + dc, add(o['protein'], dp), add(o['carbs'], dcarb),
                             add(o['fat'], dfat), 'salad with its dressing packet', nut2, both, desc=o.get('desc')))
            continue
        rows.append(food('us-wendys', name, cat, o['cal'], o['protein'], o['carbs'], o['fat'], size, nut, al, desc=o.get('desc')))
    return rows, data['checked']


# ---------- Taco Bell ----------
def fda(value, kind):
    """The FDA label rounding Taco Bell's Nutritionix labels apply to their raw values (21 CFR 101.9)."""
    if value is None:
        return None
    r = lambda x, step: math.floor(x / step + 0.5) * step
    if kind == 'cal':
        return 0 if value < 5 else int(r(value, 5 if value <= 50 else 10))
    if kind == 'fat':
        x = 0 if value < 0.5 else (r(value, 0.5) if value < 5 else r(value, 1))
        return int(x) if x == int(x) else x
    if kind == 'sodium':
        return 0 if value < 5 else int(r(value, 5 if value <= 140 else 10))
    return 0 if value < 0.5 else int(r(value, 1))           # carbs, fibre, sugar, protein


def tb_name(name):
    name = clean(name)
    # Taco Bell writes brands in capitals ("MOUNTAIN DEW BAJA BLAST dirty soda").
    return ' '.join(w.capitalize() if w.isupper() and len(w) > 2 and w not in ('BBQ',) else w for w in name.split())


def tacobell():
    data = json.loads((HERE / 'tacobell-us-source.json').read_text())
    rows, seen = [], set()
    for o in data['items']:
        if o.get('err') or 'values' not in o:
            continue
        v = o['values']
        name = tb_name(o['name'] if not o.get('size') else re.sub(r' - \w+$', '', o.get('variant') or o['name']))
        # "(v)" is Taco Bell's own vegetarian mark (American Vegetarian Association certified).
        vg = 'vegetarian' if re.search(r'\(v\)', name) else None
        name = re.sub(r'\s*\(v\)', '', name).replace(' - ', ', ')
        name = re.sub(r' (\d+(?:\.\d+)? oz)$', r' (\1)', name)
        if o.get('size'):
            name = f"{name} ({o['size'].lower().replace('_', ' ')})"
        if name in seen:
            continue
        seen.add(name)
        drink = o['category'] == 'drinks' or o.get('type') == 'Drink' or bool(o.get('size'))
        if drink:
            cat = 'drink'
        elif re.search(r'Packet|\(\d+(\.\d+)? oz\)', name):
            cat = 'extra'                                   # sauces, salsas, sour cream, guacamole and chili by the portion
        elif re.search(r'Cinnabon|Cinnamon|Churro|Twists|Cookie|Brownie', name):
            cat = 'sweet'
        elif o['category'] == 'breakfast':
            cat = 'breakfast'
        elif re.search(r'^(Chips|Black Beans|Cheesy Fiesta Potatoes|Pintos|Hash Brown)|Fries$', name):
            cat = 'side'
        else:
            cat = 'main'
        al = None
        if o.get('allergens'):
            al = allergen_keys([a for a, kind in o['allergens'].items() if kind == 'warning' and a != 'MSG'], f'Taco Bell {name}')
        # Nutritionix gives drinks odd weights (15 g for a soda), so only food gets one.
        weight = None if drink else v.get('ServingWeightGrams')
        serve = f'{round(weight)} g' if weight else (o['size'].lower() if o.get('size') else '')
        nut = {'sat': fda(v.get('SatFat'), 'fat'), 'sugar': fda(v.get('Sugars'), 'g'), 'fibre': fda(v.get('Fibers'), 'g'),
               'sodium': fda(v.get('Sodium'), 'sodium')}
        rows.append(food('us-tacobell', name, cat, fda(v['Calories'], 'cal'), fda(v.get('Proteins', 0), 'g'), fda(v.get('TotalCarb'), 'g'),
                         fda(v.get('TotalFat'), 'fat'), serve, nut, al, vg=vg))
    return rows, data['checked']


# ---------- Panda Express ----------
PANDA_CATS = {'BASE': 'side', 'VEGETABLES': 'main', 'CHICKEN': 'main', 'CHICKEN BREAST': 'main', 'BEEF': 'main', 'SEAFOOD': 'main',
              'APPETIZERS': 'side', 'SOUP': 'side', 'SAUCES & MORE': 'extra', 'BEV': 'drink'}


def panda():
    text = (HERE / 'panda-us-source.txt').read_text()
    checked = re.search(r'checked (\d+ \w+ \d{4})', text).group(1)
    rows = []
    for line in text.splitlines():
        if not line or line.startswith('#'):
            continue
        sec, dish, portion, cal, fat, sat, na, carb, fib, sug, prot, al = line.split('|')
        name = re.sub(r'[*®]', '', dish).strip()
        name = ' '.join(w if w in ('&',) else w.capitalize() for w in name.split()).replace("Kid's", "Kids'")
        name = re.sub(r'\((\w)', lambda m: '(' + m.group(1).lower(), name)          # "(Cup)" -> "(cup)", "(Tx Only)" -> "(tx only)"
        name = name.replace('(tx Only)', '(Texas only)').replace('(entree)', '(entrée)').replace('Bbq', 'BBQ').replace('Hi-c', 'Hi-C')
        cat = PANDA_CATS[sec]
        if sec == 'BEV':
            name = f'{name} ({portion} oz)'
            serve = f'{portion} fl oz cup'
        else:
            serve = portion.lower() if re.search(r'[a-z]', portion, re.I) else f"{'0' if portion.startswith('.') else ''}{portion} oz"
        if cat == 'extra' and 'Sauce' in name or name == 'Hot Mustard':
            name = 'Dipping Sauce: ' + re.sub(r' Sauce$', '', name)
        elif cat == 'extra':
            cat = 'sweet'                                       # fortune cookies, apple crisps
        num = lambda x: float(x) if '.' in x else int(x)
        nut = {'sat': num(sat), 'sugar': num(sug), 'fibre': num(fib), 'sodium': num(na)}
        rows.append(food('us-panda', name, cat, int(cal), num(prot), num(carb), num(fat), serve, nut,
                         allergen_keys([a for a in al.split(',') if a], f'Panda Express {name}')))
    return rows, datetime.strptime(checked, '%d %b %Y').strftime('%Y-%m-%d')


# ---------- Burger King ----------
BK_CATS = {'Breakfast': 'breakfast', 'Flame Grilled Burgers': 'main', 'Chicken & Fish': 'main', 'Sides': 'side', 'Drinks & Coffee': 'drink',
           'Sweets': 'sweet', 'Condiments': 'extra', 'Shakes': 'drink', 'Flame Grilled': 'main', 'King Jr. Kids Meals': 'main'}


def bk_rows(chain, path):
    """Burger King's Nutrition Explorer (bk.com, burgerking.ca): the same feed and format in both countries."""
    rows, seen = [], set()
    for o in menu_feeds.rbi_items(path):
        name = menu_feeds.sized(clean(o['name']).replace('’', "'"))
        name = name.replace("Barqs", "Barq's")
        if name in seen:
            continue
        seen.add(name)
        cat = BK_CATS.get(o['section'], 'main')
        if cat == 'breakfast' and re.search(r'Hash Brown', name):
            cat = 'side'
        if cat == 'extra' and re.search(r'Sauce|Ranch|Dressing', name):
            name = 'Dipping Sauce: ' + re.sub(r' Dipping Sauce$| Sauce$', '', name)
        if cat == 'drink' and re.search(r'Shake|Freezee', name) is None and o['n']['calories'] == 0 and re.search(r'Coke|Sprite|Pepper|Fanta|Barq|Hi-C', name) and not re.search(r'Diet|Zero', name):
            continue                                        # a sugary soda listed at 0 Cal can't be right
        n = o['n']
        r1 = lambda x: None if x is None else round(x, 1) if x != int(x) else int(x)
        nut = {'sat': r1(n.get('saturatedFat')), 'sugar': r1(n.get('sugar')), 'fibre': r1(n.get('fiber')), 'sodium': r1(n.get('sodium'))}
        weight = n.get('weight') if cat != 'drink' else None
        serve = re.search(r'\((value|kids|small|medium|large|extra large|\d+ pc)\)$', name)
        serve = f'{round(weight)} g' if weight and weight < 1500 else (serve.group(1) if serve else '')
        rows.append(food(chain, name, cat, round(n['calories']), r1(n['proteins']), r1(n.get('carbohydrates')), r1(n.get('fat')), serve, nut,
                         o['al'], o['may'], src='allergen table'))
    return rows


BK_CHECKED = '2026-11-14'                                   # when bk-us-source.json was saved from the site


def bk():
    return bk_rows('us-bk', HERE / 'bk-us-source.json'), BK_CHECKED


# ---------- Popeyes ----------
def popeyes():
    data = json.loads((HERE / 'plk-us-source.json').read_text())
    rows = []
    for o in data['rows']:
        raw = o['name'].strip()
        if re.match(r'^(TENDER - CLASSIC|LEG - CLASSIC)$', raw):
            name = raw.title().replace(' - Classic', ' (kids, classic)')       # the kids' meal pieces, on the desserts page
        else:
            name = ' '.join(w if w in ('&', '-') else w.lower() if w in ('WITH', 'OR', 'AND') else w.capitalize() for w in raw.split())
        for a, b in (('Bbq', 'BBQ'), ('Boldbq', 'BoldBQ'), ('Jalapeño', 'Jalapeño'), ('Dr Pepper', 'Dr Pepper'), ('(each)', ''), ('(Each)', ''),
                     ('Bayou Buffalo', 'Bayou Buffalo'), ('Mac & Cheese', 'Mac & Cheese'), ('Sandwich-classic', 'Sandwich, Classic'),
                     ('Sandwich-spicy', 'Sandwich, Spicy'), (' - Classic Or Spicy', ', Classic or Spicy'), (' - Blackened', ', Blackened'),
                     ('Signature Chicken', 'Signature Chicken')):
            name = name.replace(a, b)
        name = clean(name)
        portion = o['portion']
        if portion in ('Reg', 'Lg'):
            name += ' (regular)' if portion == 'Reg' else ' (large)'
        elif re.match(r'^\d+ Pieces?$', portion):
            name += f' ({portion.split()[0]} pc)'
        low = name.lower()
        if re.search(r'^(jalapeño|bayou buffalo|boldbq|blackened ranch|buttermilk ranch|mardi gras mustard|sweet heat|wild honey mustard|cocktail sauce)', low):
            cat, name = 'extra', 'Dipping Sauce: ' + name
        elif re.search(r'coffee|juice|coke|sprite|fanta|dew|pepsi|dr pepper|lemonade|tea\b', low):
            cat = 'drink'
        elif re.search(r'pie$', low):
            cat = 'sweet'
        elif re.search(r'biscuit|hash rounds', low) and low != 'biscuit':
            cat = 'breakfast'
        elif re.search(r'fries|mac & cheese|mashed|beans|coleslaw|cajun rice|gravy|^biscuit$', low):
            cat = 'side'
        else:
            cat = 'main'
        num = lambda x: float(x) if '.' in x else int(x)
        nut = {'sat': num(o['sat']), 'sugar': num(o['sugar']), 'fibre': num(o['fibre']), 'sodium': num(o['sodium'])}
        serve = {'Reg': 'regular', 'Lg': 'large'}.get(portion) or (f"{portion.split()[0]} pieces" if 'Piece' in portion else '1 piece' if re.search(r'^(Wing|Leg|Thigh|Breast)', name) else '')
        rows.append(food('us-popeyes', name, cat, num(o['cal']), num(o['protein']), num(o['carbs']), num(o['fat']), serve, nut))
    CHAIN_EXTRA['us-popeyes'] = {'edition': data.get('edition') or ''}
    return rows, data['checked']


CHAIN_EXTRA = {}
# Chains saved in the shared format (intl/SOURCE-FORMAT.md) by their own intl/<id>-fetch.py, read by intl/build-intl-menu.py's generic().
SHARED = ['us-arbys', 'us-fiveguys', 'us-deltaco', 'us-epl', 'us-jitb']


FG_TOPPINGS = {'Bacon (2 pieces)': 'Add Bacon', 'Cheese (1 slice)': 'Add Cheese', 'Hamburger Patty': 'Add Patty', 'Grilled Mushrooms': 'Grilled Mushrooms',
               'Onions / Grilled Onions': 'Grilled Onions', 'Green Peppers': 'Green Peppers', 'Jalapeño Peppers': 'Jalapeño Peppers', 'Lettuce': 'Lettuce',
               'Pickles': 'Pickles', 'Tomatoes': 'Tomatoes', 'Mayonnaise': 'Mayonnaise', 'Ketchup': 'Ketchup', 'Mustard': 'Mustard', 'Relish': 'Relish',
               'BBQ Sauce': 'BBQ Sauce', 'A.1. Sauce': 'A.1. Sauce', 'Hot Sauce': 'Hot Sauce'}
FG_SHAKES = {'Chocolate': 'Chocolate', 'Coffee': 'Coffee', 'Strawberry': 'Strawberry', 'Banana Marinade': 'Banana', 'Salted Caramel': 'Salted Caramel',
             'Peanut Butter': 'Peanut Butter', 'Oreo Cookie Pieces': 'Oreo', 'Blackberry Sauce': 'Blackberry', 'Bacon (2 pieces)': 'Bacon'}


def fiveguys(intl, rows):
    """Five Guys US publishes parts. Like the Australian menu: burgers and dogs as ordered (bun, patties, cheese, bacon), one row per milkshake
    flavour (vanilla base plus the mix-in), toppings as add-ons, and the loose parts (buns, sausage, mix-ins) left out."""
    by = {r['name'].removeprefix('Dipping Sauce: '): r for r in rows}

    def made(name, cat, parts, serve):
        rs = [by[n] for n in parts]
        total = lambda k: round(sum(r[k] for r in rs), 1)
        nut = {k: round(sum(r.get('nut', {}).get(k) or 0 for r in rs), 1) for k in ('sat', 'sugar', 'fibre', 'sodium')}
        al = sorted({a for r in rs for a in r.get('diet', {}).get('al', [])})
        may = sorted({a for r in rs for a in r.get('diet', {}).get('may', [])} - set(al))
        out = intl.row('us-fiveguys', name, cat, total('p'), total('c'), total('f'), serve, nut, al, may or None, cal=total('cal'), kj=total('kj'))
        meat = sorted({m for r in rs for m in r.get('diet', {}).get('meat') or []})
        out.setdefault('diet', {'src': 'allergen table'})['meat'] = meat
        return out

    # Kept as listed: the three plain mains, fries, peanuts, eggs and the drinks other than shakes. The rest are parts.
    out = [r for r in rows if r['cat'] in ('main', 'breakfast') or r['cat'] == 'side' and re.search(r'Fries|Peanuts', r['name'])
           or r['cat'] == 'drink' and 'Milkshake' not in r['name']]
    for (name, base) in (('Hamburger', 'Hamburger'), ('Little Hamburger', 'Little Hamburger'), ('Hot Dog', 'Hot Dog')):
        double = name == 'Hamburger'
        cheese = ['Cheese (1 slice)'] * (2 if double else 1)
        little = 'Little ' if name.startswith('Little') else ''
        kind = 'Dog' if 'Dog' in name else 'Burger'
        noun = 'Cheese Dog' if kind == 'Dog' else f'{little}Cheeseburger'
        out += [made(noun, 'main', [base] + cheese, 'no toppings'),
                made(f'{little}Bacon {kind}', 'main', [base, 'Bacon (2 pieces)'], 'no toppings'),
                made(noun.replace('Cheese', 'Bacon Cheese', 1) if kind == 'Dog' else f'{little}Bacon Cheeseburger', 'main', [base, 'Bacon (2 pieces)'] + cheese, 'no toppings')]
    for size, base, on in (('', 'Vanilla Milkshake (regular, no mix-ins)', 'on a shake'), (' (mini)', 'Vanilla Milkshake (mini, no mix-ins)', 'on a mini shake')):
        by[f'Vanilla Milkshake{size}'] = dict(by[base])
        out.append(made(f'Vanilla Milkshake{size}', 'drink', [base], 'mini' if size else 'regular'))
        for mix, flavour in FG_SHAKES.items():
            out.append(made(f'{flavour} Milkshake{size}', 'drink', [base, f'{mix} ({on})'], 'mini' if size else 'regular'))
    for part, name in FG_TOPPINGS.items():
        r = dict(by[part], cat='extra', name=name)
        r['id'] = f"us-fiveguys:{slug('add ' + name if not name.startswith('Add') else name)}"
        out.append(r)
    out += [r for r in rows if r['name'].startswith('Dipping Sauce:') and re.search(r'Cheese Sauce|Five Guys Sauce|Fry Sauce', r['name'])]
    return out


def shared_chains():
    """(chain entry, rows, checked) for each SHARED chain, less rows the international build would leave out as misprinted."""
    spec = importlib.util.spec_from_file_location('intlmenu', HERE.parent / 'intl' / 'build-intl-menu.py')
    intl = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(intl)
    out = []
    for chain in SHARED:
        meta, read = intl.generic_chain(chain)
        rows = []
        for r in read():
            why = intl.misprinted(r)
            if why:
                print(f'  {chain}: left out {r["name"]}: {why}')
            else:
                rows.append(r)
        if chain == 'us-fiveguys':
            rows = fiveguys(intl, rows)
        out.append((meta, rows, intl.CHECKED[chain]))
    return out


_pieces_spec = importlib.util.spec_from_file_location('single_pieces', pathlib.Path(__file__).resolve().parent.parent / 'single-pieces.py')
single_pieces = importlib.util.module_from_spec(_pieces_spec)
_pieces_spec.loader.exec_module(single_pieces)


def main():
    foods, checked = [], {}
    for chain, fn in (('us-mcd', mcd), ('us-cfa', cfa), ('us-wendys', wendys), ('us-tacobell', tacobell), ('us-panda', panda), ('us-bk', bk),
                      ('us-popeyes', popeyes)):
        rows, when = fn()
        foods += rows
        checked[chain] = datetime.strptime(when, '%Y-%m-%d').strftime('%-d %b %Y')
    shared = shared_chains()
    for meta, rows, when in shared:
        foods += rows
        checked[meta['id']] = datetime.strptime(when, '%Y-%m-%d').strftime('%-d %b %Y')
    foods, split, _ = single_pieces.add_single_pieces(foods)
    ids = [f['id'] for f in foods]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise SystemExit(f'Duplicate menu IDs: {sorted(dupes)}')
    for f in foods:
        for k in f.get('diet', {}).get('al', []) + f.get('diet', {}).get('may', []):
            assert k in ALLERGENS, (f['id'], k)
    chains = [dict(c, src=c['src'].format(checked=checked[c['id']], **CHAIN_EXTRA.get(c['id'], {}))) if 'src' in c else c
              for c in CHAINS + [meta for meta, _, _ in shared]]
    chains = [dict(c, src=single_pieces.noted(c['src'])) if c['id'] in split else c for c in chains]
    revision = hashlib.sha256(json.dumps({'chains': chains, 'foods': foods}, sort_keys=True).encode()).hexdigest()[:16]
    published = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
    try:
        prev = json.loads(OUT.read_text())
        if prev.get('revision') == revision:
            published = prev['published']
    except FileNotFoundError:
        pass
    OUT.write_text(json.dumps({'format': 1, 'country': 'US', 'revision': revision, 'published': published, 'chains': chains, 'foods': foods},
                              ensure_ascii=False, separators=(',', ':')))
    by = {c['id']: sum(f['chain'] == c['id'] for f in foods) for c in chains[1:]}
    print(f'Exported {len(foods)} US foods across {len(chains) - 1} restaurants: ' + ', '.join(f'{c["name"]} {by[c["id"]]}' for c in chains[1:]))


if __name__ == '__main__':
    main()
