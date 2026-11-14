#!/usr/bin/env python3
"""Builds the Canadian, British and New Zealand restaurant menus, bundled with the app beside MenuData.json (Australia) and
MenuData-US.json, in the same format:

  ios/MacroMenu/MenuData-CA.json  McDonald's, Burger King, Tim Hortons
  ios/MacroMenu/MenuData-GB.json  McDonald's, Greggs
  ios/MacroMenu/MenuData-NZ.json  McDonald's, Domino's

Each chain's own published figures, saved beside this file:
  McDonald's (CA, UK, NZ)  mcd-intl-scrape.js in a browser on the country's McDonald's site -> mcd-<cc>-source.json
  Burger King Canada       burgerking.ca/nutrition-explorer's feed, saved from the browser  -> bk-ca-source.json
  Tim Hortons              Nutrition Information PDF via extract-pdf-tables.py               -> th-ca-source.json
  Greggs                   the menu feed greggs.com/menu loads, saved from the browser       -> greggs-uk-source.json
  Domino's New Zealand     dominos.co.nz/menu/nutritional-information, every crust, read in the browser -> dominos-nz-source.json

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
            not re.search(r'muffin|cookie(?! butter)|cake|sundae|mcflurry|loaf|pie\b|croissant|wrap|burger|bagel|porridge|sauce|dip\b', low):
        return 'drink'
    if re.search(r'condiment|sauces', g) and not re.search(r'sandwich|donut|hotcake|mcdip', low) or re.search(SAUCE, low) and \
            not re.search(r'burger|mcmuffin|wrap|chicken|nugget|fries|bagel|pancake|hotcake|porridge|muffin|sandwich|donut|doughnut|mcdip|cone', low):
        return 'extra'
    if re.search(SWEET, low) and not re.search(r'english muffin|mcmuffin|muffin &|muffin with', low) or re.search(r'dessert', g):
        return 'sweet'
    if (re.search(r'breakfast', g) or re.search(r'breakfast|brekkie|mcmuffin|hotcake|pancake|bagel|bacon roll|porridge|oatmeal|oats\b', low)) \
            and not re.search(r'salad|apple slices|carrot|fruit bag', low):
        return 'breakfast'
    if re.search(r'fries|wedges|salad\b|side|carrot|corn|poutine|apple|grapes|onion rings|cheese bites|mozzarella|hash', low) and \
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
