#!/usr/bin/env python3
"""Reads the Indian chains' nutrition booklets into source files beside this script. The PDFs themselves stay out of the repo.

  kfc       about.kfc.co.in/assets/files/nutrition-booklet.pdf (linked as Nutrition Information on online.kfc.co.in)
            python3 in-extract.py kfc nutrition-booklet.pdf            -> kfc-in-source.json
  pizzahut  the "nutritionals" PDF linked from pizzahut.co.in/nutrition/
            python3 in-extract.py pizzahut nutritionals.pdf            -> pizzahut-in-source.json
  mcd       McDonald's India (North & East) menu booklet, mcdindia.com/wp-content/uploads/2026/04/mcd-website.pdf, linked from
            mcdindia.com. It is pictures with no text layer: render each page to PNG (PyMuPDF, 60 dpi), read them with
            ocr-pages.swift (macOS Vision: swiftc -O ocr-pages.swift -o ocr; ./ocr pages/p*.png > mcd-ocr.jsonl), then
            python3 in-extract.py mcd mcd-ocr.jsonl                    -> mcd-in-source.json

Both table booklets are read by position: a row's figures are its last run of numbers, in the booklet's column order. Nothing is
tidied here; build-intl-menu.py decides what is usable.
"""
import json
import pathlib
import re
import sys
from datetime import date

HERE = pathlib.Path(__file__).parent


def rows(page, tol):
    words = sorted(page.get_text('words'), key=lambda w: ((w[1] + w[3]) / 2, w[0]))
    out, cur, y = [], [], None
    for w in words:
        cy = (w[1] + w[3]) / 2
        if y is None or abs(cy - y) > tol:
            if cur:
                out.append(cur)
            cur, y = [], cy
        cur.append(w)
    if cur:
        out.append(cur)
    return [sorted(r, key=lambda w: w[0]) for r in out]


def save(name, items):
    out = HERE / f'{name}-in-source.json'
    out.write_text(json.dumps({'checked': date.today().isoformat(), 'items': items}, ensure_ascii=False, indent=0))
    print(f'{name}: {len(items)} rows -> {out.name}')


KFC_COLS = ['weight', 'servings', 'cal', 'carbs', 'protein', 'fat', 'fat_rda', 'trans', 'trans_rda', 'mufa', 'pufa', 'sat', 'sat_rda',
            'sodium', 'sodium_rda', 'sugar']


def kfc(pdf):
    """Pages 4 to 15 (single items). The later pages are meals and buckets whose names run over several lines."""
    import pymupdf
    num = lambda s: re.fullmatch(r'-?\d+(\.\d+)?', s)
    items = []
    for pn, page in enumerate(pymupdf.open(pdf)):
        if not 3 <= pn <= 14:
            continue
        section = ''
        for r in rows(page, 4):
            y = r[0][1]
            body = [w for w in r if w[4] not in ('Yes', 'No')]
            k = len(body)
            while k > 0 and num(body[k - 1][4]):
                k -= 1
            vals, name = body[k:], ' '.join(w[4] for w in body[:k])
            if len(vals) > 16:
                name, vals = (name + ' ' + ' '.join(w[4] for w in vals[:-16])).strip(), vals[-16:]
            if len(vals) == 16 and name and y > 110:
                items.append(dict({'page': pn + 1, 'section': section, 'name': name, 'msg_sweetener': [w[4] for w in r if w[4] in ('Yes', 'No')]},
                                  **{key: float(w[4]) for key, w in zip(KFC_COLS, vals)}))
            elif len(vals) >= 10 and y > 110:
                print('kfc: could not read', pn + 1, name, [w[4] for w in vals], file=sys.stderr)
            elif not vals and len(r) <= 8 and 110 < y < 370 and r[0][0] > 300:
                section = ' '.join(w[4] for w in r)
    save('kfc', items)


PH_COLS = ['weight', 'count', 'cal', 'cal_rda', 'carbs', 'protein', 'fibre', 'sugar', 'added_sugar', 'added_rda', 'fat', 'fat_rda', 'mufa', 'pufa',
           'sat', 'sat_rda', 'trans', 'trans_rda', 'chol', 'sodium', 'sodium_rda']


def pizzahut(pdf):
    """21 figures a row (20 where the booklet leaves out the number of slices or pieces); the allergen text sits to the right."""
    import pymupdf
    isval = lambda s: re.fullmatch(r'-?\d+(\.\d+)?|ND|-|NA|BLQ', s)
    items = []
    for pn, page in enumerate(pymupdf.open(pdf)):
        words, section = page.get_text('words'), ''
        for r in rows(page, 3):
            y = (r[0][1] + r[0][3]) / 2
            left = [w for w in r if w[0] < 775]
            k = len(left)
            while k > 0 and isval(left[k - 1][4]):
                k -= 1
            vals, name = left[k:], ' '.join(w[4] for w in left[:k])
            if len(vals) in (20, 21) and name:
                cols = PH_COLS if len(vals) == 21 else PH_COLS[:1] + PH_COLS[2:]
                near = sorted([w for w in words if w[0] >= 775 and abs((w[1] + w[3]) / 2 - y) < 10], key=lambda w: (round(w[1]), w[0]))
                items.append(dict({'page': pn + 1, 'section': section, 'name': name, 'allergens': ' '.join(w[4] for w in near)},
                                  **{key: w[4] for key, w in zip(cols, vals)}))
            elif len(vals) >= 8 and y > 45:
                print('pizzahut: could not read', pn + 1, name, [w[4] for w in vals], file=sys.stderr)
            elif 40 < y < 560 and not vals and r[0][0] < 60 and len(r) <= 12 and not any(w[0] >= 775 for w in r) \
                    and not re.match(r'Pizza Hut Nutrition|Milk|Contains', ' '.join(w[4] for w in r)):
                section = ' '.join(w[4] for w in r)
    save('pizzahut', items)


MCD_LABELS = {'ENERGY': 'cal', 'PROTEIN': 'protein', 'TOTAL FAT': 'fat', 'CHOLESTEROLS': 'chol', 'TRANS FAT': 'trans', 'SAT FAT': 'sat',
              'TOTAL CARBS': 'carbs', 'TOTAL SUGARS': 'sugar', 'ADDED SUGARS': 'added_sugar', 'SODIUM': 'sodium'}


def mcd(ocr):
    """One item a page: the section at the top, the name in the banner, the allergen line, and ten labelled figures, each printed
    just under its label."""
    items = []
    for line in open(ocr):
        o = json.loads(line)
        L = o['lines']
        labels = [l for l in L if l['t'].strip().upper() in MCD_LABELS]
        if not labels:
            continue
        cx = lambda l: l['x'] + l['w'] / 2
        n = {}
        for lab in labels:
            under = [l for l in L if 0 < l['y'] - lab['y'] < 0.03 and abs(cx(l) - cx(lab)) < 0.07 and re.match(r'^[\d.,]+ ?(k?Cal|g|mg)?$', l['t'].strip(), re.I)]
            if under:
                n[MCD_LABELS[lab['t'].strip().upper()]] = min(under, key=lambda l: abs(cx(l) - cx(lab)))['t'].strip()
        top = sorted([l for l in L if l['y'] < 0.1], key=lambda l: l['y'])
        name = ' '.join(l['t'] for l in sorted([l for l in L if 0.17 < l['y'] < 0.23], key=lambda l: l['x']))
        warn = next((l for l in L if 'Allergen Warning' in l['t']), None)
        al = ' '.join(l['t'] for l in sorted([l for l in L if warn and 0.005 < l['y'] - warn['y'] < 0.05 and l['x'] >= warn['x'] - 0.02 and l['y'] < 0.87],
                                             key=lambda l: l['y'])) if warn else None
        size = [l['t'] for l in L if re.search(r'\b(small|regular|medium|large|\d+ ?(pc|pcs|piece|ml|g))\b', l['t'], re.I) and 0.23 < l['y'] < 0.8]
        items.append({'page': o['file'], 'section': top[0]['t'] if top else '', 'name': name, 'allergens': al, 'size_text': size, 'n': n})
    save('mcd', items)


if __name__ == '__main__':
    globals()[sys.argv[1]](sys.argv[2])
