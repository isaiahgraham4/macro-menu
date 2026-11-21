#!/usr/bin/env python3
"""Popeyes Canada: downloads the Nutrition Guide PDF linked from popeyes.ca/nutrition-information (the page's text lives in
Popeyes' public Sanity dataset prod_plk_ca, which the site itself reads) and writes ca-popeyes-source.json beside this file.

Each table row is read by position (name, portion, then calories, fat, sat fat, trans fat, cholesterol, sodium, carbs, fibre,
sugar, protein); the section headings printed above the rows (Wings, Boneless Wings, Signature Sides ...) give the category.

Popeyes Canada's allergen guide is dated December 2023, two years older than the nutrition guide, so allergens are left out.

Run: python3 ios/Scripts/intl/ca-popeyes-fetch.py
"""
import json
import tempfile
import os
import pathlib
import re
import time
import urllib.request
from datetime import date

import pymupdf

HERE = pathlib.Path(__file__).parent
PDFS = pathlib.Path(os.environ.get('PDF_DIR', tempfile.gettempdir())) / 'plkca'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
SANITY = 'https://czqk28jt.apicdn.sanity.io/v1/graphql/prod_plk_ca/default'
PAGE_ID = '6f04fa5e-d26c-4f25-9861-e864c861440a'   # "Nutrition Information 2026" static page
CAT = {'SIGNATURE CHICKEN': 'main', 'WINGS': 'main', 'BONELESS WINGS': 'main', 'TENDERS & NUGGETS': 'main', 'SEAFOOD': 'main',
       'SANDWICHES': 'main', 'SIGNATURE SIDES': 'side', 'SIGNATURE DIPPING SAUCES': 'extra', 'DESSERTS': 'sweet', 'FOUNTAIN DRINKS': 'drink'}
NUM = re.compile(r'^<?\d+(\.\d+)?$')


def fetch(url, data=None, headers=None):
    time.sleep(0.3)
    req = urllib.request.Request(url, data=data, headers={'User-Agent': UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def pdf_url():
    q = '{ StaticPage(id:"%s"){ widgets{ ... on LocaleBlockTextWidget { localeBlockTextContent { enRaw } } } } }' % PAGE_ID
    raw = fetch(SANITY, json.dumps({'query': q}).encode(), {'content-type': 'application/json'}).decode()
    urls = re.findall(r'https://[^"]+Nutrition[^"]+\.pdf', raw)
    return urls[0]


def rows(page, last_head):
    lines, heads = [], [(-1, last_head)]
    for b in page.get_text('dict')['blocks']:
        for l in b.get('lines', []):
            t = ' '.join(s['text'] for s in l['spans']).strip()
            if not t:
                continue
            if t in CAT:
                heads.append((l['bbox'][1], t))
            else:
                lines.append((l['bbox'][1], l['bbox'][0], t))
    grouped = []
    for y, x, t in sorted(lines):
        if grouped and abs(grouped[-1][0] - y) < 3:
            grouped[-1][1].append((x, t))
        else:
            grouped.append([y, [(x, t)]])
    out = []
    for y, cells in grouped:
        cells.sort()
        nums = [t for x, t in cells if NUM.match(t)]
        words = [t for x, t in cells if not NUM.match(t)]
        if len(nums) == 10 and len(words) == 2:
            head = max((h for h in heads if h[0] < y), default=(0, None))[1]
            out.append({'section': head, 'name': words[0], 'portion': words[1], 'v': [float(n.lstrip('<')) for n in nums]})
    return out


def tidy(name, portion, section):
    name = re.sub(r'[®™▲]', '', name).replace('Teders', 'Tenders').strip()
    m = re.match(r'^(.*?) - (Classic|Spicy)$', name)
    if m:
        name = f'{m.group(2)} {m.group(1)}'
        name = re.sub(r'^(Classic|Spicy) (Breast|Leg|Thigh|Wing)$', r'\1 Chicken \2', name)
    if section == 'BONELESS WINGS' and name != 'Boneless Wings':
        name = 'Boneless ' + name
    p = portion.strip()
    size = {'Reg': 'regular', 'Medium': 'medium', 'Lg': 'large', 'Each': None}.get(p)
    if size is None and p != 'Each':
        size = re.sub(r'(?i)(\d+) ?pc', r'\1 pc', p)
    if section == 'FOUNTAIN DRINKS':
        size = 'medium'
    return f'{name} ({size})' if size else name


def main():
    PDFS.mkdir(parents=True, exist_ok=True)
    url = pdf_url()
    path = PDFS / 'popeyes-ca-nutrition.pdf'
    path.write_bytes(fetch(url))
    doc = pymupdf.open(path)
    items, dropped, last_head = [], [], None
    for page in doc:
        page_rows = rows(page, last_head)
        last_head = page_rows[-1]['section'] if page_rows else last_head
        for r in page_rows:
            cal, fat, sat, trans, chol, na, carb, fibre, sugar, prot = r['v']
            name = tidy(r['name'], r['portion'], r['section'])
            if cal > 20 and abs(4 * prot + 4 * carb + 9 * fat - cal) > cal / 3:
                dropped.append(name)
                continue
            num = lambda v: int(v) if v == int(v) else v
            sec = r['section']
            meat = None
            if CAT.get(sec) == 'main':
                meat = ['seafood'] if sec == 'SEAFOOD' else ['chicken']
            items.append({
                'name': name, 'cat': CAT.get(sec, 'main'), 'serve': {'Each': '1 serving', 'Reg': 'regular', 'Lg': 'large', 'Medium': 'medium'}
                .get(r['portion'], r['portion'].replace('Pc', 'pieces').replace('1 pieces', '1 piece')),
                'cal': num(cal), 'kj': None, 'p': num(prot), 'c': num(carb), 'f': num(fat),
                'sat': num(sat), 'sugar': num(sugar), 'fibre': num(fibre), 'sodium': num(na), 'salt': None,
                'contains': None, 'may': None, 'vg': None, 'meat': meat,
            })
    src = ('Popeyes Canada Nutrition Guide 2025 (PDF, "current as of November 2025", linked from popeyes.ca). '
           + (f'Left out: {len(dropped)} rows whose energy does not add up ({"; ".join(dropped)}). ' if dropped else 'Nothing left out. ')
           + 'No allergens: the only allergen guide Popeyes Canada links is dated December 2023.')
    out = {'chain': 'ca-popeyes', 'name': 'Popeyes', 'how': 'Official nutrition guide (PDF)',
           'url': 'https://www.popeyes.ca/nutrition-information', 'src': src, 'checked': date.today().isoformat(),
           'energy': 'cal', 'halal': False, 'items': items}
    (HERE / 'ca-popeyes-source.json').write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f'ca-popeyes: {len(items)} items, dropped {dropped}')


if __name__ == '__main__':
    main()
