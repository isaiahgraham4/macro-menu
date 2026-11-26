#!/usr/bin/env python3
"""Jack's Family Restaurants (US): the nutrition panel on each product page of eatatjacks.com, saved as us-jacks-source.json.

eatatjacks.com is WordPress/WooCommerce. Its public product list (/wp-json/wp/v2/product) gives every menu item's page; each page's
short description holds two small tables: calories, fat, carbs and protein (the only figures Jack's publishes), then allergen
icons. A plain request gets both; no browser. Saturated fat, sugar, fibre and sodium aren't published, so they're null.

Left out: meals, combos, kids' meals, boxes, bundles and deals; items given as a calorie range (fountain drinks, tea, lemonade,
iced coffee, milkshakes, ice cream, fried pies, 2pc/3pc dinners, 3pc/4pc snacks), whose fat/carbs/protein can't be matched to
one size; bottled water; pages with no figures; and rows whose calories are far from 4p + 4c + 9f (more than a third out),
which are counted in `src`.
Allergens: the icons cover eggs, milk, soy, wheat, gluten, sesame and "nuts" only (no fish, shellfish or peanut/tree nut split),
so contains/may are null for every item.

Run: python3 ios/Scripts/intl/us-jacks-fetch.py
"""
import html
import json
import pathlib
import re
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'us-jacks-source.json'
SITE = 'https://www.eatatjacks.com'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36'
CATS = {22: 'breakfast', 23: 'main', 24: 'sweet', 25: 'drink', 27: 'main', 28: 'main', 29: 'main', 30: 'side', 43: 'main'}
SKIP = re.compile(r'(?i)meal|combo|box\b|bundle|deal|dinner|snack|family|bottled water|\s&\s.*(drink|fries|coffee)|, drink')
NAMES = {'All About the Biscuit Buttered Biscuit': 'Buttered Biscuit (breakfast)',
         'All About the Buttered Biscuit': 'Buttered Biscuit (side)'}
MEATS = [(r'chicken', 'chicken'), (r'burger|big jack|bigger jack|steak|big bacon', 'beef'),
         (r'bacon|sausage|gravy|\bham\b|blt|breakfast (special|deluxe|wrap|sandwich)', 'pork')]


def get(url):
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-US,en;q=0.9'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode('utf-8', 'replace')


def num(s):
    s = s.strip().lower().rstrip('g').strip()
    try:
        v = float(s)
    except ValueError:
        return None
    return int(v) if v == int(v) else v


def meat(name):
    n = name.lower()
    out = [m for pat, m in MEATS if re.search(pat, n)]
    return out or None


def main():
    products = json.loads(get(f'{SITE}/wp-json/wp/v2/product?per_page=100&_fields=id,slug,title,link,product_cat'))
    if not products:
        raise SystemExit("Jack's: the product list is empty")
    items, skipped, dropped, ranges = [], [], [], []
    for p in products:
        name = re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', ' ', html.unescape(p['title']['rendered']))).replace('®', '').strip()
        name = NAMES.get(name, name).replace('’', "'")
        if SKIP.search(name):
            skipped.append(name)
            continue
        page = get(p['link'])
        i = page.find('woocommerce-product-details__short-description')
        block = page[i:page.find('<hr', page.find('<table', i) + 1)] if i >= 0 else ''
        tables = re.findall(r'<table>(.*?)</table>', block, re.S)
        cells = [re.sub(r'<[^>]+>', '', c).strip() for c in re.findall(r'<td>(.*?)</td>', tables[0], re.S)] if tables else []
        if len(cells) < 8 or [c.lower() for c in cells[4:8]] != ['cal', 'fat', 'carbs', 'protein']:
            skipped.append(name)
            continue
        if '-' in cells[0]:
            ranges.append(name)
            continue
        cal, f, c, pr = (num(x) for x in cells[:4])
        if None in (cal, f, c, pr):
            skipped.append(name)
            continue
        est = 4 * pr + 4 * c + 9 * f
        if abs(est - cal) > cal / 3 and abs(est - cal) > 15:
            dropped.append(name)
            continue
        cat = next((CATS[k] for k in p['product_cat'] if k in CATS and k != 43), CATS.get(p['product_cat'][0], 'main'))
        m = re.search(r'\((\d+)\s*pc\)', name)
        items.append({
            'name': re.sub(r'\((\d+)pc\)', r'(\1 pc)', name), 'cat': cat, 'serve': f'{m.group(1)} pieces' + (' and a biscuit' if 'Biscuit' in name else '') if m else '1 serving',
            'cal': cal, 'kj': None, 'p': pr, 'c': c, 'f': f, 'sat': None, 'sugar': None, 'fibre': None, 'sodium': None,
            'salt': None, 'contains': None, 'may': None, 'vg': None, 'meat': meat(name),
        })

    src = ("Jack's Family Restaurants product pages (eatatjacks.com, undated; read on the date checked): calories, fat, carbs and "
           "protein only, so saturated fat, sugar, fibre and sodium are null. Allergens left out: the site's icons don't cover "
           f"fish, shellfish or peanuts separately. Left out: meals, combos, boxes, bundles and deals ({len(skipped)} pages, "
           f"incl. bottled water and pages without figures) and items given only as a calorie range ({', '.join(ranges)})")
    if dropped:
        src += f"; {len(dropped)} row(s) whose calories don't match their macros ({', '.join(dropped)})"
    out = {
        'chain': 'us-jacks', 'name': "Jack's", 'how': 'Official menu pages (nutrition panel)', 'url': SITE + '/pages/menu/',
        'src': src + '.', 'checked': date.today().isoformat(), 'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"Jack's: {len(items)} items, {len(dropped)} dropped, {len(ranges)} ranges, {len(skipped)} skipped -> {OUT.name}")


if __name__ == '__main__':
    main()
