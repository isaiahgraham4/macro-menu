#!/usr/bin/env python3
"""The Daily Cut (Singapore) -> sg-dailycut-source.json (normalised format, see SOURCE-FORMAT.md).

The Daily Cut sells build-your-own bowls (2 bases, 1-2 proteins, 2-3 supplements, 1 topping, 1 dressing). Its menu page
links "Nutritional Info" to thedailycut.sg/macro-calculator, where every component carries its calories, protein, carbs
and fat per portion in the page's HTML (data-cal / data-protein / data-carbs / data-fat on each counter). One row per
component per portion; a bowl is the sum of what's in it.

Left out: rows whose calories are far (more than a third) from 4p + 4c + 9f.
No allergens (the calculator gives none; the menu marks only gluten, nuts, dairy and fish). Not halal certified.

Run: python3 ios/Scripts/intl/sg-dailycut-fetch.py
"""
import html
import json
import pathlib
import re
import time
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'sg-dailycut-source.json'
URL = 'https://www.thedailycut.sg/macro-calculator/'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

GROUPS = {'bases': ('base', 'side'), 'proteins': ('protein', 'main'), 'supplements': ('supplement', 'side'),
          'toppings': ('topping', 'extra'), 'dressings': ('dressing', 'extra')}
MEAT = [(r'CHICKEN', 'chicken'), (r'BEEF', 'beef'), (r'DORY|SALMON', 'fish')]


def get(url):
    time.sleep(0.3)
    with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=40) as r:
        return r.read().decode('utf-8', 'replace')


def energy_ok(cal, p, c, f):
    est = 4 * p + 4 * c + 9 * f
    if est < 10 and cal < 10:
        return True
    return abs(cal - est) <= est / 3


def nice(raw):
    t = raw.title().replace(' W/ ', ' with ')
    return re.sub(r'-([A-Z])', lambda m: '-' + m.group(1).lower(), t)


def main():
    page = get(URL)
    heads = [(m.start(), m.group(1).lower()) for m in re.finditer(r'>\s*(bases|proteins|supplements|toppings|dressings)\s*<', page, re.I)]
    items, dropped = [], []
    for m in re.finditer(r'data-cal="([\d.]+)" data-protein="([\d.]+)" data-carbs="([\d.]+)" data-fat="([\d.]+)"', page):
        after = page[m.end():m.end() + 800]
        nm = re.search(r'</div>\s*<div[^>]*>\s*([^<]+?)\s*</div>', after)
        if not nm:
            continue
        raw = re.sub(r'\s+', ' ', html.unescape(nm.group(1))).strip().upper()
        group = [h for pos, h in heads if pos < m.start()]
        kind, cat = GROUPS.get(group[-1] if group else '', ('component', 'extra'))
        cal, p, c, f = (float(x) for x in m.groups())
        name = f'{nice(raw)} ({kind})'
        if not energy_ok(cal, p, c, f):
            dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
            continue
        meat = [v for pat, v in MEAT if re.search(pat, raw)] or None
        items.append({
            'name': name, 'cat': cat, 'serve': '1 portion',
            'cal': int(cal + 0.5), 'kj': None, 'p': p, 'c': c, 'f': f,
            'sat': None, 'sugar': None, 'fibre': None, 'sodium': None, 'salt': None,
            'contains': None, 'may': None, 'vg': None, 'meat': meat,
        })
    if not items:
        raise SystemExit('no components found: the calculator page layout has changed')
    src = ("The Daily Cut macro calculator (thedailycut.sg/macro-calculator, linked as the menu's Nutritional Info), per portion of "
           "each build-your-own bowl component: a petite bowl is 2 bases, half a protein, 2 supplements, 1 topping, 1 dressing; "
           "regular 2 bases, 1 protein, 3 supplements; large 2 bases, 2 proteins, 3 supplements. Calories, protein, carbs and fat "
           "only. No allergens. Not halal certified. "
           f"Left out {len(dropped)} component(s) whose calories don't match their macros" + (': ' + '; '.join(dropped) if dropped else '') + '.')
    out = {
        'chain': 'sg-dailycut', 'name': 'The Daily Cut', 'how': 'Official macro calculator',
        'url': URL, 'src': src, 'checked': date.today().isoformat(),
        'energy': 'cal', 'halal': False, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'The Daily Cut: {len(items)} items -> {OUT.name}; dropped {len(dropped)}: {dropped}')


if __name__ == '__main__':
    main()
