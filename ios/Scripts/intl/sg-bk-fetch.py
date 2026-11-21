#!/usr/bin/env python3
"""Burger King Singapore -> sg-bk-source.json (normalised format, see SOURCE-FORMAT.md).

Source: each menu category page on burgerking.com.sg (/Menu/Category/<n>) carries the whole category as
`window.BK_MENU_PRODUCTS = {...}` in a script tag; the site's item panel ("Nutritional Information, per serving") is
drawn from it. The panel's footnote dates the figures October 2025.

Left out: rows whose calories are far (more than a third) from 4p + 4c + 9f, and plain water / hot tea.
Sodium figures under 20 mg on items over 100 kcal are misprints on the site (grams typed as milligrams?) and are left blank.
Allergens are not carried: Burger King Singapore's list has no sesame (the Whopper, on a sesame bun, lists only egg).
Burger King Singapore is halal certified: its bacon and ham are turkey.

Run: python3 ios/Scripts/intl/sg-bk-fetch.py
"""
import html
import json
import pathlib
import re
import ssl
import subprocess
import time
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
OUT = HERE / 'sg-bk-source.json'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
BASE = 'https://www.burgerking.com.sg'

# category id -> app category
CATEGORIES = {9: 'breakfast', 4: 'breakfast', 3: 'main', 1: 'main', 2: 'main', 11: 'main', 7: 'side', 8: 'sweet', 5: 'drink'}
SKIP = {'Dasani Bottled Water', 'Hot Tea'}
MEAT = {
    'Whopper': ['beef'], 'Western Whopper': ['beef', 'turkey'], 'Whopper with Cheese': ['beef'], 'Whopper Jr.': ['beef'],
    'Single Mushroom Swiss': ['beef'], 'Cheeseburger': ['beef'], 'Hamburger': ['beef'], 'Single BBQ Turkey Bacon': ['beef', 'turkey'],
    'Ultimate Angus Classic BBQ': ['beef'], 'Ultimate Angus Mushroom Swiss': ['beef'],
    'Turkey Bacon Croissan\'wich with Egg': ['turkey'], 'Turkey Ham Croissan\'wich with Egg': ['turkey'],
    'Turkey Ham & Cheese Omelette Platter': ['turkey'], 'BK Nuggets': ['chicken'], 'Mexican Drumlets': ['chicken'],
}


def get(url):
    """Plain GET. burgerking.com.sg sends an incomplete certificate chain that Python's own store can't complete,
    so fall back to the system curl (which still verifies the certificate) when that happens."""
    time.sleep(0.3)
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept-Language': 'en-SG,en;q=0.9'})
    try:
        with urllib.request.urlopen(req, timeout=40) as r:
            return r.read().decode('utf-8', 'replace')
    except urllib.error.URLError as e:
        if not isinstance(getattr(e, 'reason', None), ssl.SSLError):
            raise
    return subprocess.run(['curl', '-sSL', '--max-time', '40', '-A', UA, url], capture_output=True, text=True, check=True).stdout


def num(v):
    v = (v or '').strip()
    return float(v) if re.fullmatch(r'\d+(\.\d+)?', v) else None


def clean(s):
    s = html.unescape(s or '')
    s = re.sub(r'[®™©]', '', s)
    s = s.replace('Coca-cola', 'Coca-Cola').replace('w/ Cheese', 'with Cheese')
    for a, b in (('WHOPPER', 'Whopper'), ("HERSHEY'S", "Hershey's"), ('MILO', 'Milo'), ('SJORA', 'Sjora')):
        s = s.replace(a, b)
    return re.sub(r'\s+', ' ', s).strip()


def size_label(size):
    s = (size or '').strip().strip('()').strip()
    if not s:
        return None
    m = re.fullmatch(r'(\d+)\s*pcs?', s, re.I)
    if m:
        return f'{m.group(1)} pieces'
    m = re.fullmatch(r'(\d+)\s*ml', s, re.I)
    if m:
        return f'{m.group(1)} ml'
    return s.lower()


def energy_ok(cal, p, c, f):
    est = 4 * p + 4 * c + 9 * f
    if est < 10 and cal < 10:
        return True
    return abs(cal - est) <= est / 3


def main():
    items, dropped, seen = [], [], set()
    for cid, cat in CATEGORIES.items():
        page = get(f'{BASE}/Menu/Category/{cid}')
        m = re.search(r'window\.BK_MENU_PRODUCTS\s*=\s*(\{.*?\});\s*\n', page, re.S)
        if not m:
            raise SystemExit(f'category {cid}: BK_MENU_PRODUCTS not found')
        for pid, v in json.loads(m.group(1)).items():
            if pid in seen:
                continue
            seen.add(pid)
            name = clean(v['title'])
            if name in SKIP:
                continue
            cal, p, c, f = (num(v.get(k)) for k in ('calories', 'protein', 'carbohydrates', 'fat'))
            if None in (cal, p, c, f):
                dropped.append(f'{name} (figures missing)')
                continue
            if not energy_ok(cal, p, c, f):
                dropped.append(f'{name} ({cal:g} kcal vs {4*p+4*c+9*f:.0f} from macros)')
                continue
            size = size_label(v.get('size'))
            sodium = num(v.get('sodium'))
            if sodium is not None and sodium < 20 and cal > 100:
                sodium = None
            items.append({
                'name': f'{name} ({size})' if size else name,
                'cat': cat,
                'serve': size if size else '1 serving',
                'cal': int(cal + 0.5), 'kj': None,
                'p': p, 'c': c, 'f': f,
                'sat': num(v.get('saturatedfat')), 'sugar': num(v.get('sugar')), 'fibre': num(v.get('fiber')),
                'sodium': sodium, 'salt': None,
                'contains': None, 'may': None,
                'vg': None,
                'meat': MEAT.get(name),
            })
    src = ("Burger King Singapore menu pages, nutritional information per serving (Burger King dates the figures October 2025). "
           "Drinks are per 100 ml as published. No allergens: Burger King Singapore's list leaves out sesame. "
           "Halal: bacon and ham are turkey. Sodium left blank where the site prints a figure under 20 mg for a full item. "
           f"Left out {len(dropped)} item(s) whose calories don't match their macros"
           + (': ' + '; '.join(dropped) if dropped else '') + '; also bottled water and hot tea.')
    out = {
        'chain': 'sg-bk', 'name': 'Burger King', 'how': 'Official menu nutrition panels',
        'url': f'{BASE}/Menu', 'src': src, 'checked': date.today().isoformat(),
        'energy': 'cal', 'halal': True, 'items': items,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'Burger King SG: {len(items)} items -> {OUT.name}; dropped {len(dropped)}: {dropped}')


if __name__ == '__main__':
    main()
