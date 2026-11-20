#!/usr/bin/env python3
"""Fetches the South African chains that publish nutrition on plain web pages, and saves what each page says beside this file:

  Kauai       kauai.co.za/menu-group/<group>/   every item's panel (per serving, or per 350 ml and 500 ml)  -> kauai-za-source.json
  Wimpy       wimpy.co.za/classic-menu/<page>/  the table behind each item's card                           -> wimpy-za-source.json
  Debonairs   debonairspizza.co.za/nutritional-and-allergen-guide/  one row per pizza size                  -> debonairs-za-source.json

McDonald's (mcd-za-scrape.js) and Nando's (the menu feed nandos.co.za/eat/order/menu loads, saved from the browser as
nandos-za-source.json) need a browser. Nothing is tidied here; build-intl-menu.py decides what is usable.

Steers (steers.co.za/nutritional-guide/) is not fetched: on 20 Nov 2026 its guide gave the Egg Breakfast Bun the figures of the
beef patty bun, five wings less than three, one set of figures for three different burgers, and didn't say which burgers are
counted with their chips.

Run: python3 ios/Scripts/intl/za-fetch.py [kauai|wimpy|debonairs ...]
"""
import html
import json
import pathlib
import re
import sys
import time
import urllib.request
from datetime import date

HERE = pathlib.Path(__file__).parent
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'


def get(url):
    time.sleep(0.4)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=40) as r:
            return r.read().decode('utf-8', 'replace')
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def text(s):
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s))).strip()


def save(name, items):
    out = HERE / f'{name}-za-source.json'
    out.write_text(json.dumps({'checked': date.today().isoformat(), 'items': items}, ensure_ascii=False, indent=1))
    print(f'{name}: {len(items)} items -> {out.name}')


def kauai():
    groups = ['all-day-breakfast', 'wraps', 'salad-bowls', 'warm-meals', 'sourdoughtoasties', 'snacks', 'smoothies', 'protein-smoothies',
              'superfood-smoothies', 'raw-juices-shots', 'recovery-drinks', 'organic-coffee-hot-drinks']
    items = {}
    for g in groups:
        page = 1
        while True:
            t = get(f'https://kauai.co.za/menu/?_sft_menu-group={g}' + (f'&sf_paged={page}' if page > 1 else ''))
            if not t:
                break
            found = 0
            for m in re.split(r'<div id="myModal\d+"', t)[1:]:
                name = text(re.search(r'<h4 class="modal-title">(.*?)</h4>', m, re.S).group(1))
                link = re.search(r'href="(https://kauai\.co\.za/menu-item/[^"]+)">MORE INFO', m)
                key = link.group(1) if link else name
                found += 1
                if key in items:
                    if g not in items[key]['groups']:
                        items[key]['groups'].append(g)
                    continue
                table = re.search(r'<table class="nutri_table".*?</table>', m, re.S)
                rows = [[text(c) for c in re.findall(r'<td[^>]*>(.*?)</td>', r, re.S)] for r in re.findall(r'<tr>(.*?)</tr>', table.group(0), re.S)] if table else []
                al = re.search(r'<p id="allergens_list">(.*?)</p>', m, re.S)
                ing = re.search(r'INGREDIENTS:</h6>\s*<p>(.*?)</p>', m, re.S)
                items[key] = {'name': name, 'url': key, 'groups': [g],
                              'tags': [text(x) for x in re.findall(r'<span class="tag_label"[^>]*>(.*?)</span>', m.split('modal-title')[1].split('ALLERGENS')[0], re.S)],
                              'allergens': [a.strip() for a in text(al.group(1)).split(',') if a.strip()] if al else None,
                              'ingredients': text(ing.group(1)) if ing else '', 'rows': rows}
            if not found or f'sf_paged={page + 1}' not in t:
                break
            page += 1
    save('kauai', list(items.values()))


def wimpy():
    items = []
    for page in ['breakfast', 'burger', 'grills', 'sandwiches-light-meals', 'kids', 'desserts', 'drinks']:
        t = get(f'https://wimpy.co.za/classic-menu/{page}/')
        if not t:
            print('wimpy: no page', page)
            continue
        for sect in re.split(r'<h2 class="screen-reader-text">', t)[1:]:
            section = text(sect.split('</h2>')[0])
            for tb in re.findall(r'<table class="table table-striped promo-nutri-table.*?</table>', sect, re.S):
                name = text(re.search(r'<th class="nutritional-heading"[^>]*>(.*?)</th>', tb, re.S).group(1))
                n, al = {}, {}
                for r in re.findall(r'<tr>(.*?)</tr>', tb, re.S):
                    th = re.search(r'<th>(.*?)</th>', r, re.S)
                    tds = re.findall(r'<td(?: class="([^"]*)")?>(.*?)</td>', r, re.S)
                    if th and tds:
                        n[text(th.group(1))] = text(tds[0][1])
                    if len(tds) > 1 and text(tds[1][1]):
                        al[text(tds[1][1])] = tds[1][0]
                    elif not th and tds and text(tds[-1][1]):
                        al[text(tds[-1][1])] = tds[-1][0]
                items.append({'page': page, 'section': section, 'name': name, 'n': n, 'allergens': al})
    save('wimpy', items)


def debonairs():
    t = get('https://debonairspizza.co.za/nutritional-and-allergen-guide/')
    standard = t.split('id="nutri-standard-output"')[1].split('id="nutri-halaal-output"')[0]
    rest = t.split('id="nutri-halaal-output"')[1]
    items = []

    def sections(chunk):
        for s in re.split(r'<section class="nutri-section" id="', chunk)[1:]:
            sid = s.split('"')[0]
            title = text(re.search(r'<h2 class="nutri-section__title">(.*?)</h2>', s, re.S).group(1))
            for a in re.split(r'<article class="nutri-item">', s)[1:]:
                yield sid, title, text(re.search(r'<span class="nutri-item__name">(.*?)</span>', a, re.S).group(1)), a

    rows = lambda chunk: {text(k): text(v) for k, v in re.findall(r'<dt>(.*?)</dt>\s*<dd>(.*?)</dd>', chunk, re.S)}
    for sid, title, name, a in sections(standard):
        sizes = [{'label': text(z.split('</h3>')[0]), 'n': rows(z)} for z in re.split(r'<h3 class="nutri-size__label">', a)[1:]]
        items.append({'section': title, 'name': name, 'sizes': sizes})
    allergens = [{'section': title, 'name': name, 'al': rows(a)} for sid, title, name, a in sections(rest) if sid.startswith('allergens-')]
    out = HERE / 'debonairs-za-source.json'
    out.write_text(json.dumps({'checked': date.today().isoformat(), 'items': items, 'allergens': allergens}, ensure_ascii=False, indent=1))
    print(f'debonairs: {len(items)} items, {len(allergens)} allergen rows -> {out.name}')


if __name__ == '__main__':
    todo = sys.argv[1:] or ['kauai', 'wimpy', 'debonairs']
    for name in todo:
        globals()[name]()
