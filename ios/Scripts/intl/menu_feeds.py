"""Readers shared by the US build (us/build-us-menu.py) and the Canada/UK/NZ build (intl/build-intl-menu.py).

- `rbi_items`: Burger King's Nutrition Explorer feed. bk.com and burgerking.ca load it from Sanity when the page opens
  (GraphQL operation staticNutritionPage); save that response from the browser as the chain's source file.
- `allergen_words`: allergen statements written as text ("Contains Barley, Milk, Soy, Wheat.") into the app's keys (Diet.swift).
"""
import json
import re

APP_KEYS = {'gluten', 'wheat', 'milk', 'egg', 'soy', 'sesame', 'peanut', 'treenut', 'fish', 'shellfish', 'lupin', 'sulphites'}
# Words chains use, mapped to the app's keys. Cereals with gluten count as gluten; crustaceans and molluscs as shellfish.
WORDS = {
    'milk': 'milk', 'dairy': 'milk', 'dairy / milk': 'milk', 'lactose': 'milk',
    'egg': 'egg', 'eggs': 'egg',
    'soy': 'soy', 'soya': 'soy', 'soybean': 'soy', 'soybeans': 'soy', 'soy bean': 'soy',
    'wheat': 'wheat', 'gluten': 'gluten', 'barley': 'gluten', 'rye': 'gluten', 'oats': 'gluten', 'oat': 'gluten', 'triticale': 'gluten',
    'spelt': 'gluten', 'cereals containing gluten': 'gluten',
    'sesame': 'sesame', 'sesame seeds': 'sesame', 'sesame seed': 'sesame',
    'peanut': 'peanut', 'peanuts': 'peanut',
    'tree nuts': 'treenut', 'tree nut': 'treenut', 'nuts': 'treenut', 'almond': 'treenut', 'almonds': 'treenut', 'hazelnut': 'treenut',
    'hazelnuts': 'treenut', 'cashew': 'treenut', 'pecan': 'treenut', 'pecans': 'treenut', 'walnut': 'treenut', 'walnuts': 'treenut',
    'pistachio': 'treenut', 'macadamia': 'treenut', 'brazil nut': 'treenut', 'pine nut': 'treenut',
    'fish': 'fish', 'shellfish': 'shellfish', 'crustacean': 'shellfish', 'crustaceans': 'shellfish', 'crustacea': 'shellfish',
    'mollusc': 'shellfish', 'molluscs': 'shellfish', 'mollusks': 'shellfish', 'prawn': 'shellfish',
    'lupin': 'lupin', 'lupine': 'lupin',
    'sulphites': 'sulphites', 'sulphite': 'sulphites', 'sulfites': 'sulphites', 'sulphur dioxide': 'sulphites', 'sulphur dioxide/sulphites': 'sulphites',
}
# Allergens the app has no filter for, and words that aren't allergens. Mustard and celery are EU/UK/Canadian allergens.
IGNORE = {'mustard', 'celery', 'caffeine', 'phenylalanine', 'msg', 'none', 'and', ''}


def allergen_words(text, where):
    """'Contains: Milk, Soy, Gluten (Wheat) ,' -> ['gluten', 'milk', 'soy', 'wheat']."""
    text = re.sub(r'(?i)\b(may )?contains?:?|\bmay contain\b|\btraces? of\b', ',', text or '')
    out = set()
    for w in re.split(r'[,.;()/]|\band\b', text):
        w = re.sub(r'\s+', ' ', w).strip().lower()
        if w in IGNORE:
            continue
        key = WORDS.get(w)
        if not key:
            raise SystemExit(f'{where}: allergen "{w}" is not one of the app\'s keys; add it to WORDS or IGNORE in menu_feeds.py')
        out.add(key)
        if key == 'wheat':
            out.add('gluten')
    return sorted(out)


def allergen_mentions(text):
    """Every allergen named anywhere in a sentence, for cross-contact notes written as prose ("BACON may be cooked on the same
    equipment as Egg or products containing Gluten, Wheat, Milk, Soy.")."""
    low = (text or '').lower()
    out = {WORDS[w] for w in sorted(WORDS, key=len, reverse=True) if re.search(r'\b' + re.escape(w) + r'\b', low)}
    if 'wheat' in out:
        out.add('gluten')
    return sorted(out)


# Nutrition Explorer allergen values: 3 contains, 2 may contain, 1 may be cooked on shared equipment, 0 doesn't contain
# (from the site's own disclaimer table: '001' contains, '010' may contain, '100' may be cooked on).
RBI_KEYS = {'milk': 'milk', 'eggs': 'egg', 'fish': 'fish', 'peanuts': 'peanut', 'shellfish': 'shellfish', 'treeNuts': 'treenut',
            'soy': 'soy', 'wheat': 'wheat', 'sesame': 'sesame', 'gluten': 'gluten', 'lupin': 'lupin', 'sulphurDioxide': 'sulphites'}


def rbi_items(path):
    """Every item in a Nutrition Explorer feed, once each, with the menu section it was first listed under."""
    data = json.loads(open(path).read())
    if 'data' not in data and isinstance(data.get('body'), str):
        data = json.loads(data['body'])
    items = {}

    def walk(o, section):
        if isinstance(o, dict):
            if o.get('_type') == 'section' and isinstance(o.get('name'), dict):
                section = o['name']['locale']
            if o.get('_type') == 'item' and (o.get('nutritionWithModifiers') or o.get('nutrition')):
                items.setdefault(o['_id'], (section, o))
            for v in o.values():
                walk(v, section)
        elif isinstance(o, list):
            for v in o:
                walk(v, section)

    walk(data['data']['StaticPage']['widgets'][0]['menu'], '')
    out = []
    for section, o in items.values():
        # nutritionWithModifiers is the item as served (a Whopper with its patty, cheese and sauce); `nutrition` is the base alone.
        n = o.get('nutritionWithModifiers') or o['nutrition']
        if n.get('calories') is None or n.get('proteins') is None:
            continue
        a = o.get('allergens') or {}
        known = {k: v for k, v in a.items() if k in RBI_KEYS or k in ('mustard', 'celery')}
        if all(v is None for v in known.values()):
            al = may = None
        else:
            al = sorted({RBI_KEYS[k] for k, v in known.items() if k in RBI_KEYS and v == 3})
            may = sorted({RBI_KEYS[k] for k, v in known.items() if k in RBI_KEYS and v in (1, 2)})
            if 'wheat' in al and 'gluten' not in al:
                al.append('gluten')
                al.sort()
        out.append({'section': section, 'name': o['name']['locale'], 'n': n, 'al': al, 'may': may})
    return out


SIZES = r'Value|Kids|Small|Medium|Large|Extra Large|X Large|XL|Regular|Mini|Snack|Junior|Jr\.?'


def sized(name):
    """A size or count written into a name becomes the app's "(size)" suffix: "Small French Fries" -> "French Fries (small)",
    "Cappuccino - Large" -> "Cappuccino (large)", "8 Pc. Chicken Fries" -> "Chicken Fries (8 pc)"."""
    name = re.sub(r'\s+', ' ', name).strip()
    m = re.match(r'^(\d+) ?(?:Pc\.?|Piece|pieces?|pc|pk|Pack)\.? (.+)$', name, re.I)
    if m:
        return f'{m.group(2)} ({m.group(1)} pc)'
    m = re.match(r'^(.+?)\s*(?:[-–,]\s*|\()\s*(\d+) ?(?:pc|pcs|pk|pack|pieces?|piece)\)?$', name, re.I)
    if m:
        return f'{m.group(1)} ({m.group(2)} pc)'
    m = re.match(rf'^(.+?)\s*(?:[-–,]\s*|\s\(|\s)({SIZES})\)?$', name)
    if m and re.search(r'[-–,(]', name[len(m.group(1)):]) or (m and m.group(2) in ('Small', 'Medium', 'Large', 'Regular', 'Extra Large', 'X Large')):
        return f'{m.group(1)} ({m.group(2).lower().replace("x large", "extra large")})'
    m = re.match(r'^(Value|Kids|Small|Medium|Large|Extra Large|Regular) (.+)$', name)
    if m:
        return f'{m.group(2)} ({m.group(1).lower()})'
    return name
