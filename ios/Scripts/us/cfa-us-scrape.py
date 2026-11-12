#!/usr/bin/env python3
"""Chick-fil-A US menu: nutrition and allergens from chick-fil-a.com/nutrition-allergens.

The page embeds its whole table as WordPress Interactivity state (a JSON script tag), so a plain request is enough.
Saves ios/Scripts/us/cfa-us-source.json. Run: python3 ios/Scripts/us/cfa-us-scrape.py
"""
import datetime
import json
import pathlib
import re
import urllib.request

URL = 'https://www.chick-fil-a.com/nutrition-allergens'
OUT = pathlib.Path(__file__).with_name('cfa-us-source.json')

req = urllib.request.Request(URL, headers={'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
                                           '(KHTML, like Gecko) Chrome/130.0 Safari/537.36'})
html = urllib.request.urlopen(req, timeout=60).read().decode('utf8', 'ignore')
m = re.search(r'<script id="wp-script-module-data-@wordpress/interactivity" type="application/json">(.*?)</script>', html, re.S)
if not m:
    raise SystemExit('Chick-fil-A: the nutrition table state is missing from the page')
table = json.loads(m.group(1))['state']['nutrition-allergens-table-store']['tableData']


def fields(item):
    return {f.get('key') or f['label']: f['value'] for f in item['fields']}


def walk(groups, kind):
    """{item ID: {...}} for every item and sub-item in each menu group."""
    out = {}
    for g in groups:
        for it in g['items']:
            out[it['ID']] = {'menu': g['menu'], 'title': it['title'], kind: fields(it),
                             'subs': [s['ID'] for s in it['sub_items']]}
            for s in it['sub_items']:
                out[s['ID']] = {'menu': g['menu'], 'title': s['title'], 'parent': it['title'], kind: fields(s), 'subs': []}
    return out


nutrition = walk(table['nutrition'], 'n')
allergens = walk(table['allergens'], 'a')
# The same item can sit in two menu groups (Fruit Cup is in Breakfast and Sides); keep each group it appears in.
items = []
for g in table['nutrition']:
    for it in g['items']:
        for iid in [it['ID']] + [s['ID'] for s in it['sub_items']]:
            row = dict(nutrition[iid])
            row['menu'] = g['menu']
            row['id'] = iid
            row['a'] = allergens.get(iid, {}).get('a')
            items.append(row)
OUT.write_text(json.dumps({'checked': datetime.date.today().isoformat(), 'url': URL, 'items': items}, ensure_ascii=False, indent=1))
print(f'Saved {len(items)} Chick-fil-A rows to {OUT.name}')
