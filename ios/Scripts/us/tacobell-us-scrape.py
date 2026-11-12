#!/usr/bin/env python3
"""Taco Bell US menu: every item and drink size on tacobell.com, with the nutrition label Taco Bell links for it.

Taco Bell's own item pages (tacobell.com/food/...) carry each item's Nutritionix label link (the label Taco Bell shows under
"Nutrition Info"); drinks list one per size. The label holds the unrounded values and the allergen list. tacobell.com/nutrition/info
redirects to tacobell.com.au from Australia, but the item pages don't.
Saves ios/Scripts/us/tacobell-us-source.json. Run: python3 ios/Scripts/us/tacobell-us-scrape.py  (about 5 minutes)
"""
import datetime
import html as htmllib
import json
import pathlib
import re
import time
import urllib.request

OUT = pathlib.Path(__file__).with_name('tacobell-us-source.json')
BASE = 'https://www.tacobell.com'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
# Boxes, combos, party packs and member deals are bundles of items already listed.
CATEGORIES = ['breakfast', 'cantina-menu', 'specialties', 'tacos', 'burritos', 'quesadillas', 'nachos', 'luxe-value-menu',
              'snacks-sweets', 'drinks', 'bowls', 'vegetarian', 'featured', 'best-sellers', 'online-exclusives']


def get(url):
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US'})
            with urllib.request.urlopen(req, timeout=40) as r:
                if 'tacobell.com.au' in r.geturl():
                    raise SystemExit(f'{url} redirected to the Australian site')
                return r.read().decode('utf8', 'ignore')
        except SystemExit:
            raise
        except Exception:
            if attempt == 2:
                raise
            time.sleep(3)


def next_data(page):
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', page, re.S)
    return json.loads(m.group(1))['props']['pageProps']


def label(url):
    """Values and allergens from a Nutritionix label popup."""
    page = get(url)
    vals = dict(re.findall(r'\n\s*value(\w+)\s*:\s*([\d.]+)', page))
    unit = re.search(r"valueServingSizeUnit\s*:\s*'([^']*)'", page)
    name = re.search(r"itemName\s*:\s*'((?:[^'\\]|\\.)*)'", page)
    allergens = {}
    for a, kind in re.findall(r'<td><strong>([^<]+)</strong></td>\s*<td><em class="allergen (\w+)', page):
        allergens[htmllib.unescape(a).strip()] = kind          # warning = contains, free = doesn't
    return {'name': htmllib.unescape(name.group(1)).replace("\\'", "'") if name else None, 'unit': unit and unit.group(1),
            'values': {k: float(v) for k, v in vals.items()}, 'allergens': allergens}


products = {}
for cat in CATEGORIES:
    pp = next_data(get(f'{BASE}/food/{cat}'))
    for p in pp.get('products') or []:
        if p.get('itemType') == 'Product' and p.get('url'):
            products.setdefault(p['url'], {'code': p['code'], 'name': p['name'], 'category': cat, 'type': p.get('productType')})
    time.sleep(0.4)
print(f'{len(products)} Taco Bell products')

items = []
for url, info in products.items():
    try:
        p = next_data(get(BASE + url))['product']
    except Exception as e:
        items.append({**info, 'url': url, 'err': str(e)[:120]})
        continue
    if not p:
        items.append({**info, 'url': url, 'err': 'page has no product data'})
        continue
    variants = [v for v in (p.get('variantOptions') or []) if (v.get('nutritionInfo') or {}).get('url')]
    targets = [(v.get('drinkSize'), v['nutritionInfo']['url'], v.get('name')) for v in variants] or \
              ([(None, p['nutritionInfo']['url'], p.get('name'))] if (p.get('nutritionInfo') or {}).get('url') else [])
    if not targets:
        items.append({**info, 'url': url, 'err': 'no nutrition label'})
    for size, nix, vname in targets:
        try:
            items.append({**info, 'url': url, 'size': size, 'variant': vname, 'label_url': nix, **label(nix)})
        except Exception as e:
            items.append({**info, 'url': url, 'size': size, 'err': str(e)[:120]})
        time.sleep(0.3)
    time.sleep(0.3)

OUT.write_text(json.dumps({'checked': datetime.date.today().isoformat(), 'items': items}, ensure_ascii=False, indent=1))
print(f'Saved {len(items)} rows ({sum(1 for i in items if i.get("err"))} errors) to {OUT.name}')
