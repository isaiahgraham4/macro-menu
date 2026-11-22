#!/usr/bin/env python3
"""Single pieces: 1 wing, 1 nugget, 1 tender, 1 churro... for items restaurants only publish as packs.

Restaurants publish "3 Wicked Wings" or "Chicken McNuggets (6 pc)", but people often eat one or two. For every pack
whose name gives a count, this adds a row for one piece: the pack's published figures divided by its count.

- A pack is left alone when it comes with something else that isn't split evenly per piece (chips, a drink, a dipping
  sauce: meals, combos, buckets, boxes, platters, share deals), when it's a drink, swap or add-on, or when the serve
  says its figures are already per piece ("8 per pizza", "1 of 4").
- When a chain sells the same thing in several pack sizes, packs with far more sugar per piece are set aside (KFC's
  6 and 10 Nuggets include a sauce, the 3 doesn't), then one piece comes from the packs that agree with each other
  (Arby's 3 and 5 tenders, not its smaller 2), the smallest of them. Packs that disagree by more than 12% are reported.
- When the chain already publishes a single piece (KFC's "1 Piece of Chicken"), nothing is added for that item.
- The single copies the pack's dietary info and the sauces and items it can be ordered with; other modifiers
  (removals, swaps, extras) are pack-sized, so they're dropped.

Used by export-menu.cjs (Australia, through stdin/stdout), us/build-us-menu.py and intl/build-intl-menu.py (by import).
Run directly with --report to see what it would add to the current menus.
"""
import json
import re
import sys

SKIP_CATS = {'drink', 'swap', 'extra'}
# Packs that come with something else, or aren't a pile of identical pieces.
SKIP_WORDS = re.compile(r"(?i)\b(meal|combo|bucket|box|boxes|platter|feast|family|share|sharebox|bundle|deal|carry cup|"
                        r"snack pack|value pack|chips|fries and|fries &|& fries|and fries|dip|dips|dip'd|dipping|"
                        r"with (?:\w+ )*(?:sauce|sauces|mayo|ketchup|ranch|aioli|gravy|salsa|dressing)|for \$|\$\d|#\d|"
                        r"half|1/2|1/4|serves|servings|slices? of pizza|whole pizza|sliders? &|& sliders?)\b"
                        # several kinds of piece in one pack: "2 Piece Chicken (Drumstick and Side Breast)"
                        r"|\([^)]*(?:,| and | & )[^)]*\)")
# Serves that say the figures are already for one piece.
PER_PIECE = re.compile(r"(?i)\bper (?:pack|pizza|box|bag|bucket)\b|\b1 of \d|\beach\b|\bserve · \d+ per\b")
# The count, in the ways chains write it. Each gives the count and how to write one piece.
PIECE = r'(?:pcs?|pce|pieces?|ct|count)'
PATTERNS = [
    # Churros (5 pieces), Chicken Nuggets (8 pc), Saucy Chicken Wings, BBQ (5), French Toast Fingers (4)
    ('paren', re.compile(rf'(?i)\s*\((\d+)(?:\s*({PIECE}|pack))?\)')),
    # Chicken McNuggets 6 pc, Crispy 5 Pc Chicken Strips, 3 Piece Dip & Crunch Tenders
    ('pc', re.compile(rf'(?i)(?<![\d.$/])\b(\d+)\s*-?\s*({PIECE})\b')),
    # 3 Pack Tenders, Tenders - 3 Pack, Naughty Natas 2 pack, Schnuggets 6 Pack, Pack of 6 Wings
    ('pack', re.compile(r'(?i)(?:\s*-\s*|\s+|^)(?:(\d+)\s*-?\s*pack\b|pack of (\d+)\b)')),
    # Healthy Fried Chicken Bites - 6
    ('dash', re.compile(r'\s+-\s+(\d+)$')),
    # 3 Wicked Wings, 10 Chicken McNuggets, 2 Baked Apple Pies
    ('lead', re.compile(r'(?i)^(\d+)\s+(?![%"\'″]|oz\b|ml\b|g\b|cm\b|inch|in\b|kg\b|cal\b|x\b|layer|grain|cheese|way\b)')),
    # Wings x6, 6x Wings
    ('times', re.compile(r'(?i)(?:\bx\s?(\d+)\b|\b(\d+)\s?x\s)')),
]
SERVES = re.compile(r'(?i)\s*\(serves? \d+\)')
GRAMS = re.compile(r'^\s*(?:about\s+)?(\d+(?:\.\d+)?)\s*g\b')
IRREGULAR = {'pies': 'pie', 'fries': 'fry', 'pieces': 'piece', 'mini': 'mini', 'churros': 'churro', 'tacos': 'taco',
             'potatoes': 'potato', 'tomatoes': 'tomato', 'cookies': 'cookie', 'brownies': 'brownie', 'patties': 'patty',
             'bites': 'bite', 'tenders': 'tender', 'sandwiches': 'sandwich', 'boneless': 'boneless', 'mozzarella': 'mozzarella'}


def slug(name):
    return re.sub(r'^-|-$', '', re.sub(r'[^a-z0-9]+', '-', name.lower()))


def singular(word):
    low = word.lower()
    if low in IRREGULAR:
        out = IRREGULAR[low]
    elif re.search(r'(?:ch|sh|x)es$', low):
        out = low[:-2]
    elif re.search(r'[^aeiou]ies$', low):
        out = low[:-3] + 'y'
    elif re.search(r'[^s]s$', low) and len(low) > 3 and not low.endswith('ous'):
        out = low[:-1]
    else:
        return word
    return word[:len(out)] if word.lower().startswith(out) else out.capitalize() if word[0].isupper() else out


def singular_phrase(text):
    """Singular of the noun a count applies to: the last word before 'with', '&', ',' or a bracket."""
    m = re.match(r"^(.*?)(\s+with\b.*|\s*[,(].*)?$", text)
    head, tail = m.group(1), m.group(2) or ''
    words = head.split(' ')
    words[-1] = singular(words[-1])
    # "3 Pieces Wicked Boneless", "3 Piece Dip & Crunch Tenders": the count's own word is singular too
    if len(words) > 1:
        words[0] = singular(words[0]) if words[0].lower() in ('pieces', 'pcs') else words[0]
    return ' '.join(words) + tail


def parse(name):
    """(count, base key, name of one piece), or None when the name gives no count."""
    for kind, pat in PATTERNS:
        m = pat.search(name)
        if not m:
            continue
        n = int(next(g for g in m.groups() if g and g.isdigit()))
        before, after = name[:m.start()], name[m.end():]
        if kind == 'paren':
            unit = m.group(2)
            one = f"{singular_phrase(before.strip())} (1{' ' + singular(unit) if unit and unit.lower() != 'pack' else ''}){after}"
        elif kind == 'pc':
            unit = singular(m.group(2)).lower()
            if before.strip():
                one = f"{singular_phrase(re.sub(r'\s+', ' ', before + after).strip(' -'))} (1 {unit})"
            else:
                one = f'1 {unit.capitalize()}{singular_phrase(after) if after.strip() else after}'
        elif kind in ('pack', 'dash', 'times'):
            one = f"{singular_phrase(re.sub(r'\s+', ' ', before + after).strip(' -'))} (1)"
        else:  # lead
            one = f'1 {singular_phrase(after)}'
        one = re.sub(r'\s+', ' ', SERVES.sub('', one)).strip()
        base = re.sub(r'\s+', ' ', SERVES.sub('', before + ' ' + after)).strip(' -,').lower()
        base = ' '.join(singular(w) for w in re.findall(r"[a-z0-9&']+", base) if w not in ('pc', 'pcs', 'piece', 'pieces', 'pack'))
        return n, base, one
    return None


def skipped(food):
    if food['cat'] in SKIP_CATS:
        return 'drink, swap or add-on'
    if SKIP_WORDS.search(food['name']) or SKIP_WORDS.search(food.get('serve') or ''):
        return 'comes with something else'
    if PER_PIECE.search(food.get('serve') or ''):
        return 'already per piece'
    return None


def split(food, n, name, chain_ids):
    r1 = lambda x: None if x is None else round(x / n, 1)
    one = {'id': f"{food['chain']}:{slug(name)}", 'chain': food['chain'], 'name': name, 'cat': food['cat'],
           'kj': round(food['kj'] / n), 'cal': round(food['cal'] / n), 'p': r1(food['p']), 'c': r1(food['c']), 'f': r1(food['f'])}
    g = GRAMS.match(food.get('serve') or '')
    grams = f'{round(float(g.group(1)) / n)} g · ' if g else ''
    one['serve'] = f"1 piece · {grams}{food['name']} ÷ {n}"
    if food.get('nut'):
        one['nut'] = {k: (round(v / n) if k == 'sodium' else round(v / n, 2 if k == 'salt' else 1)) if isinstance(v, (int, float)) else v
                      for k, v in food['nut'].items()}
    # Sauces and items sold on their own are the same size whatever the pack; removals, swaps and extras aren't.
    one['modifiers'] = [m for m in food.get('modifiers', []) if m.get('kind') == 'a' and m['key'].startswith('item:')]
    if food.get('diet'):
        one['diet'] = json.loads(json.dumps(food['diet']))
    for k in food:
        if k not in one and k not in ('price', 'pf'):
            one[k] = json.loads(json.dumps(food[k]))
    return one


def choose(packs):
    """The pack one piece comes from (see the notes at the top)."""
    sugar = lambda x: (x[0].get('nut') or {}).get('sugar')
    known = [sugar(x) / x[1] for x in packs if sugar(x) is not None]
    if known:
        least = min(known)
        packs = [x for x in packs if sugar(x) is None or sugar(x) / x[1] <= max(least * 3, least + 1)]
    per = lambda x: x[0]['kj'] / x[1]
    near = lambda a: [x for x in packs if abs(per(x) - per(a)) <= per(a) * 0.12]
    best = max(packs, key=lambda a: (len(near(a)), -per(a)))
    return min(near(best), key=lambda x: (x[1], per(x)))


def add_single_pieces(foods, log=print):
    """Returns (foods with single pieces added after the pack they come from, ids of chains that got any)."""
    ids = {f['id'] for f in foods}
    groups = {}
    have_single = set()
    for f in foods:
        p = parse(f['name'])
        if not p:
            continue
        n, base, one = p
        key = (f['chain'], base)
        if n == 1:
            have_single.add(key)
            continue
        if n > 100 or skipped(f):
            continue
        groups.setdefault(key, []).append((f, n, one))
    singles = {}
    for key, packs in groups.items():
        if key in have_single:
            continue
        f, n, one = choose(packs)
        lo, hi = min(x[0]['kj'] / x[1] for x in packs), max(x[0]['kj'] / x[1] for x in packs)
        if hi > lo * 1.12:
            log(f"  {key[0]}: {one} from {f['name']} ({round(f['kj'] / n)} kJ); the packs give {round(lo)}-{round(hi)} kJ a piece")
        new = split(f, n, one, ids)
        if new['id'] in ids:
            continue
        ids.add(new['id'])
        singles[f['id']] = new
    out = []
    for f in foods:
        if f['id'] in singles:
            out.append(singles[f['id']])
        out.append(f)
    return out, {s['chain'] for s in singles.values()}, list(singles.values())


NOTE = 'Single pieces (1 wing, 1 nugget and so on) are the published pack divided by its count.'


def noted(src):
    """A chain's source line with the single-pieces note on the end."""
    src = (src or '').rstrip()
    if NOTE in src:
        return src
    return f"{src}{'' if not src or src[-1] in '.)!' else '.'} {NOTE}".strip()


if __name__ == '__main__':
    if '--report' in sys.argv:
        import glob
        import pathlib
        root = pathlib.Path(__file__).resolve().parents[1] / 'MacroMenu'
        total = 0
        for fn in sorted(root.glob('MenuData*.json')):
            data = json.loads(fn.read_text())
            foods = [f for f in data['foods'] if '÷' not in (f.get('serve') or '')]
            print(f'== {fn.name}')
            _, _, added = add_single_pieces(foods)
            for s in added:
                print(f"  {s['chain']:14} {s['name']:55} {s['kj']:>5} kJ  {s['p']}/{s['c']}/{s['f']}  [{s['serve']}]")
            total += len(added)
        print(f'{total} single pieces')
    else:
        # export-menu.cjs: {"chains": [...], "foods": [...]} on stdin, the same back on stdout, notes on stderr.
        data = json.load(sys.stdin)
        data['foods'], chains, added = add_single_pieces(data['foods'], log=lambda s: print(s, file=sys.stderr))
        for c in data['chains']:
            if c['id'] in chains:
                c['src'] = noted(c.get('src'))
        print(f'Added {len(added)} single pieces.', file=sys.stderr)
        json.dump(data, sys.stdout, ensure_ascii=False)
