#!/usr/bin/env python3
"""SaladStop! Singapore -> sg-saladstop-source.json (normalised format, see SOURCE-FORMAT.md).

Source: the menu pages on saladstop.com.sg draw their "Nutrition Calculator" from plain JSON files the site serves at
saladstop.com.sg/wp-content/json/<file>.json (one per menu page: signatures, warm_protein_bowls, ...). Each item has a
nutrition_breakdown (Energy in kcal, protein, fat, carbohydrate, sugars, fibre, sodium) for the item as served. The
Create-Your-Own page's file (cyo.json) gives every dressing and topping with its portion weight; those are kept as extras.

Left out: rows whose energy is far (more than a third) from 4p + 4c + 9f; the cold-pressed juices and immunity shots
(no fat figure published); plain and sparkling water; the salad-leaf bases of Create-Your-Own.
Allergens are not carried: SaladStop's tags are dairy, nuts, gluten, meat, seafood and allium only (no egg, soy, sesame).
SaladStop! is not halal certified: its bacon bits are pork.

Run: python3 ios/Scripts/intl/sg-saladstop-fetch.py
"""
import json
import pathlib
import re
import time
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'sg-saladstop-source.json'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
JSON_BASE = 'https://saladstop.com.sg/wp-content/json/'

# file -> default app category
FILES = ['signatures', 'lto', 'warm_protein_bowls', 'warm_bowls', 'min-wrap', 'breakfast', 'snacks', 'acai_bowls',
         'smoosha', 'beverages', 'yoghurts_mueslis']


def get_json(name):
    time.sleep(0.3)
    req = urllib.request.Request(JSON_BASE + name + '.json', headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.loads(r.read().decode('utf-8'))


def flat(items):
    out = []
    for g in items:
        out += g if isinstance(g, list) else [g]
    return out


def energy_ok(cal, p, c, f):
    est = 4 * p + 4 * c + 9 * f
    if est < 10 and cal < 10:
        return True
    return abs(cal - est) <= est / 3


MEAT_WORDS = [(r'\bchicken\b', 'chicken'), (r'\bbacon\b', 'pork'), (r'\b(beef|brisket)\b', 'beef'),
              (r'\b(salmon|tuna|fish)\b', 'fish'), (r'\b(prawn|shrimp|ebi)\b', 'seafood'), (r'\blamb\b', 'lamb')]


def meats(text):
    found = []
    for pat, m in MEAT_WORDS:
        if re.search(pat, text, re.I) and m not in found:
            found.append(m)
    return found or None


def vg(diets):
    diets = diets or []
    return 'vegan' if 'vegan' in diets else 'vegetarian' if 'vegetarian' in diets else None


def name_and_cat(file, x):
    label = re.sub(r'\s+', ' ', x['label']).strip()
    kind = (x.get('category') or '').strip()
    group = (x.get('group') or '').strip().lower()
    if file in ('signatures', 'lto', 'warm_protein_bowls', 'warm_bowls'):
        base = re.sub(r'\s+Bowl$', '', label)
        if base.startswith('Seoulja'):
            base = base.rstrip('!')  # listed as "Seoulja-Boy" (bowl) and "Seoulja-Boy!" (wrap)
        return (f'{base} {kind}' if kind else base), 'main'
    if file == 'min-wrap':
        return f'{label} Wrap', 'main'
    if file == 'breakfast':
        if label in ('Cheesy Veggie', 'Chicken Bacon'):
            return f'{label} Wrap (egg white)', 'breakfast'
        return label, 'breakfast'
    if file == 'snacks':
        if group == 'chicken tenders':
            m = re.match(r'(\w+) \((\d+) pieces\) with (.+)', label)
            return (f'Chicken Tenders {m.group(1)} ({m.group(2)} pieces) with {m.group(3)}' if m else label), 'side'
        return label, ('sweet' if 'cake' in group else 'side')
    if file == 'acai_bowls':
        return (f'{label} Bowl' if 'acai' in label.lower() else f'{label} Acai Bowl'), 'sweet'
    if file == 'smoosha':
        return f'{label} Smoothie', 'drink'
    if file == 'beverages':
        return label, 'drink'
    if file == 'yoghurts_mueslis':
        return label, ('sweet' if group == 'puddings' else 'breakfast')
    return label, 'main'


def main():
    items, dropped, skipped = [], [], []
    seen = set()
    for file in FILES:
        for x in flat(get_json(file)['items']):
            name, cat = name_and_cat(file, x)
            group = (x.get('group') or '').lower()
            if file == 'beverages' and group in ('cold pressed juice', 'immunity shots', 'water'):
                skipped.append(name)
                continue
            nb = {n['label']: n.get('amount') for n in x.get('nutrition_breakdown', []) if 'label' in n}
            cal, p, c, f = nb.get('Energy'), nb.get('Protein'), nb.get('Carbohydrate'), nb.get('Total Fat')
            if None in (cal, p, c, f):
                dropped.append(f'{name} (no fat figure)')
                continue
            if not energy_ok(cal, p, c, f):
                dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
                continue
            if name in seen:
                continue
            seen.add(name)
            items.append({
                'name': name, 'cat': cat, 'serve': '1 serving',
                'cal': int(cal + 0.5), 'kj': None, 'p': p, 'c': c, 'f': f,
                'sat': None, 'sugar': nb.get('Total Sugars'), 'fibre': nb.get('Dietary Fiber'),
                'sodium': nb.get('Sodium'), 'salt': None,
                'contains': None, 'may': None,
                'vg': vg(x.get('diets')),
                'meat': meats(name + ' ' + (x.get('description') or '')),
                '_meat_tag': 'meat' in (x.get('allergens') or []) or 'seafood' in (x.get('allergens') or []),
            })

    # a wrap's description sometimes leaves out the protein its salad lists (Jai Ho! Wrap): borrow it from the sibling
    by_base = {}
    for it in items:
        base = re.sub(r' (Salad|Wrap|Bowl|Mini Wrap)$', '', it['name'])
        if it['meat']:
            by_base.setdefault(base, it['meat'])
    for it in items:
        if not it['meat'] and it['_meat_tag']:
            it['meat'] = by_base.get(re.sub(r' (Salad|Wrap|Bowl|Mini Wrap)$', '', it['name']))
        del it['_meat_tag']

    # Create-Your-Own dressings and toppings (per portion, weight given)
    for x in flat(get_json('cyo')['items']):
        group = (x.get('group') or '').lower()
        if group not in ('dressings', 'toppings', 'sprinkles'):
            continue
        n = x['nutrition']
        label = re.sub(r'\s+', ' ', x['label']).strip()
        label = label[0] + label[1:].lower() if label.isupper() else label
        kind = 'dressing' if group == 'dressings' else 'topping'
        name = f'{label} ({kind})'
        cal, p, c, f = n.get('calories'), n.get('protein'), n.get('carbs'), n.get('total_fat')
        if None in (cal, p, c, f):
            dropped.append(f'{name} (figures missing)')
            continue
        if not energy_ok(cal, p, c, f):
            dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
            continue
        grams = n.get('amount')
        # a portion can't weigh less than its protein + carbs + fat (Fresh Lemon & Oil is listed as 5 g with 14.5 g fat)
        serve = f'1 portion ({grams:g} g)' if grams and grams >= p + c + f else '1 portion'
        items.append({
            'name': name, 'cat': 'extra', 'serve': serve,
            'cal': int(cal + 0.5), 'kj': None, 'p': p, 'c': c, 'f': f,
            'sat': n.get('saturated_fat'), 'sugar': n.get('sugar'), 'fibre': n.get('fiber'),
            'sodium': n.get('sodium'), 'salt': None,
            'contains': None, 'may': None,
            'vg': vg(x.get('diets')),
            'meat': meats(label),
        })

    src = ("SaladStop! Singapore website nutrition calculator (the JSON files its menu pages load), per item as served; "
           "Create-Your-Own dressings and toppings per portion. Calories as published. No allergens: SaladStop's tags leave out "
           "egg, soy and sesame. Not halal: bacon bits are pork. "
           f"Left out {len(dropped)} row(s) whose figures don't add up" + (': ' + '; '.join(dropped) if dropped else '')
           + f". Also left out {len(skipped)} drinks with no fat figure or plain water (cold-pressed juices, immunity shots, "
           "still and sparkling water).")
    out = {
        'chain': 'sg-saladstop', 'name': 'SaladStop!', 'how': 'Official website nutrition calculator',
        'url': 'https://saladstop.com.sg/salads-wraps/', 'src': src, 'checked': date.today().isoformat(),
        'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'SaladStop SG: {len(items)} items -> {OUT.name}; dropped {len(dropped)}: {dropped}; skipped {len(skipped)}')


if __name__ == '__main__':
    main()
