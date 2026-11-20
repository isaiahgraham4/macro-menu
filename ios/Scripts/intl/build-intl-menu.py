#!/usr/bin/env python3
"""Builds the Canadian, British, New Zealand, South African and Indian restaurant menus, bundled with the app beside MenuData.json (Australia) and
MenuData-US.json, in the same format:

  ios/MacroMenu/MenuData-CA.json  McDonald's, Burger King, Tim Hortons
  ios/MacroMenu/MenuData-GB.json  McDonald's, Greggs
  ios/MacroMenu/MenuData-NZ.json  McDonald's, Domino's
  ios/MacroMenu/MenuData-ZA.json  McDonald's, Nando's, Wimpy, Debonairs Pizza, Kauai
  ios/MacroMenu/MenuData-IN.json  McDonald's, KFC, Pizza Hut

Each chain's own published figures, saved beside this file:
  McDonald's (CA, UK, NZ)  mcd-intl-scrape.js in a browser on the country's McDonald's site -> mcd-<cc>-source.json
  Burger King Canada       burgerking.ca/nutrition-explorer's feed, saved from the browser  -> bk-ca-source.json
  Tim Hortons              Nutrition Information PDF via extract-pdf-tables.py               -> th-ca-source.json
  Greggs                   the menu feed greggs.com/menu loads, saved from the browser       -> greggs-uk-source.json
  Domino's New Zealand     dominos.co.nz/menu/nutritional-information, every crust, read in the browser -> dominos-nz-source.json
  McDonald's South Africa  mcd-za-scrape.js in a browser on mcdonalds.co.za (its own site, not the API above) -> mcd-za-source.json
  Nando's South Africa     the menu feed nandos.co.za/eat/order/menu loads, saved from the browser   -> nandos-za-source.json
  Wimpy, Debonairs, Kauai  za-fetch.py (plain web pages)                                             -> <chain>-za-source.json
  McDonald's, KFC, Pizza Hut India  each chain's nutrition booklet (PDF) via in-extract.py                 -> <chain>-in-source.json

Chain IDs carry the country ("ca-mcd", "uk-mcd", "nz-mcd") so no two menus share one. Energy is whatever the chain publishes:
Canada publishes Calories (kJ worked out), the UK and New Zealand publish both. UK chains publish salt, not sodium; sodium is
worked out as salt / 2.5 (the UK and EU labelling rule).

Run: python3 ios/Scripts/intl/build-intl-menu.py
"""
import hashlib
import importlib.util
import json
import pathlib
import re
from datetime import datetime, timezone

HERE = pathlib.Path(__file__).parent
APP = HERE.parent.parent / 'MacroMenu'

_spec = importlib.util.spec_from_file_location('usmenu', HERE.parent / 'us' / 'build-us-menu.py')
us = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(us)
import menu_feeds  # noqa: E402  (us-menu put this folder on sys.path)

# Meats from names, for these menus' own words. First pattern per meat; names that say "vegan" or "plant based" have none.
us.MEATS[:] = [
    ('chicken', r'chicken|chook|nugget|mcnuggets|selects|mccrispy|mcchicken|tender|wings?\b|crispy chicken|junior chicken|mcspicy|katsu|tikka|tandoori|butter chicken|bites'),
    ('beef', r'beef|burger|big mac|quarter pounder|mcdouble|whopper|steak|big king|angus|mcroyale|bacon king|roadhouse king|quarter pound|meatlovers|meats\b|the lot|godfather|supreme|chili|mince|cheeseburger|hamburger|big tasty|double cheese'),
    ('pork', r'bacon|sausage|\bham\b|pepperoni|salami|chorizo|pork|belt\b|meatlovers|meats\b|the lot|godfather|supreme|hawaiian'),
    ('fish', r'fish'),
    ('seafood', r'prawn|shrimp|shellfish'),
]
us.NO_MEAT = r'no meat|no chicken|vegan|plant[- ]based|vegetarian|veggie|vege\b|impossible|pork-free|beyond|meat[- ]free|paneer|margherita'
# Words that make "chicken" and "beef" wrong: "Vegan Sausage Roll", "Chicken Supreme" has chicken but no beef.
NOT_BEEF = r'chicken supreme|chicken|vegan'

CHECKED = {}


def row(chain, name, cat, p, c, f, serve, nut, al=None, may=None, cal=None, kj=None, vg=None, src='allergen table'):
    if cal is None:
        cal = round(kj / 4.184)
    r = us.food(chain, name, cat, round(cal), p, c, f, serve, nut, al, may, src=src, vg=vg)
    if kj is not None:
        r['kj'] = round(kj)
    meat = r.get('diet', {}).get('meat')
    if meat and 'beef' in meat and 'chicken' in meat and re.search(NOT_BEEF, name.lower()) and not re.search(r'burger|whopper|beef|meats|meatlovers|the lot', name.lower()):
        meat.remove('beef')
    return r


def num(x):
    if x is None or x == '':
        return None
    x = float(x)
    return int(x) if x == int(x) else round(x, 1)


def dedupe(rows):
    """Two rows with one name (the same item on two menu pages) keep the first; different figures under one name get the serve added."""
    out, seen = [], {}
    for r in rows:
        if r['id'] in seen:
            prev = seen[r['id']]
            if (prev['kj'], prev['p']) == (r['kj'], r['p']):
                continue
            r['name'] = f"{r['name']} ({r['serve']})" if r['serve'] and r['serve'] != '1 serving' else f"{r['name']} ({r['kj']} kJ)"
            r['id'] = f"{r['chain']}:{us.slug(r['name'])}"
            if r['id'] in seen:
                continue
        seen[r['id']] = r
        out.append(r)
    return out


# ---------- McDonald's (Canada, UK, New Zealand) ----------
DRINK = (r'shake|frapp|smoothie|coffee|latte|mocha|cappuccino|macchiato|americano|flat white|espresso|\btea\b|chai|hot chocolate|'
         r'coke|coca|cola|sprite|fanta|pepper|lemonade|juice|water|milk\b|milk -|punch|powerade|frozen|fruitopia|iced capp|irn|tango|'
         r'oasis|lilt|refresher|mccafé|mccafe|chocolate milk|fruit shoot|frozen|drink|l&p|lift\b|dr pepper|barq|nestea|minute maid|'
         r'smoothie|frappé|soda|piccolo|matcha|iced chocolate|energizer|dream\b|red bull|refresher|frosted')
SWEET = r'mcflurry|sundae|cone|pie\b|muffin|cookie|donut|doughnut|brownie|cake|loaf|danish|croissant|scone|tart|apple slices|parfait|carrot|cinnamon|macaron|caramel slice|sweet treat|pastry|snack bar'
SAUCE = r'sauce|dip\b|dip pot|ketchup|mayo\b|mayonnaise|mustard|relish|dressing|syrup|jam\b|butter\b|spread|honey\b|salsa|creamer|sugar|sweetener|whipped'


def mcd_cat(name, groups):
    low, g = name.lower(), ' '.join(groups).lower()
    drink_group = re.search(r'beverage|drinks|mccaf', g) and not re.search(r'bakery|dessert', g)
    if re.search(r'hash brown|hashbrown', low):
        return 'side'
    if (re.search(DRINK, low) or drink_group and not re.search(SWEET, low)) and \
            not re.search(r'muffin|cookie(?! butter)|cake|sundae|mcflurry|loaf|pie\b|croissant|wrap|burger|bagel|porridge|sauce|dip\b|fries', low):
        return 'drink'
    if re.search(r'condiment|sauces', g) and not re.search(r'sandwich|donut|hotcake|mcdip', low) or re.search(SAUCE, low) and \
            not re.search(r'burger|mcmuffin|wrap|chicken|nugget|fries|bagel|pancake|hotcake|porridge|muffin|sandwich|donut|doughnut|mcdip|cone', low):
        return 'extra'
    if re.search(SWEET, low) and not re.search(r'english muffin|mcmuffin|muffin &|muffin with|pizza', low) or re.search(r'dessert', g):
        return 'sweet'
    if (re.search(r'breakfast', g) or re.search(r'breakfast|brekkie|mcmuffin|hotcake|pancake|bagel|bacon roll|porridge|oatmeal|oats\b', low)) \
            and not re.search(r'salad|apple slices|carrot|fruit bag', low):
        return 'breakfast'
    if re.search(r'fries|wedges|salad\b|side|carrot|corn|poutine|apple|grapes|onion rings|cheese bites|mozzarella|hash|dippers|pizza pie', low) and \
            not re.search(r'chicken|burger|wrap|deluxe|mcmuffin', low):
        return 'side'
    return 'main'


def mcd(cc, chain):
    data = json.loads((HERE / f'mcd-{cc}-source.json').read_text())
    CHECKED[chain] = data['checked']
    # Each size of a drink is its own item; McDonald's labels them in the item's size list ("Small", "Medium", "Large").
    size_of = {s['id']: s['label'] for o in data['items'] for s in o.get('sizes') or [] if s.get('label')}
    rows = []
    for o in data['items']:
        if 'n' not in o:
            continue
        n = o['n']
        name = us.clean(o['marketing'] or o['name']).replace('’', "'").replace('FiIet', 'Filet')
        name = re.sub(r'^(Small|Medium|Large|Regular)\s*-\s*', r'\1 ', name)
        name = name.replace('LIMITED EDITION GOLD SAUCE', 'Limited Edition Gold Sauce').replace('Choc McDip', 'Choc McDip Cone')
        name = re.sub(r'^(?:Drink|Condiment|Sauce|Dessert)\s*-\s*|^-\s*', '', name)
        name = re.sub(r'\s*-\s*\d+ ?g$', '', name)
        name = re.sub(r'^McCaf[ée]®?\s*(?:Drink\s*)?-?\s*', '', name) if not re.search(r'McCafé$', name) else name
        name = re.sub(r'\s*-\s*(\d+) ?ml$', r' (\1 ml)', name)
        name = menu_feeds.sized(name)
        label = size_of.get(o['id'], '')
        label = {'Regular Size': 'regular', 'Snack Size': 'snack', 'Child': 'kids'}.get(label, label)
        if label and not name.endswith(')') and re.match(r'^(Extra Small|X-?Small|Small|Medium|Large|Extra Large|Regular|Kids|Junior|Snack)$', label, re.I):
            name = f'{name} ({label.lower()})'
        groups = o.get('cats', []) + o.get('pages', [])
        cat = mcd_cat(name, groups)
        if cat == 'extra' and re.search(r'sauce|dip\b|dip pot', name, re.I):
            name = re.sub(r'^(?:Sauce Packet|Condiment)\s*', '', name)
            name = 'Dipping Sauce: ' + re.sub(r'\s*(Dipping )?(Sauce|Dip Pot|Dip)(?= \(|$)', '', name, flags=re.I)
        kcal = n.get('calories') if n.get('calories') is not None else n.get('energy_kcal')
        kj = n.get('energy_kJ')
        if kcal is None and kj is None or n.get('protein') is None:
            continue
        sodium = n.get('sodium')
        if sodium is None and n.get('salt') is not None:
            sodium = round(n['salt'] * 400)
        nut = {'sat': num(n.get('saturated_fat')), 'sugar': num(n.get('sugars')), 'fibre': num(n.get('fibre')), 'sodium': num(sodium)}
        serve = f"{num(n['primary_serving_size'])} g" if n.get('primary_serving_size') else ''
        al = may = None
        if cc in ('ca', 'nz') and o['item_al']:
            # "Contains Milk.|May also contain Sulphites." The contains list is a list; the rest are cross-contact notes in prose.
            contains, *notes = o['item_al'].split('|')
            al = menu_feeds.allergen_words(contains, f"McDonald's {cc} {name}")
            may = menu_feeds.allergen_mentions(' '.join(notes + [o['item_may'] or ''])) or None
        # The UK feed lists all fourteen allergens on items like the Big Mac and Fries, so its allergens aren't used.
        rows.append(row(chain, name, cat, num(n['protein']), num(n.get('carbohydrate')), num(n.get('fat')), serve, nut, al, may,
                        cal=kcal if cc == 'ca' or kj is None else None, kj=kj if cc != 'ca' else None, src='allergen list'))
        if cc == 'ca' and kj:
            rows[-1]['kj'] = round(kj)
    return dedupe(rows)


# ---------- Burger King Canada ----------
def bk_ca():
    CHECKED['ca-bk'] = '2026-11-14'                       # when bk-ca-source.json was saved from the site
    return dedupe(us.bk_rows('ca-bk', HERE / 'bk-ca-source.json'))


# ---------- Tim Hortons ----------
def tims():
    data = json.loads((HERE / 'th-ca-source.json').read_text())
    CHECKED['ca-tims'] = data['checked']
    rows = []
    for o in data['rows']:
        name = menu_feeds.sized(o['name'].replace('’', "'"))
        sec = o['section']
        low = (name + ' ' + sec).lower()
        if re.search(r'quencher', name.lower()) and re.search(r'sparkling|lemonade|frozen', sec.lower()):
            kind = re.search(r'sparkling|lemonade|frozen', sec.lower()).group(0)
            name = re.sub(r'Quencher', f'{kind.capitalize()} Quencher', name)
        if re.search(r'syrup|sugar|dairy|cream for|milk for|whitener|sweetener|bagel toppings|cream cheese|butter|jam\b|honey|pump', low) \
                and not re.search(r'bagel sandwich|bagel belt|donut|timbit|muffin|cookie', name.lower()):
            cat = 'extra'
        elif re.search(r'coffee|latte|cappuccino|espresso|americano|macchiato|tea\b|chai|london fog|hot chocolate|lemonade|quencher|'
                       r'smoothie|iced capp|cold brew|beverage|steeped|refresher|frozen|mocha|flat white', low):
            cat = 'drink'
        elif re.search(r'donut|timbit|muffin|cookie|brownie|croissant|danish|fritter|cruller|dutchie|tea biscuit|cinnamon|loaf|cake', name.lower()) \
                and not re.search(r'english muffin|bagel|sandwich|biscuit sandwich|homestyle biscuit', name.lower()):
            cat = 'sweet'
        elif re.search(r'breakfast|farmer|omelette|egg|belt|hash brown|oatmeal|bagel|english muffin|homestyle biscuit', low) and not re.search(r'soup|chili', low):
            cat = 'side' if re.search(r'hash brown', low) else 'breakfast'
        elif re.search(r'soup|chili|side|bun|potato|wedges|hash', low):
            cat = 'side'
        else:
            cat = 'main'
        nut = {'sat': num(o['sat']), 'sugar': num(o['sugar']), 'fibre': num(o['fibre']), 'sodium': num(o['sodium'])}
        size = re.search(r'\((small|medium|large|extra large|x large)\)$', name)
        rows.append(row('ca-tims', name, cat, num(o['protein']), num(o['carbs']), num(o['fat']), size.group(1) if size else '', nut,
                        cal=num(o['cal'])))
    return dedupe(rows)


# ---------- Greggs ----------
GREGGS_CATS = {1: 'breakfast', 2: 'main', 3: 'drink', 4: 'main', 5: 'sweet', 6: 'main'}


def greggs():
    data = json.loads((HERE / 'greggs-uk-source.json').read_text())
    CHECKED['uk-greggs'] = '2026-11-14'                   # when greggs-uk-source.json was saved from the site
    rows = []
    for o in data:
        if o.get('isCustomisation') or o.get('isMealDeal'):
            continue
        name = menu_feeds.sized(us.clean(o['articleName']).replace('’', "'"))
        name = re.sub(r'\s*\((New Recipe|NEW|New & Improved Recipe|New and Improved Recipe)\)$', '', name, flags=re.I)
        n = {v['name']: v['value'] for v in o['nutritionalValues']}
        if n.get('Calories') is None or n.get('Protein') is None:
            continue
        cat = GREGGS_CATS.get(o['articleCategoryId'], 'main')
        low = name.lower()
        if cat == 'drink' and re.search(r'cookie|muffin|doughnut|bake|slice', low):
            cat = 'sweet'
        if cat == 'main' and re.search(r'doughnut|cookie|muffin|tart|slice|cake|yum yum|triangle|brownie|mousse|pot\b', low) and 'pizza' not in low:
            cat = 'sweet'
        if re.search(r'pizza box', low):
            name = re.sub(r'^(\d+) Slice (.+?) Pizza Box$', r'\2 Pizza (\1-slice box)', name).replace('Pizza with Hot Honey Pizza', 'Pizza with Hot Honey')
            cat = 'main'
        # Greggs lists only the allergens an item has, so an empty list means none.
        al = sorted({k for i in o.get('ingredients', []) if i.get('isAllergen')
                     for k in menu_feeds.allergen_words(i['name'], f'Greggs {name}')})
        if 'wheat' in al and 'gluten' not in al:
            al = sorted(al + ['gluten'])
        vg = 'vegan' if re.search(r'\bvegan\b', low) else None
        nut = {'sat': num(n.get('Saturates')), 'sugar': num(n.get('Sugar')), 'sodium': round(n['Salt'] * 400) if n.get('Salt') is not None else None}
        size = o.get('articleSize') or {}
        serve = f"{num(size['size'])} {size.get('unitOfMeasure') or 'g'}" if size.get('size') else ''
        rows.append(row('uk-greggs', name, cat, num(n['Protein']), num(n.get('Carbohydrates')), num(n.get('Fat')), serve, nut, al,
                        cal=n['Calories'], kj=n.get('EnergyKj'), vg=vg))
    return dedupe(rows)


# ---------- Domino's New Zealand ----------
def dominos_nz():
    data = json.loads((HERE / 'dominos-nz-source.json').read_text())
    CHECKED['nz-dominos'] = data['checked']
    rows = []
    for o in data['rows']:
        t = o['text']
        get = lambda label: (re.search(label + r'\n([\d.]*)\s*(?:g|mg|cal|kj)?', t, re.I) or [None, None])[1]
        cal, kj, p = get(r'Energy \(Calories\)'), get(r'Energy \(kilojoules\)'), get('Protein')
        if not cal or not p:
            continue
        figures = [get(x) for x in ('Carbohydrate', r'Fat - Total', r'Fat - Sat', 'Sugars', 'Sodium', 'Serving Size')] + [cal, p, kj]
        if any(v and not re.match(r'^\d+(\.\d+)?$', v) for v in figures):
            print(f"Domino's NZ: left out {o['name']} ({o['serving']}), misprinted figure on the site: {[v for v in figures if v and not re.match(r'^\d+(\.\d+)?$', v)]}")
            continue
        per = re.search(r'(\d+) Servings per (\w+)', t)
        kind = per.group(2).lower() if per else ''
        name = us.clean(o['name']).replace('’', "'").replace('Mozarella', 'Mozzarella')
        if kind == 'pizza':
            cat = 'main'
            name = f"{name} ({o['serving'].lower().replace(' n ', ' & ')} slice)" if o['serving'] else f'{name} (slice)'
            serve = f"1 slice ({get('Serving Size')} g), {per.group(1)} per pizza"
        else:
            cat = 'sweet' if kind == 'desserts' else 'side'
            if re.search(r'dipping sauce|^marinara sauce', name.lower()):
                cat, name = 'extra', 'Dipping Sauce: ' + re.sub(r' (Dipping )?Sauce$', '', name)
            elif re.search(r'wings|chicken bites', name.lower()):
                cat = 'main'
            name = menu_feeds.sized(name)
            serve = f"{get('Serving Size')} g" if get('Serving Size') else ''
        al_text = re.search(r'Contains:([^\n]*)', t)
        al = menu_feeds.allergen_words(al_text.group(1), f"Domino's {name}") if al_text else None
        may_text = re.search(r'May (?:also )?contain:?([^\n]*)', t, re.I)
        may = menu_feeds.allergen_mentions(may_text.group(1)) if may_text else None
        vg = 'vegan' if re.search(r'vegan', name.lower()) else 'vegetarian' if 'Suitable for Vegetarians' in t else None
        nut = {'sat': num(get('Fat - Sat')), 'sugar': num(get('Sugars')), 'sodium': num(get('Sodium'))}
        rows.append(row('nz-dominos', name, cat, num(p), num(get('Carbohydrate')), num(get('Fat - Total')), serve, nut, al, may,
                        cal=num(cal), kj=num(kj) if kj else None, vg=vg))
    return dedupe(rows)


# ---------- South Africa ----------
def fnum(x):
    """'3,8 g', '2356 kJ', '4.79gg', '440kCal' -> a number; anything else (blank, '-', 'n/a') -> None."""
    m = re.search(r'-?\d+(?:[.,]\d+)?', str(x) if x is not None else '')
    return num(m.group(0).replace(',', '.')) if m else None


SMALL_WORDS = {'And', 'Or', 'The', 'With', 'On', 'Of', 'In', 'A'}
KEEP_UPPER = {'BBQ', 'PERi-PERi'}


def titled(name):
    """Chains that write names in capitals: 'ALL THE GREENS' -> 'All the Greens', 'BBQ BEEF' -> 'BBQ Beef'."""
    if name != name.upper():
        return name
    words = [w if w in KEEP_UPPER else w.capitalize() for w in name.split(' ')]
    words = [w.lower() if i and w in SMALL_WORDS else w for i, w in enumerate(words)]
    return re.sub(r"(?<=[-/'’&(])([a-z])(?=[a-z]{2})", lambda m: m.group(1).upper(), ' '.join(words))


def mcd_za():
    """mcdonalds.co.za item pages (mcd-za-scrape.js). Each size is a button carrying its own figures. Meal and Happy Meal pages
    are left out (a meal is its parts, which are all here), and so are items whose page has no Calories or protein."""
    data = json.loads((HERE / 'mcd-za-source.json').read_text())
    CHECKED['za-mcd'] = data['checked']
    rows = []
    for o in data['items']:
        if o.get('err') or not o.get('name'):
            continue
        name = us.clean(o['name']).replace('’', "'")
        if re.search(r'\bmeal\b|happy meal|with filter coffee|& glazed doughnut', name, re.I) or set(o['cats']) <= {'combo-meals', 'happy-meal'}:
            continue
        name = re.sub(r'^(\d+) Piece (.+)$', r'\2 (\1 pc)', name)
        name = {'Chilli Cheese Double burger': 'Chilli Cheese Double Burger', 'Caramel muffin': 'Caramel Muffin', 'Fries': 'Fries'}.get(name, name)
        groups = o['cats']
        text = ' '.join(o['allergens'])
        al = may = None
        if re.search(r'no allergens', text, re.I):
            al = []
        elif o['allergens']:
            spaced = [re.sub(r'(?<=[a-z)])(?=[A-Z])', ' ', a) for a in o['allergens']]         # "WheatSoya", "Cow's MilkEggWheat (Gluten)Soy"
            contains = ' '.join(a for a in spaced if not re.search(r'may contain|ingredients:', a, re.I))
            al = menu_feeds.allergen_mentions(contains.replace('\xa0', ' ').replace('Nuts', 'tree nuts'))
            may = menu_feeds.allergen_mentions(' '.join(a for a in o['allergens'] if re.search(r'may contain', a, re.I)).replace('nuts', 'tree nuts')) or None
        sized_rows = [(s['label'].replace('Meduim', 'Medium'), {'cal': s['product_cals'], 'fat': s['product_fats'], 'carbs': s['product_carbs'],
                                                                'protein': s['product_protein'], 'sat': s.get('table_satfat'), 'sodium': s.get('table_sodium'),
                                                                'fibre': s.get('table_fiber'), 'sugar': s.get('table_sugars')}) for s in o['sizes']]
        for label, n in sized_rows or [('', o['n'])]:
            cal, p = fnum(n['cal']), fnum(n['protein'])
            if cal is None or p is None:
                continue
            full = f'{name} ({label.lower()})' if label else name
            nut = {'sat': fnum(n['sat']), 'sugar': fnum(n['sugar']), 'fibre': fnum(n['fibre']), 'sodium': fnum(n['sodium'])}
            cat = mcd_cat(full, groups)
            if re.search(r'sandwich|\broll\b', full, re.I):
                cat = 'main'
            elif 'all-day-breakfast' in groups and name != 'Hash Brown':
                cat = 'breakfast'
            rows.append(row('za-mcd', full, cat, p, fnum(n['carbs']), fnum(n['fat']), '', nut, al, may, cal=cal, src='allergen list'))
    return dedupe(rows)


def nandos_za():
    """The menu feed nandos.co.za/eat/order/menu loads, saved from the browser. Nando's publishes each item per 100 g with its
    serving weight (the site's own per-serving column shows 0), so a serve is worked out from the two. "Energy" is kilojoules,
    whatever the feed's unit says. Left out: items with no serving weight, "+ any side" and kids' meals (the figures are for the
    chicken alone), and rows whose protein, carbohydrate and fat add up to more than 80 g in 100 g (figures entered per serve)."""
    menu = json.loads((HERE / 'nandos-za-source.json').read_text())['data']['menu']
    CHECKED['za-nandos'] = '2026-11-20'                   # when nandos-za-source.json was saved from the site
    comp = {c['id']: c['name'] for c in menu['nutritionalComponents']}
    allergen = {a['id']: a['name'] for a in menu['productAllergens']}
    NOTES = {'Marinade & Basting', 'Disclaimer', 'Chicken Soup Powder', 'Spicy Rice', 'Veggie Patty', 'Halloumi', 'Wedges', 'Salt'}  # ingredient notes, not allergens
    AL = {'Cows Milk': 'milk', 'Egg': 'egg', 'Soya': 'soy', 'Wheat Gluten': 'wheat', 'Sulphur & Sulphur Derivatives': 'sulphites',
          'Sulphur Dioxide': 'sulphites', 'Sulphites': 'sulphites', 'Fish (Anchovy Extract)': 'fish', 'Mustard': None, 'Celery': None}
    group = {ch['destinationId']: c['name'] for c in menu['categories'] for ch in c['children']}
    defs = [d for d in menu['productDefinitions'] if d.get('nutritionalComponents')]
    single = {re.sub(r'\s*\((Single|Sharing)\)\s*$', '', d['name']): d.get('servingSize') for d in defs if '(Single)' in d['name']}
    rows = []
    for d in defs:
        raw = re.sub(r'\s+', ' ', d['name']).strip()
        g = group.get(d['id']) or ''
        serve = d.get('servingSize')
        v = {comp[x['destinationId']]: fnum(x['weight']) for x in d['nutritionalComponents']}
        if re.search(r'livers|4 nando\'s rolls', raw, re.I):
            print(f"  ZA za-nandos: left out {raw}: its figures don't fit a {serve} g serve")
            continue
        if not serve or '+' in raw or g == 'Nandinos' or v.get('Energy') is None or v.get('Protein') is None:
            continue
        p100, c100, f100 = v['Protein'], v.get('Glycaemic Carbohydrate') or 0, v.get('Total Fat') or 0
        if p100 + c100 + f100 > 80:
            print(f"  ZA za-nandos: left out {raw}: {p100 + c100 + f100:g} g of protein, carbohydrate and fat in 100 g")
            continue
        est = 17 * p100 + 17 * c100 + 37 * f100
        if est >= 250 and abs(est - v['Energy']) / est > 1 / 3:
            print(f"  ZA za-nandos: left out {raw}: {v['Energy']:g} kJ per 100 g but its macros add up to {round(est)}")
            continue
        base = re.sub(r'\s*\((Single|Sharing)\)\s*$', '', raw)
        if '(Sharing)' in raw and single.get(base) == serve:
            continue                                         # the sharing side listed with the single side's weight
        name = re.sub(r'\s*\(on (its|their) own\)', '', raw)
        name = re.sub(r'\s*\((Single|Sharing)\)\s*$', lambda m: f' ({m.group(1).lower()})', name)
        name = re.sub(r'\s*\(Full portion\)', ' (full portion)', name)
        name = re.sub(r'^(\d+) (Winglets)$', r'\2 (\1 pc)', name).replace("’", "'").replace('with cheese', 'with Cheese')
        each = lambda k: num(round(v[k] * serve / 100, 1)) if v.get(k) is not None else None
        if g == "125g Nando's Sauces" or re.search(r'\bDip$', name):
            cat, name = 'extra', 'Dipping Sauce: ' + re.sub(r'\s*(Sauce|Dip)$', '', name)
        elif g in ('Treats',) or re.search(r'shake|churros', name, re.I):
            cat = 'drink' if re.search(r'shake', name, re.I) else 'sweet'
        elif re.search(r'\((single|sharing)\)$', name) or re.search(r'rolls?$', name, re.I):
            cat = 'side'
        else:
            cat = 'main'
        ids = [allergen.get(a, '') for a in d.get('allergens') or []]
        al = sorted({AL[a] for a in ids if AL.get(a)} | ({'gluten'} if 'Wheat Gluten' in ids else set()))
        for a in ids:
            assert a in AL or a in NOTES, (raw, a)
        nut = {'sat': each('Of which saturated fat'), 'sugar': each('Of which total sugar'), 'fibre': each('Dietary Fibre'), 'sodium': each('Sodium')}
        vg = 'vegetarian' if re.search(r'^veg\b|\(veg\)|halloumi(?!.*chicken)', name, re.I) and not re.search(r'chicken', name, re.I) else None
        rows.append(row('za-nandos', name, cat, each('Protein'), each('Glycaemic Carbohydrate'), each('Total Fat'), f'{serve} g', nut, al,
                        kj=v['Energy'] * serve / 100, vg=vg, src='allergen list'))
    return dedupe(rows)


KAUAI_GROUPS = {'all-day-breakfast': ('breakfast', ''), 'wraps': ('main', 'Wrap'), 'salad-bowls': ('main', 'Salad'), 'warm-meals': ('main', ''),
                'sourdoughtoasties': ('main', 'Toastie'), 'snacks': ('side', ''), 'smoothies': ('drink', 'Smoothie'),
                'protein-smoothies': ('drink', 'Protein Smoothie'), 'superfood-smoothies': ('drink', 'Smoothie'), 'raw-juices-shots': ('drink', ''),
                'recovery-drinks': ('drink', ''), 'organic-coffee-hot-drinks': ('drink', '')}


def kauai():
    """kauai.co.za menu panels (za-fetch.py). Each panel's table has a per-100 column and one or two serving columns (a serve, or
    350 ml and 500 ml); the serving columns are used. Items whose panel has no table, or no column headings, are left out."""
    data = json.loads((HERE / 'kauai-za-source.json').read_text())
    CHECKED['za-kauai'] = data['checked']
    rows = []
    for o in data['items']:
        if not o['rows'] or o['rows'][0][0] or not any(o['rows'][0]):
            continue
        cat, suffix = KAUAI_GROUPS[o['groups'][0]]
        name = titled(us.clean(o['name']).replace('’', "'"))
        if suffix and not re.search(r'wrap|quesadilla|burrito|salad|noodles|bowl|smoothie|toast|flat$', name, re.I):
            name = f"{name} {'Smoothie' if 'Protein' in name else suffix}"
        name = re.sub(r' Flat$', ' Flat Wrap', name)
        table = {re.sub(r'\s*\(.*?\)', '', r[0]).strip().lower(): r[1:] for r in o['rows'][1:] if r[0]}
        get = lambda key, i: next((fnum(v[i]) for k, v in table.items() if k.startswith(key) and i < len(v)), None)
        al = menu_feeds.allergen_words(', '.join(o['allergens']), f"Kauai {name}") if o['allergens'] is not None else None
        vg = 'vegan' if 'V' in o['tags'] else 'vegetarian' if 'VEG' in o['tags'] else None
        if vg == 'vegan' and al and {'milk', 'egg', 'fish'} & set(al):
            vg = 'vegetarian'                                # tagged vegan, but its own allergen list has milk or egg
        for i, head in enumerate(o['rows'][0][1:]):
            h = head.lower().strip()
            if not h or re.match(r'per 100', h):
                continue
            size = re.search(r'(\d+) ?(ml|g)', h)
            label = f'{size.group(1)} ml' if size and size.group(2) == 'ml' else {'regular wrap': 'regular wrap', 'low carb wrap': 'low carb wrap'}.get(h, '')
            serve = f'{size.group(1)} {size.group(2)}' if size else ''
            kj, p = get('energy', i), get('protein', i)
            if kj is None or p is None or size and size.group(2) == 'ml' and int(size.group(1)) < 50:
                continue
            nut = {'sat': get('of which saturated', i), 'sugar': get('of which total sugar', i), 'fibre': get('dietary fibre', i), 'sodium': get('total sodium', i)}
            rows.append(row('za-kauai', f'{name} ({label})' if label else name, cat, p, get('carbohydrate', i) if get('carbohydrate', i) is not None else get('glycaemic', i),
                            get('total fat', i), serve, nut, al, kj=kj, vg=vg, src='allergen list'))
    return dedupe(rows)


WIMPY_AL = {'GLUTEN': ['gluten'], 'LACTOSE': ['milk'], 'SOYA': ['soy'], 'EGG': ['egg'], 'NUT': ['peanut', 'treenut'], 'SULPHITES': ['sulphites'],
            'WHEAT': ['wheat', 'gluten']}
WIMPY_CATS = {'breakfast': 'breakfast', 'burger': 'main', 'grills': 'main', 'sandwiches-light-meals': 'main', 'kids': 'main', 'desserts': 'sweet',
              'drinks': 'drink'}


def wimpy():
    """wimpy.co.za classic menu pages (za-fetch.py): the table behind each item's card, as plated. Left out: items with only an
    energy figure, and any set of figures Wimpy lists under more than one item (Brekkie Bun, Mzansi Brekkie and Early Bird share
    one row; so do the 300 g and 600 g ribs), since there's no telling whose they are."""
    data = json.loads((HERE / 'wimpy-za-source.json').read_text())
    CHECKED['za-wimpy'] = data['checked']
    key = lambda o: tuple(o['n'].get(k) for k in ('TOTAL ENERGY (kJ)', 'PROTEIN (g)', 'CARB (g)', 'TOTAL FAT (g)'))
    seen = {}
    for o in data['items']:
        seen.setdefault(key(o), set()).add(o['name'])
    rows = []
    for o in data['items']:
        n = o['n']
        kj, p = fnum(n.get('TOTAL ENERGY (kJ)')), fnum(n.get('PROTEIN (g)'))
        if kj is None or p is None:
            continue
        if len(seen[key(o)]) > 1:
            print(f"  ZA za-wimpy: left out {o['name']}: same figures as {', '.join(sorted(seen[key(o)] - {o['name']}))}")
            continue
        name = us.clean(o['name']).replace('’', "'").replace('*', '').replace(' ®', '')
        name = re.sub(r'^NEW & IMPROVED\s+', '', name).replace('...', '')
        name = re.sub(r'\s+', ' ', name).strip()
        sec, low = o['section'], name.lower()
        if sec in ('Classic Burgers', 'Big Eat Burgers') and not re.search(r'burger|combo|meal', low):
            name += ' Burger'
        elif sec == 'Toasteds & lighter meals' and not re.search(r'salad|wrap|dagwood', low):
            name = 'Toasted ' + name
        elif sec == 'Iced Coffees' and 'frappe' not in low:
            name += ' Iced Coffee'
        elif sec == 'Frozen Lemonades' and 'smoothie' not in low:
            name += ' Frozen Lemonade'
        elif sec == 'Chill Shakes' and 'shake' not in low:
            name += ' Shake'
        elif sec == 'Sharing Jugs':
            name += ' Sharing Jug'
        elif sec == 'Kids' and not re.match(r"kids", low):
            name = "Kids' " + name
        cat = WIMPY_CATS[o['page']]
        if cat == 'drink' and re.search(r'muffin', low):
            cat = 'sweet'
        if o['page'] == 'kids' and re.search(r'scrambled|breakfast', low):
            cat = 'breakfast'
        elif o['page'] == 'kids' and re.search(r'waffle', low):
            cat = 'sweet'
        elif o['page'] == 'kids' and re.search(r'candy|cooler', low):
            cat = 'drink'
        al = sorted({k for a, yes in o['allergens'].items() if yes == 'y' for k in WIMPY_AL[a]}) if o['allergens'] else None
        nut = {'sat': fnum(n.get('SAT FAT (g)')), 'sugar': fnum(n.get('SUGAR (g)')), 'fibre': fnum(n.get('DIETARY FIBRE (g)')), 'sodium': fnum(n.get('TOTAL SODIUM (mg)'))}
        rows.append(row('za-wimpy', name, cat, p, fnum(n.get('CARB (g)')), fnum(n.get('TOTAL FAT (g)')), '', nut, al, kj=kj, src='allergen table'))
    return dedupe(rows)


DEB_AL = {'Gluten': ['gluten'], 'Soya': ['soy'], 'Cows Milk': ['milk'], 'Egg': ['egg'], 'Nuts': ['peanut', 'treenut'], 'Sulphates': ['sulphites'],
          'Wheat': ['wheat', 'gluten']}


def debonairs():
    """debonairspizza.co.za Nutritional & Allergen Guide (za-fetch.py). Pizzas are the whole pizza, one row per size. Left out:
    bases, sauces and toppings on their own, the two Specialty rows named only "Chicken" and "Meaty", and any pizza whose sizes
    don't rise in order (BBQ Beef's small is larger than its medium on the site)."""
    data = json.loads((HERE / 'debonairs-za-source.json').read_text())
    CHECKED['za-debonairs'] = data['checked']
    allergens = {}
    for a in data['allergens']:
        allergens.setdefault(a['name'].upper().strip(), set()).add(tuple(sorted(k for label, x in a['al'].items() if x.strip() for k in DEB_AL.get(label, []))))
        for label in a['al']:
            assert label in DEB_AL, label
    wraps = {tuple(z['n'].values()) for o in data['items'] if o['section'].upper().startswith('PIZZAWRAP') for z in o['sizes']}
    rows = []
    for o in data['items']:
        sec = o['section'].upper()
        raw = re.sub(r'\s*<br>\s*', '', o['name']).strip()
        if sec in ('BASE', 'SAUCES', 'EXTRAS') or sec == 'SPECIALTY' and raw in ('Chicken', 'Meaty'):
            continue
        name = us.clean(titled(re.sub(r'\s*\(Halaal version:.*?\)', '', raw))).replace('Triple- Decker', 'Triple-Decker').replace('JalapeÃ±o', 'Jalapeño')
        name = re.sub(r'^(\d+) (.+ Wings)$', r'\2 (\1 pc)', name)
        wrap = sec.startswith('PIZZAWRAP')
        if not wrap and sec != 'SIDES' and all(tuple(z['n'].values()) in wraps for z in o['sizes']):
            continue                                         # a Pizzawrap's row repeated under the pizzas
        sizes = [z for z in o['sizes'] if (fnum(z['n'].get('Energy (kJ)')) or 0) < 20000]
        order = [fnum(z['n'].get('Energy (kJ)')) for z in sizes if z['label'].lower() in ('small', 'medium', 'large')]
        if order != sorted(order) or len({z['label'] for z in sizes}) < len(sizes):
            print(f"  ZA za-debonairs: left out {name}: its sizes are out of order on the site ({', '.join(z['label'] + ' ' + z['n'].get('Energy (kJ)', '') for z in o['sizes'])})")
            continue
        found = allergens.get(raw.upper(), set())
        al = sorted(next(iter(found))) if len(found) == 1 and next(iter(found)) else None    # a row with nothing ticked isn't "no allergens" for a pizza
        for z in sizes:
            n, label = z['n'], z['label'].lower()
            kj, p = fnum(n.get('Energy (kJ)')), fnum(n.get('Protein (g)'))
            if kj is None or p is None:
                continue
            if sec == 'SIDES':
                full, cat, serve = menu_feeds.sized(name), 'sweet' if 'chocolate' in name.lower() else 'side', ''
            elif wrap:
                full, cat, serve = f'{name} Pizzawrap', 'main', '1 Pizzawrap'
            else:
                full, cat, serve = f"{name}{'' if 'Triple-Decker' in name else ' Pizza'} ({label})", 'main', f'1 whole {label} pizza'
            nut = {'fibre': fnum(n.get('Dietary Fibre (g)')), 'sodium': fnum(n.get('Total Sodium (mg)'))}
            nut = {k: v for k, v in nut.items() if v is not None and v >= 0}     # the guide lists minus fibre for two rows
            vg = 'vegetarian' if re.search(r'veggie|margherita', name, re.I) else None
            rows.append(row('za-debonairs', full, cat, num(round(p, 1)), num(round(fnum(n.get('Carbohydrates (g)')) or 0, 1)), num(round(fnum(n.get('Fat (g)')) or 0, 1)),
                            serve, nut, al, kj=kj, vg=vg, src='allergen table'))
    return dedupe(rows)


# ---------- India ----------
def mcd_in():
    """McDonald's India (North & East) menu booklet, read page by page (in-extract.py mcd). One size an item, as the booklet has it.
    McDonald's India (West & South) is a separate company that publishes Calories only, so its figures aren't used."""
    data = json.loads((HERE / 'mcd-in-source.json').read_text())
    CHECKED['in-mcd'] = data['checked']
    rows = []
    for o in data['items']:
        n = {k: fnum(v) for k, v in o['n'].items()}
        if n.get('cal') is None or n.get('protein') is None or n.get('carbs') is None or n.get('fat') is None:
            continue
        name = us.clean(o['name']).replace('PaneerBurger', 'Paneer Burger').replace('Filet O Fish', 'Filet-O-Fish').replace('Egg McWrap', 'Egg McWrap')
        name = {'Our World Famous Fries': 'Fries', 'Sundae (Chocolate)': 'Chocolate Sundae', 'Sundae (Strawberry)': 'Strawberry Sundae',
                'Sundae (Chocolate Brownie)': 'Chocolate Brownie Sundae', 'McFlurry (Oreo)': 'Oreo McFlurry', 'McFlurry (Choco Crunch)': 'Choco Crunch McFlurry'}.get(name, name)
        sec, low = o['section'].upper(), name.lower()
        if re.search(r'hash brown|fries|puff', low):
            cat = 'side'
        elif sec.startswith('MCCAF'):
            cat = 'sweet' if re.search(r'cookie|croissant|cheesecake', low) else 'main' if 'toasty' in low else 'drink'
        elif sec == 'DESSERTS':
            cat = 'sweet'
        elif sec == 'BREAKFAST':
            cat = 'drink' if 'cappuccino' in low else 'breakfast'
        else:
            cat = 'main'
        text = re.sub(r'(?i)cereal containing\s*(gluten)?', 'gluten ', (o['allergens'] or '')).replace('Nuts', 'tree nuts')   # "Cereal containinggluten", "Cereal containing Milk"
        al = [] if re.search(r'no allergens', text, re.I) else menu_feeds.allergen_mentions(text) if text.strip() else None
        nut = {'sat': n.get('sat'), 'sugar': n.get('sugar'), 'sodium': n.get('sodium')}
        rows.append(row('in-mcd', name, cat, n['protein'], n['carbs'], n['fat'], '', nut, al, cal=n['cal'], src='allergen list'))
    return dedupe(rows)


KFC_IN_NAMES = [(r'\bHC Leg\b', 'Hot & Crispy Leg Piece'), (r'\bHC chicken\b', 'Hot & Crispy Chicken'), (r'\bHC\b', 'Hot & Crispy Chicken'),
                (r'Piripiri', 'Peri Peri'), (r'Bonless', 'Boneless'), (r'Chiken', 'Chicken'), (r'Buger', 'Burger'), (r'Chatpta Channa', 'Chatpata Chana'),
                (r'Ricebowl', 'Rice Bowl'), (r'^Popcorn\b(?! Chicken)', 'Popcorn Chicken'), (r'\bstrips\b', 'Strips'), (r'\bleg\b', 'Leg'),
                (r'^Smoky$', 'Smoky Grilled Chicken'), (r'\bDew\b', 'Mountain Dew'), (r'^7 ?[Uu]p\b', '7UP'), (r'Nashvillle', 'Nashville'),
                (r'\bthousand\b', 'Thousand'), (r'Mousse cake \( Coffee Flavoured\)', 'Coffee Mousse Cake'), (r'Andra Rice', 'Andhra Rice')]


def kfc_in():
    """KFC India Nutrition Information booklet (in-extract.py kfc). The booklet gives a serve's share for bigger packs ("3 Pc" as two
    serves), so only rows that are one serve are used. Allergens and the veg mark are pictures in the booklet, so they're unknown."""
    data = json.loads((HERE / 'kfc-in-source.json').read_text())
    CHECKED['in-kfc'] = data['checked']
    rows = []
    for o in data['items']:
        if o['servings'] != 1 or re.search(r'bottle|seasoning', o['name'], re.I):
            continue
        name = o['name']
        for a, b in KFC_IN_NAMES:
            name = re.sub(a, b, name)
        name = re.sub(r'^(\d+) Pc (.+)$', r'\2 (\1 pc)', name)
        name = re.sub(r'^Smoky(?= \()', 'Smoky Grilled Chicken', name)
        name = re.sub(r'^Boneless Wing(?= \()', 'Boneless Wings', re.sub(r'^Peri Peri Strip(?= \()', 'Peri Peri Strips', name))
        name = re.sub(r'^(.+) (Regular|Medium|Large|Single|Double)$', lambda m: f'{m.group(1)} ({m.group(2).lower()})', name)
        name = re.sub(r'^(Single|Double) (Veg Patty)$', lambda m: f'{m.group(2)} ({m.group(1).lower()})', name)
        sec, low = o['section'], name.lower()
        if re.search(r'cola|krushers|pepsico', sec, re.I):
            cat = 'drink'
        elif sec == 'French Fries' or 'veg patty' in low:
            cat = 'side'
        elif sec == 'Sides & Desserts':
            cat = 'sweet'
        elif sec.startswith('Dips'):
            cat, name = 'extra', 'Dipping Sauce: ' + re.sub(r'\s*Dip$', '', name)
        else:
            cat = 'main'
        if cat == 'drink' and o['protein'] > o['carbs']:
            print(f"  IN in-kfc: left out {name}: a drink listed with {num(o['protein'])} g protein and {num(o['carbs'])} g carbohydrate")
            continue
        if cat == 'drink':
            name = re.sub(r' (Can|Pet)$', lambda m: ' (can)' if m.group(1) == 'Can' else ' (bottle)', name)
        nut = {'sat': num(o['sat']), 'sugar': num(o['sugar']), 'sodium': num(o['sodium'])}
        rows.append(row('in-kfc', name, cat, num(o['protein']), num(o['carbs']), num(o['fat']), f"{num(o['weight'])} g" if cat != 'drink' else '', nut, cal=num(o['cal'])))
    return dedupe(rows)


PH_SKIP = r'3-IN-1|Half N Half|Dips|Crust Upgrade|Golden Hand Stretched'
PH_CRUST = [('TnC', 'thin n crispy'), ('Pan', 'pan'), ('Ultimate Cheese', 'ultimate cheese'), ('Spicy Range Pizzas', 'pan'), ('Flavour Fun', 'personal')]


def pizzahut_in():
    """Pizza Hut India Nutrition & Allergen Information Booklet (in-extract.py pizzahut). A pizza row is the whole pizza: its weight
    and number of slices are in the serve. Left out: dips, crust upgrades on their own, half-and-half and 3-in-1 pizzas (the booklet
    doesn't name their halves clearly) and the hand-stretched page, whose names don't read as items."""
    data = json.loads((HERE / 'pizzahut-in-source.json').read_text())
    CHECKED['in-pizzahut'] = data['checked']
    val = lambda o, k: fnum(o.get(k)) if o.get(k) not in (None, 'ND', '-', 'NA', 'BLQ') else None
    rows, taken = [], set()
    for o in data['items']:
        sec = o['section']
        if re.search(PH_SKIP, sec):
            continue
        cal, p = val(o, 'cal'), val(o, 'protein')
        if cal is None or p is None and 'Beverages' not in sec:
            continue
        name = re.sub(r'\s+', ' ', o['name'].replace('}', ')').replace('`', "'").replace('–', '-')).strip()
        name = re.sub(r'\s*\((\d+) ?pc\.?\)', '', name)
        name = re.sub(r'^Non ?- ?Veg ', 'Chicken ', name).replace('Masal Pepsi', 'Masala Pepsi').replace('7 up', '7UP').replace('7 UP', '7UP')
        size = re.search(r'\(?\b(Personal|Medium|Large)\)?', name)
        by_slices = {'4': 'personal', '6': 'medium', '8': 'large'}.get(str(o.get('count')))
        base = re.sub(r'\s*\(?\b(Personal|Medium|Large)\)?', '', name) if size else name
        base = re.sub(r'\s*\b(TnC|TNC|Pan|Ultimate Cheese)\b', '', base).replace('Pizza Pizza', 'Pizza').strip()
        base = re.sub(r'\s+Pizza$', '', base)
        count, weight = val(o, 'count'), val(o, 'weight')
        low = base.lower()
        if re.search(r'pizza|flatzz', sec, re.I):
            crust = next((label for key, label in PH_CRUST if key in sec), '')
            said = size.group(1).lower() if size else ''
            if said and crust == 'pan' and by_slices and said != by_slices:
                said = by_slices                             # "Double Chicken Delight (Personal)" with 6 slices and 550 g is the medium
            label = ' '.join(x for x in (said, crust) if x)
            label = {'personal personal': 'personal'}.get(label, label)
            full = f"{base} {'Flatzz' if 'Flatzz' in sec else 'Pizza'}" + (f' ({label})' if label else '')
            cat, serve = 'main', f"1 whole pizza, {num(count)} slices ({num(weight)} g)" if count else f'{num(weight)} g'
        elif sec == 'Beverages':
            full, cat, serve = f'{base} ({num(weight)} ml)', 'drink', f'{num(weight)} ml'
        else:
            cat = {'Melts': 'main', 'Pastas': 'main', 'Dessert': 'sweet'}.get(sec, 'main' if 'wing' in low else 'side')
            full = base + (' Melt' if sec == 'Melts' else '') + (' Fries' if 'Fries' in sec and 'fries' not in low else '')
            if 'wing' in low and count:
                full = re.sub(r'\bWing\b', 'Wings', re.sub(r'\bwings\b', 'Wings', full)) + f' ({num(count)} pc)'
            serve = f'{num(weight)} g'
        al = menu_feeds.allergen_mentions(o['allergens']) if o['allergens'].strip() else None
        nut = {'sat': val(o, 'sat'), 'sugar': val(o, 'sugar'), 'fibre': val(o, 'fibre'), 'sodium': val(o, 'sodium')}
        r1 = lambda x: num(round(x or 0, 1))
        if full in taken:                                    # the booklet lists a veg and a chicken version under one name; the weight tells them apart
            full = f'{full[:-1]}, {num(weight)} g)' if full.endswith(')') else f'{full} ({num(weight)} g)'
        taken.add(full)
        rows.append(row('in-pizzahut', full, cat, r1(p), r1(val(o, 'carbs')), r1(val(o, 'fat')), serve, {k: (r1(v) if v is not None else None) for k, v in nut.items()},
                        al, cal=round(cal), src='allergen list'))
    return dedupe(rows)


COUNTRIES = {
    'CA': [
        ({'id': 'ca-mcd', 'name': "McDonald's", 'how': 'Official website item pages', 'url': 'https://www.mcdonalds.com/ca/en-ca/full-menu.html',
          'src': "mcdonalds.com (Canada) item nutrition, every size McDonald's lists ({checked}). Allergens are McDonald's own list for each item"},
         lambda: mcd('ca', 'ca-mcd')),
        ({'id': 'ca-bk', 'name': 'Burger King', 'how': 'Official Nutrition Explorer', 'url': 'https://www.burgerking.ca/nutrition-explorer',
          'src': "Burger King Canada Nutrition Explorer ({checked}), each item as served with its standard toppings. May-contain includes shared cooking equipment"},
         bk_ca),
        ({'id': 'ca-tims', 'name': 'Tim Hortons', 'how': 'Official nutrition guide', 'url': 'https://www.timhortons.ca/nutrition-and-allergens',
          'src': "Tim Hortons Nutrition Information, Canadian edition ({checked}). Iced Capps, Chai Latte and London Fog are left out: their rows couldn't be read reliably from the guide. No allergens yet: they're in a separate chart"},
         tims),
    ],
    'GB': [
        ({'id': 'uk-mcd', 'name': "McDonald's", 'how': 'Official website item pages', 'url': 'https://www.mcdonalds.com/gb/en-gb/menu.html',
          'src': "mcdonalds.com (UK) item nutrition ({checked}). Sodium is worked out from the salt McDonald's lists. No allergens: the UK feed marks some items with every allergen"},
         lambda: mcd('uk', 'uk-mcd')),
        ({'id': 'uk-greggs', 'name': 'Greggs', 'how': 'Official menu nutrition', 'url': 'https://www.greggs.com/menu',
          'src': "Greggs menu nutrition and allergens ({checked}). Sodium is worked out from the salt Greggs lists. Pizza boxes are the whole box"},
         greggs),
    ],
    'NZ': [
        ({'id': 'nz-mcd', 'name': "McDonald's", 'how': 'Official website item pages', 'url': 'https://www.mcdonalds.com/nz/en-nz/menu.html',
          'src': "mcdonalds.com (New Zealand) item nutrition ({checked}). Allergens are McDonald's own list for each item. Some items list less fat than their energy implies (the Big Mac); they're kept as published, and items more than a third out are left out"},
         lambda: mcd('nz', 'nz-mcd')),
        ({'id': 'nz-dominos', 'name': "Domino's", 'how': 'Official nutrition page', 'url': 'https://www.dominos.co.nz/menu/nutritional-information/',
          'src': "Domino's New Zealand Nutritional Information ({checked}). Pizzas are per slice, one row per crust"},
         dominos_nz),
    ],
    'ZA': [
        ({'id': 'za-mcd', 'name': "McDonald's", 'how': 'Official website item pages', 'url': 'https://www.mcdonalds.co.za/menu',
          'src': "mcdonalds.co.za item nutrition, every size McDonald's lists ({checked}). McDonald's South Africa publishes Calories; kilojoules are worked out. Allergens are McDonald's own list for each item. Items whose energy is more than a third away from their macros are left out"},
         mcd_za),
        ({'id': 'za-nandos', 'name': "Nando's", 'how': 'Official online menu', 'url': 'https://www.nandos.co.za/eat/order/menu',
          'src': "Nando's South Africa online menu, Allergens & Nutritional Info ({checked}). Nando's lists each item per 100 g with its serving weight; a serve is worked out from the two. Items with no serving weight are left out"},
         nandos_za),
        ({'id': 'za-wimpy', 'name': 'Wimpy', 'how': 'Official menu nutrition', 'url': 'https://wimpy.co.za/classic-menu/burger/',
          'src': "Wimpy South Africa classic menu nutrition and allergens ({checked}), each item as Wimpy lists it. Figures Wimpy shows under more than one item are left out. Nut means peanuts or tree nuts"},
         wimpy),
        ({'id': 'za-debonairs', 'name': 'Debonairs Pizza', 'how': 'Official nutritional guide', 'url': 'https://debonairspizza.co.za/nutritional-and-allergen-guide/',
          'src': "Debonairs Pizza Nutritional & Allergen Guide ({checked}). Pizzas are the whole pizza, one row per size. Nuts means peanuts or tree nuts"},
         debonairs),
        ({'id': 'za-kauai', 'name': 'Kauai', 'how': 'Official menu nutrition', 'url': 'https://kauai.co.za/menu/',
          'src': "Kauai menu nutrition and allergens ({checked}), per serving as ready to eat. Smoothies are listed at 350 ml and 500 ml"},
         kauai),
    ],
    'IN': [
        ({'id': 'in-mcd', 'name': "McDonald's", 'how': 'Official menu booklet', 'url': 'https://mcdindia.com/',
          'src': "McDonald's India (North & East) menu booklet with nutrition and allergens ({checked}). McDonald's India publishes Calories; kilojoules are worked out. Restaurants in the west and south are run by a different company that publishes Calories only, and their recipes can differ"},
         mcd_in),
        ({'id': 'in-kfc', 'name': 'KFC', 'how': 'Official nutrition booklet', 'url': 'https://online.kfc.co.in/',
          'src': "KFC India Nutrition Information booklet, version 6 ({checked}), one serve of each item. Calories as published; kilojoules are worked out. No allergens: the booklet shows them as pictures"},
         kfc_in),
        ({'id': 'in-pizzahut', 'name': 'Pizza Hut', 'how': 'Official nutrition booklet', 'url': 'https://www.pizzahut.co.in/nutrition/',
          'src': "Pizza Hut India Nutrition & Allergen Information Booklet ({checked}). Pizzas are the whole pizza, one row per size and crust. Calories as published; kilojoules are worked out"},
         pizzahut_in),
    ],
}


def misprinted(f):
    """Published energy over a third away from its own macros (4/4/9), or kJ and Calories that disagree: the same rule the
    Australian menus use. Small items (under 60 Cal) are let through, since rounding swamps them."""
    est = 4 * f['p'] + 4 * (f['c'] or 0) + 9 * (f['f'] or 0)
    if f['cal'] >= 60 and abs(est - f['cal']) / f['cal'] > 1 / 3:
        return f"{f['cal']} Cal but its macros add up to {round(est)}"
    if f['cal'] >= 20 and abs(f['kj'] / 4.184 - f['cal']) / f['cal'] > 0.15:
        return f"{f['cal']} Cal but {f['kj']} kJ"
    sat = (f.get('nut') or {}).get('sat')
    if sat is not None and f['f'] is not None and sat > f['f'] + 0.5:
        return f"{sat} g saturated fat but {f['f']} g fat"
    return None


def build(country, chains):
    foods = []
    for chain, fn in chains:
        rows = []
        for r in fn():
            why = misprinted(r)
            if country in ('ZA', 'IN'):
                est = 4 * r['p'] + 4 * (r['c'] or 0) + 9 * (r['f'] or 0)
                if not why and est >= 30 and r['cal'] < est / 2:
                    why = f"{r['cal']} Cal but its macros add up to {round(est)}"
                if country == 'IN' and 'diet' in r and 'meat' in r['diet']:
                    # These chains sell no beef or pork in India: burgers are chicken, fish or vegetarian, and sausage, pepperoni and keema are chicken.
                    low = r['name'].lower()
                    kept = [m for m in r['diet']['meat'] if m in ('chicken', 'fish')]
                    if not kept and re.search(r'sausage|pepperoni|keema|zinger(?! fillet)|leg\b|strips|drums|chizza|double down|krisper', low) and not re.search(r'\bveg|paneer', low):
                        kept = ['chicken']
                    if kept or re.search(r'\bveg|veggie|paneer|aloo|margherita|corn\b', low):
                        r['diet']['meat'] = kept
                    else:
                        del r['diet']['meat']
                        if set(r['diet']) <= {'src'}:
                            del r['diet']
                meat = r.get('diet', {}).get('meat') or []
                if 'beef' in meat and re.search(r'chicken', r['name'], re.I) and not re.search(r'beef|steak|meaty', r['name'], re.I):
                    meat.remove('beef')
            if why:
                print(f"  {country} {r['chain']}: left out {r['name']}: {why}")
            else:
                rows.append(r)
        foods += rows
    ids = [f['id'] for f in foods]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise SystemExit(f'{country}: duplicate menu IDs {sorted(dupes)}')
    for f in foods:
        for k in f.get('diet', {}).get('al', []) + f.get('diet', {}).get('may', []):
            assert k in menu_feeds.APP_KEYS, (f['id'], k)
    when = lambda c: datetime.strptime(CHECKED[c], '%Y-%m-%d').strftime('%-d %b %Y')
    meta = [{'id': 'mine', 'name': 'My foods'}] + [dict(c, src=c['src'].format(checked=when(c['id']))) for c, _ in chains]
    out = APP / f'MenuData-{country}.json'
    revision = hashlib.sha256(json.dumps({'chains': meta, 'foods': foods}, sort_keys=True).encode()).hexdigest()[:16]
    published = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.000Z')
    try:
        prev = json.loads(out.read_text())
        if prev.get('revision') == revision:
            published = prev['published']
    except FileNotFoundError:
        pass
    out.write_text(json.dumps({'format': 1, 'country': country, 'revision': revision, 'published': published, 'chains': meta, 'foods': foods},
                              ensure_ascii=False, separators=(',', ':')))
    by = {c['id']: sum(f['chain'] == c['id'] for f in foods) for c in meta[1:]}
    print(f'{country}: {len(foods)} foods: ' + ', '.join(f'{c["name"]} {by[c["id"]]}' for c in meta[1:]))


if __name__ == '__main__':
    for country, chains in COUNTRIES.items():
        build(country, chains)
