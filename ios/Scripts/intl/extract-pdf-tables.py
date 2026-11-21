#!/usr/bin/env python3
"""Reads the two chains that only publish a PDF into JSON the menu builds use. The PDFs aren't kept in the repo; download them
from the chain's own nutrition page and pass the paths.

  Tim Hortons Canada  timhortons.ca/nutrition-and-allergens, "Nutrition Information" PDF  -> intl/th-ca-source.json
  Popeyes US          popeyes.com/nutritional-information, PLK_Nutrition.pdf             -> us/plk-us-source.json
  Subway New Zealand  subway.com/en-nz/media/new_zealand/documents/nutritionals/nz-nutritional-summary.pdf -> intl/subway-nz-source.json

Tim Hortons' text layer lists names and figures in different orders, so rows are matched by their position on the page
(each figures row goes with the name printed level with it). Popeyes' text layer keeps each row on one line.

Run: python3 -I ios/Scripts/intl/extract-pdf-tables.py th <tim-hortons.pdf>
     python3 -I ios/Scripts/intl/extract-pdf-tables.py plk <popeyes.pdf>
     python3 -I ios/Scripts/intl/extract-pdf-tables.py subway-nz <nz-nutritional-summary.pdf>
"""
import json
import pathlib
import re
import sys
from datetime import date

HERE = pathlib.Path(__file__).parent
NUM = re.compile(r'^-?\d+(\.\d+)?$')


def tim_hortons(path):
    import pymupdf
    doc = pymupdf.open(path)
    edition = re.search(r'as of (\w+ \d{4})', doc[0].get_text())
    rows, section, unpaired = [], '', []
    for page in doc:
        words = page.get_text('words')                      # x0, y0, x1, y1, text, block, line, word
        if not words:
            continue
        # Figures sit right of the name column; the first figure column starts where the "Calories" header does.
        cal = [w for w in words if w[4].startswith('Calories')]
        if not cal:
            continue
        split = min(w[0] for w in cal) - 4
        header_bottom = max(w[3] for w in words if w[4] in ('(kcal)', 'Calories', 'Item', '(mg)', '(g)'))
        names, figures = {}, {}
        for w in words:
            if w[1] < header_bottom:
                continue
            mid = round((w[1] + w[3]) / 2, 1)
            (names if w[0] < split else figures).setdefault(mid, []).append(w)
        name_lines = sorted((y, ' '.join(x[4] for x in sorted(ws, key=lambda x: x[0]))) for y, ws in names.items())
        fig_lines = sorted((y, [x[4] for x in sorted(ws, key=lambda x: x[0])]) for y, ws in figures.items())
        used = set()
        paired = {}
        for y, vals in fig_lines:
            if len(vals) != 10 or not all(NUM.match(v) for v in vals):
                continue
            best = min(((abs(ny - y), ny, text) for ny, text in name_lines if ny not in used), default=None)
            if best and best[0] <= 3.5:
                used.add(best[1])
                paired[best[1]] = vals
        for ny, text in name_lines:
            if ny in paired:
                cal_, fat, sat, trans, chol, na, carb, fib, sug, prot = paired[ny]
                rows.append({'section': section, 'name': text, 'cal': cal_, 'fat': fat, 'sat': sat, 'trans': trans, 'chol': chol,
                             'sodium': na, 'carbs': carb, 'fibre': fib, 'sugar': sug, 'protein': prot})
            elif re.search(r' - (Small|Medium|Large|X Large|Extra Large)$', text):
                unpaired.append(text)                       # an item whose figures couldn't be placed: left out, listed below
            elif not re.search(r'Nutrition Information|Menu Item|Hortons|^\(|^\*', text):
                section = text                              # a heading row, such as "Brewed Coffee"
    if unpaired:
        print('Left out (no figures level with the name):', unpaired)
    return {'edition': edition.group(1) if edition else None, 'rows': rows}


def popeyes(path):
    import pypdf
    reader = pypdf.PdfReader(path)
    text = '\n'.join(p.extract_text() for p in reader.pages)
    edition = re.search(r'Nutrition Guide\s*\n?\s*(\w+\s+\d{4})', text)
    rows = []
    for line in text.splitlines():
        m = re.match(r'^(.+?) (\d+(?: Pieces?)?|Reg|Lg|Sm|Med|Kids) ((?:-?\d+(?:\.\d+)? ?){11})$', line.strip())
        if not m:
            continue
        cal, calfat, fat, sat, trans, chol, na, carb, fib, sug, prot = m.group(3).split()
        rows.append({'name': m.group(1), 'portion': m.group(2), 'cal': cal, 'fat': fat, 'sat': sat, 'trans': trans, 'chol': chol,
                     'sodium': na, 'carbs': carb, 'fibre': fib, 'sugar': sug, 'protein': prot})
    return {'edition': re.sub(r'\s+', ' ', edition.group(1)) if edition else None, 'rows': rows}


SUBWAY_FIELDS = ['g', 'kj', 'cal', 'p', 'f', 'sat', 'c', 'sugar', 'fibre', 'sodium']
SUBWAY_HEAD = {'AVG QTY Per Serve', 'Serving Size (g)', 'Energy (kJ)', 'Energy (kCal)', 'Protein (g)', 'Fat, Total (g)', 'Sat. Fat (g)',
               'Carb. (g)', 'Sugars (g)', 'Dietary Fiber (g)', 'Sodium (mg)'}
SUBWAY_SECTIONS = ['Subway 6-Inch® Subs', 'Wraps (on regular flour wrap)', 'Mini Subs', 'Breakfast', 'BreakfastWraps', 'Breakfast Wraps',
                   'Sides & Snacks', 'Cookies', 'Baked Goods', 'Smoothies', 'Breads', 'Meat, Poultry, Egg, Seafood & Vegetarian Items',
                   'Sauces & Dressings', 'Cheeses', 'Vegetables', 'Seasonings', 'New']


def subway_nz(path):
    """Subway NZ's Nutritional Summary. Its text layer lists each item as name, description in brackets, then ten figures. Only
    the per-serve pages are read (the rest repeat everything per 100 g). The two salad sections have their headings drawn, not
    written, so they're found where the item names start over after the wraps: regular salads, then large."""
    import pymupdf
    doc = pymupdf.open(path)
    order = ['Subway 6-Inch® Subs', 'Wraps (on regular flour wrap)', 'Salads (regular)', 'Salads (large)']
    rows, section, seen, pending = [], '', set(), []
    for page in doc:
        text = page.get_text()
        if 'Per 100g' in text:
            break
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        i, pending = 0, []                                   # headings drawn at a page's foot belong to nothing on the next page
        while i < len(lines):
            line = lines[i]
            if line.startswith(('*', 'Amount on', 'Nutrition information compiled')):
                break
            if line in SUBWAY_HEAD or line.startswith(('Double values', 'Salads (')):
                i += 1
                continue
            if NUM.match(line):
                nums = []
                while i < len(lines) and NUM.match(lines[i]) and len(nums) < 10:
                    nums.append(float(lines[i]))
                    i += 1
                heads = [l for l in pending if l in SUBWAY_SECTIONS]
                if heads:
                    section = heads[-1] if heads[-1] not in ('Breakfast',) else 'Breakfast Subs'
                    section = {'BreakfastWraps': 'Breakfast Wraps', 'Subway 6-Inch® Subs': 'Breakfast Subs' if 'Breakfast' in heads else section}.get(section, section)
                    seen = set()
                words = [l for l in pending if l not in SUBWAY_SECTIONS]
                name, desc = [], []
                for l in words:
                    (desc if desc or l.startswith('(') else name).append(l)
                name = ' '.join(name)
                if name in seen and section in order[:-1]:
                    section, seen = order[order.index(section) + 1], set()
                seen.add(name)
                if len(nums) == 10:
                    rows.append({'section': section, 'name': name, 'desc': ' '.join(desc), **dict(zip(SUBWAY_FIELDS, nums))})
                pending = []
                continue
            pending.append(line)
            i += 1
    edition = re.search(r'(January|February|March|April|May|June|July|August|September|October|November|December) \d{4}', ' '.join(p.get_text() for p in doc))
    return {'edition': edition.group(0) if edition else None, 'rows': rows}


if __name__ == '__main__':
    kind, path = sys.argv[1], sys.argv[2]
    if kind == 'th':
        data, out = tim_hortons(path), HERE / 'th-ca-source.json'
    elif kind == 'plk':
        data, out = popeyes(path), HERE.parent / 'us' / 'plk-us-source.json'
    elif kind == 'subway-nz':
        data, out = subway_nz(path), HERE / 'subway-nz-source.json'
    else:
        raise SystemExit('kind is th, plk or subway-nz')
    data['checked'] = date.today().isoformat()
    out.write_text(json.dumps(data, ensure_ascii=False, indent=0))
    print(f'{len(data["rows"])} rows ({data["edition"]}) -> {out}')
