#!/usr/bin/env python3
"""Allergens for Leanr's dietary filters, from each restaurant's own allergen guide.

Grill'd, Nando's and Hungry Jack's publish allergens in their ordering apps (see diet-info.py). The other restaurants publish
them in a guide, a chart or a nutrition page, and this reads those, the same way: only what the restaurant says, with
"contains" kept apart from "may contain", and anything a guide doesn't cover left unknown.

- Per item: Domino's nutrition page ("Contains" and "May contain" on every product), Boost Juice's allergen chart, Oporto's
  and Red Rooster's allergen charts (P present, T trace), and Spud Bar's product guide (a "Contains" statement and the full
  ingredient list for every bowl).
- Per component, with the item built from the restaurant's own description of it: Guzman y Gomez (allergen table plus its
  table of each menu item's standard ingredients), Zambrero (allergen sheet plus its menu descriptions) and Schnitz (allergen
  guide plus its menu descriptions; Schnitz's nutrition is for a traditional crumb chicken schnitzel, so that's the build).
  Where a description leaves a choice open (which beans, which salsa), an allergen in only some of the choices is
  "may contain".

- Subway: its allergen guide PDF (subs, wraps, salads, breakfast, sides, cookies, mini subs and breads), and its rice bowl guide.
- McDonald's and KFC show theirs only inside their own pages. Those were read once in a normal browser (McDonald's own
  itemDetails data that each item page loads, and each item's "More Info" panel in KFC's guide) and saved as
  mcd-allergens.json and kfc-allergens.json, which `build` reads. KFC's combos, boxes and feasts have no allergen panel.

Usage:
    python3 ios/Scripts/allergen-guides.py fetch   # downloads and reads the guides into allergen-source.json (about 12 requests)
    python3 ios/Scripts/allergen-guides.py build   # matches them to the exported menu, into allergen-items.json (diet-info.py reads it)
"""
import collections, html, json, re, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "allergen-source.json"
OUT = HERE / "allergen-items.json"
CATALOG = HERE.parent / "MacroMenu" / "MenuData.json"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

# The allergen words guides use, to Leanr's keys. Wheat is also gluten; every tree nut is a tree nut; crustaceans and
# molluscs are shellfish. Garlic, onion, caffeine and royal jelly aren't filtered on.
WORDS = [
    (r"wheat|spelt", ["gluten", "wheat"]), (r"gluten|barley|\brye\b|\boats?\b|cereal", ["gluten"]), (r"\bmilk|dairy", ["milk"]),
    (r"\beggs?\b", ["egg"]), (r"\bsoy", ["soy"]), (r"sesame", ["sesame"]), (r"peanut", ["peanut"]),
    (r"tree ?nut|almond|brazil|cashew|hazelnut|macadamia|pecan|peacan|pine ?nut|pistachio|walnut", ["treenut"]),
    (r"\bfish", ["fish"]), (r"crustace|mollusc|shellfish", ["shellfish"]), (r"lupin", ["lupin"]), (r"sulph|sulfite", ["sulphites"]),
]


def keys(words):
    """Every allergen named in some words: "Wheat Gluten Milk" is gluten, wheat and milk."""
    words = words.lower()
    return sorted({k for pattern, out in WORDS if re.search(pattern, words) for k in out})


def get(url, binary=False):
    out = subprocess.run(["curl", "-sfL", "-A", UA, "-m", "90", url], capture_output=True, check=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def link(page_url, pattern):
    """The first link on an official page whose address matches, so a guide that's replaced with a newer file is still found."""
    page = get(page_url)
    for href in re.findall(r'href="([^"]+)"', page):
        href = html.unescape(href)
        if re.search(pattern, href, re.I):
            return href if href.startswith("http") else re.match(r"https?://[^/]+", page_url).group(0) + href
    raise SystemExit(f"No link matching {pattern} on {page_url}")


def get_http1(url, binary=False):
    """For sites whose servers drop HTTP/2 requests from curl."""
    out = subprocess.run(["curl", "-sfL", "--http1.1", "-m", "120", url], capture_output=True, check=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def pdf(url):
    import pymupdf
    path = Path(tempfile.mkdtemp()) / "guide.pdf"
    path.write_bytes(get(url, binary=True))
    return pymupdf.open(path)


# Grids: product rows, one column per allergen, a mark in each cell that has one.

def columns(page, names, band, gap=2, left=0):
    """The x centre of each column from its heading. names: [(key, first word of the heading)], left to right."""
    words = [w for w in page.get_text("words") if band[0] <= w[1] <= band[1] and w[0] >= left]
    out, last = {}, -1
    for key, word in names:
        hits = sorted((w for w in words if w[4].strip(" *#∂").upper() == word.upper() and (w[0] + w[2]) / 2 > last), key=lambda w: w[0])
        if not hits:
            raise SystemExit(f"No heading {word}")
        x = (hits[0][0] + hits[0][2]) / 2
        out[key], last = x, x + gap
    return out


def lines(words, gap=2.5):
    out = []
    for w in sorted(words, key=lambda w: ((w[1] + w[3]) / 2, w[0])):
        y = (w[1] + w[3]) / 2
        if out and abs(out[-1][0] - y) < gap:
            out[-1][1].append(w)
        else:
            out.append([y, [w]])
    return [(y, re.sub(r"\s+", " ", " ".join(x[4] for x in sorted(ws, key=lambda x: x[0]))).strip()) for y, ws in out]


def rows(labels, marks, cols, gap=3, reach=8, width=9):
    """Rows from label lines and marks: a row's marks sit level with its label, or between its lines when the label wraps."""
    clusters = []
    for m in sorted(marks, key=lambda m: m[1]):
        if clusters and abs(clusters[-1]["y"] - m[1]) < gap:
            clusters[-1]["marks"].append(m)
        else:
            clusters.append({"y": m[1], "marks": [m], "text": []})
    lone = []
    for y, text in labels:
        near = min(clusters, key=lambda c: abs(c["y"] - y), default=None)
        if near and abs(near["y"] - y) < reach:
            near["text"].append((y, text))
        else:
            lone.append({"y": y, "marks": [], "text": [(y, text)]})
    out = []
    for c in sorted(clusters + lone, key=lambda c: c["y"]):
        out.append((" ".join(t for _, t in sorted(c["text"])), cells(c["marks"], cols, width)))
    return out


def bands(page, top, bottom, min_rule=30, min_h=6):
    """Row bands between a table's horizontal rules."""
    ys = sorted({round(d["rect"].y0) for d in page.get_drawings() if d["rect"].height < 1.5 and d["rect"].width >= min_rule
                 and top - 2 <= d["rect"].y0 <= bottom + 2})
    ys = [y for i, y in enumerate(ys) if i == 0 or y - ys[i - 1] > 2]
    return [(a, b) for a, b in zip(ys, ys[1:]) if b - a >= min_h]


def band_rows(page, row_bands, cols, label_right, marks, width=12):
    words = page.get_text("words")
    out = []
    for y0, y1 in row_bands:
        label = " ".join(w[4] for w in sorted((w for w in words if w[2] <= label_right and y0 - 1 <= (w[1] + w[3]) / 2 <= y1 + 1),
                                                key=lambda w: (round(w[1]), w[0])))
        out.append((re.sub(r"\s+", " ", label).strip(), cells([m for m in marks if y0 - 1 <= m[1] <= y1 + 1], cols, width)))
    return out


def cells(marks, cols, width):
    out = {}
    for x, _, v in marks:
        key = min(cols, key=lambda k: abs(cols[k] - x))
        if abs(cols[key] - x) < width:
            out.setdefault(key, set()).add(v)
    return out


def entry(contains, may=(), unk=(), vg=None, text=None):
    al = sorted({k for word in contains for k in keys(word)})
    out = {"al": al, "may": sorted({k for word in may for k in keys(word)} - set(al))}
    unk = sorted(set(unk) - set(al) - set(out["may"]))
    if unk:
        out["unk"] = unk
    if vg:
        out["vg"] = vg
    if text:
        out["text"] = text
    return out


def gluten_unknown_wheat(e, said):
    """A guide that only says "gluten" hasn't said whether it's wheat."""
    if ("gluten" in e["al"] or "gluten" in e["may"]) and not re.search(r"wheat|barley|\brye\b|\boats?\b|spelt", said, re.I):
        e["unk"] = sorted(set(e.get("unk", [])) | {"wheat"})
    return e


# The guides.

def dominos():
    page = get("https://www.dominos.com.au/menu/nutritional-information/")
    cards = list(re.finditer(r'id="([^"]+)-nutritional-info-product-card"', page))
    out = {}
    for i, m in enumerate(cards):
        body = page[m.end(): cards[i + 1].start() if i + 1 < len(cards) else len(page)]
        name = html.unescape(re.search(r'product-card-heading">(.*?)</div>', body, re.S).group(1)).strip()
        contains, may = [], []
        # "May contain" spans for the gluten-free base are hidden until that base is chosen; only shown ones count.
        for attrs, text in re.findall(r"<span ([^>]*data-contains-allergen=[^>]*)>([^<]*)</span>", body):
            if "display: inline" in attrs:
                (contains if "data-contains-allergen='true'" in attrs else may).append(html.unescape(text).strip(" ,"))
        labels = re.findall(r"Suitable for (Veg\w+)", body)
        vg = "vegan" if "Vegans" in labels else "vegetarian" if labels else None
        out.setdefault(name, entry(contains, may, vg=vg))
    return out


def boost():
    doc = pdf(link("https://www.boostjuice.com.au/", r"Allergens.*\.pdf"))
    page = doc[0]
    words = page.get_text("words")
    head = min(w[1] for w in words if w[4] == "Caffine")
    names = [("vegan", "Vegan"), ("milk", "Milk"), ("egg", "Egg"), ("wheat", "Wheat"), ("oats", "Oats"), ("barley", "Barley"),
             ("rye", "Rye"), ("lupin", "Lupin"), ("sesame", "Sesame"), ("peanut", "Peanut"), ("soy", "Soy"), ("fish", "Fish"),
             ("mollusc", "Mollusc"), ("crustacean", "Crustacean"), ("almond", "Almond"), ("brazil", "Brazil"), ("cashew", "Cashew"),
             ("hazelnut", "Hazelnut"), ("macadamia", "Macadamia"), ("pecan", "Pecan"), ("pistachio", "Pistachio"),
             ("walnut", "Walnut"), ("pinenut", "Pine"), ("sulphites", "Sulphites"), ("caffeine", "Caffine"), ("vegetarian", "Vegetarian")]
    # A key left of the chart also says "Vegan".
    cols = columns(page, names, (head - 40, head + 30), left=120)
    first = min(cols.values())
    # The chart's first table runs down to the boosters; the drink cards below it repeat the same drinks.
    end = min(w[1] for w in words if w[4] == "BOOSTERS" and w[1] > head)
    labels = [l for l in lines([w for w in words if w[2] < first - 6 and head + 20 < w[1] < end]) if not re.fullmatch(r"[A-Z ]{3,}", l[1])]
    marks = [((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, w[4]) for w in words if w[4] in ("Y", "N") and head + 20 < w[1] < end]
    out = {}
    for label, vals in rows(labels, marks, cols, reach=9, width=6):
        if not vals:
            continue
        said = {k for k, v in vals.items() if v == {"Y"}}
        # Vegan is shown as a mark only where it's not ("N"); vegan drinks have a symbol instead.
        vg = "vegetarian" if "vegetarian" in said else None
        if vg and vals.get("vegan") != {"N"}:
            vg = "vegan"
        # Category labels ("TROPICAL") sit level with a row; "(vit A & C)" says what the booster adds.
        name = re.sub(r"^(?:[A-Z]{3,} )+|\s*\(vit [^)]*\)", "", re.sub(r"[†^‡°#]", "", label)).strip()
        out[name] = entry([k for k in said if k not in ("vegan", "vegetarian", "caffeine")], vg=vg)
    return out


def craveable(url, brand):
    """Oporto's and Red Rooster's charts: P present, T trace, blank not reported by their suppliers."""
    nuts = ["ALMOND", "BRAZIL", "CASHEW", "HAZELNUT", "MACADAMIA", "PEACAN" if brand == "rr" else "PECAN", "PINE", "PISTACHIO", "WALNUT"]
    heads = ["GLUTEN", "WHEAT", "EGG", "MILK", "PEANUTS"] + nuts + ["SESAME", "SOY"] + (["SHELLFISH"] if brand == "rr" else []) + \
            ["FISH", "CRUSTACEAN", "MOLLUSCS", "ADDED", "ROYAL", "LUPIN"]
    named = {"ADDED": "sulphites", "PINE": "pine nut", "ROYAL": "royal jelly"}
    out = {}
    for page in pdf(url):
        words = page.get_text("words")
        top = next((w[3] for w in words if w[4].upper() == "GLUTEN"), None)
        if top is None:
            continue
        cols = columns(page, [(named.get(h, h.lower()), h) for h in heads], (top - 90, top + 5))
        first = min(cols.values())
        bottom = min([w[1] for w in words if w[4] in ("CHART", "Further", "FRYERS", "Fryers") and w[1] > top] + [1e9])
        labels = [l for l in lines([w for w in words if w[2] < first - 8 and top < w[1] < bottom])
                  if not l[1].isupper() and len(l[1]) > 2 and not l[1].startswith("CHICKEN (")]
        if brand == "rr":
            # Red Rooster's marks are little pictures: a red P and a grey T.
            kinds = {}
            for info in page.get_image_info(xrefs=True):
                if info["xref"] and info["xref"] not in kinds:
                    import pymupdf
                    pix = pymupdf.Pixmap(page.parent, info["xref"])
                    s = pix.samples
                    r, g = sum(s[0::pix.n]) / (len(s) / pix.n), sum(s[1::pix.n]) / (len(s) / pix.n)
                    kinds[info["xref"]] = "P" if r > g * 1.4 else "T"
            marks = [((i["bbox"][0] + i["bbox"][2]) / 2, (i["bbox"][1] + i["bbox"][3]) / 2, kinds[i["xref"]])
                     for i in page.get_image_info(xrefs=True) if i["xref"] and i["bbox"][2] - i["bbox"][0] < 10 and top < i["bbox"][1] < bottom]
        else:
            marks = [((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, w[4]) for w in words if w[4] in ("P", "T") and top < w[1] < bottom]
        for label, vals in rows(labels, marks, cols):
            if label and not label.startswith(("Contains Caffeine", "Test Stores", "TEST STORES", "MASH & GRAVY")):
                present = [k for k, v in vals.items() if "P" in v]
                trace = [k for k, v in vals.items() if "T" in v]
                out.setdefault(label, entry(present, trace))
    return out


def spud():
    doc = pdf(link("https://www.spudbar.com.au/menu", r"Product-Information-Guide.*\.pdf"))
    out = {}
    for page in doc:
        text = page.get_text()
        name = re.search(r"\n(THE [A-Z &()]+)\n", "\n" + text)
        said = re.search(r"Contains:\s*([^\n]*)", text)
        if name and said:
            ingredients = re.search(r"(Potato\..*?)(?:\n\d+\s*\n|\nAllergens|$)", text, re.S)
            words = [w.strip(" .") for w in said.group(1).split(",")]
            out[name.group(1).strip()] = gluten_unknown_wheat(entry(words, text=re.sub(r"\s+", " ", ingredients.group(1)) if ingredients else None), said.group(1))
    return out


def schnitz():
    url = link("https://schnitz.com.au/allergens/", r"Allergen-Information-(?!.*Saucy).*\.pdf")
    heads = [("wheat", "Wheat"), ("gluten", "Gluten"), ("egg", "Egg"), ("milk", "Milk"), ("soy", "Soy"), ("peanut", "Peanuts"),
             ("treenut", "Tree"), ("sesame", "Sesame"), ("shellfish", "Crustacea"), ("lupin", "Lupin"), ("fish", "Fish"),
             ("sulphites", "Sulphites"), ("garlic", "Garlic"), ("onion", "Onion")]
    parts = {}
    for page in pdf(url):
        words = page.get_text("words")
        top = next((w[3] for w in words if w[4] == "Wheat"), None)
        if top is None:
            continue
        cols = columns(page, heads, (top - 12, top + 2))
        first = min(cols.values())
        labels = lines([w for w in words if w[2] < first - 4 and w[1] > top])
        marks = [((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, w[4]) for w in words if w[4] in ("P", "M") and w[1] > top]
        for label, vals in rows(labels, marks, cols, gap=2.5, reach=4, width=14):
            present = [k for k, v in vals.items() if "P" in v and k not in ("garlic", "onion")]
            may = [k for k, v in vals.items() if "M" in v and k not in ("garlic", "onion")]
            parts.setdefault(label.strip(), {"al": present, "may": may})
    # What's on each burger, wrap and box, from Schnitz's menu.
    menu = get("https://schnitz.com.au/our-menu/")
    menu = re.sub(r"<script.*?</script>|<style.*?</style>", "", menu, flags=re.S)
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", menu)))
    text = re.sub(r"(\s*\|\s*)+", " | ", text)
    described = {}
    for m in re.finditer(r"\| ([A-Z][^|]{2,40}?) \| ([A-Z][^|]{15,300}?\.) \| Nutritional Information", text):
        described.setdefault(m.group(1).strip(), m.group(2).strip())
    return {"parts": parts, "described": described}


def zambrero():
    import pymupdf
    doc = pdf(link("https://www.zambrero.com.au/allergens", r"ALLERGEN-INFORMATION-SHEET.*\.pdf"))
    page = doc[0]
    words = page.get_text("words")
    heads = [("wheat", "WHEAT"), ("rye", "RYE"), ("barley", "BARLEY"), ("oats", "OATS"), ("gluten", "GLUTEN"), ("soy", "SOYBEAN"),
             ("egg", "EGG"), ("milk", "MILK"), ("peanut", "PEANUTS"), ("almond", "ALMOND"), ("brazil", "BRAZIL"), ("cashew", "CASHEW"),
             ("hazelnut", "HAZELNUT"), ("macadamia", "MACADAMIA"), ("pecan", "PECAN"), ("pinenut", "PINE"), ("pistachio", "PISTACHIO"),
             ("walnut", "WALNUT"), ("sesame", "SESAME"), ("fish", "FISH"), ("crustacean", "CRUSTACEAN"), ("mollusc", "MOLLUSC"),
             ("sulphites", "SULPHITES"), ("lupin", "LUPIN"), ("vegetarian", "VEGETARIAN"), ("vegan", "VEGAN")]
    top = next(w[3] for w in words if w[4] == "WHEAT")
    cols = columns(page, heads, (top - 30, top + 5))
    first = min(cols.values())
    # The marks are dots: green yes, dark green may contain, blue yes (naturally occurring).
    marks = []
    for d in page.get_drawings():
        fill, r = d.get("fill"), d["rect"]
        if fill and 3 < r.width < 12 and abs(r.width - r.height) < 1 and r.y0 > top:
            kind = "M" if fill[1] < 0.4 else "Y"
            marks.append(((r.x0 + r.x1) / 2, (r.y0 + r.y1) / 2, kind))
    labels = [l for l in lines([w for w in words if w[2] < first - 30 and w[1] > top]) if not l[1].startswith(("INFORMATION", "Individual", "may be", "contact"))]
    out = {}
    for label, vals in rows(labels, marks, cols, reach=5, width=10):
        if not label or label in ("YES", "MAY CONTAIN"):
            continue
        present = [k for k, v in vals.items() if "Y" in v and k not in ("vegetarian", "vegan")]
        may = [k for k, v in vals.items() if v == {"M"} and k not in ("vegetarian", "vegan")]
        vg = "vegan" if "vegan" in vals else "vegetarian" if "vegetarian" in vals else None
        out[label] = {"al": present, "may": may, "vg": vg}
    menu = get("https://www.zambrero.com.au/menu")
    menu = re.sub(r"<script.*?</script>|<style.*?</style>", "", menu, flags=re.S)
    text = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " | ", menu)))
    text = re.sub(r"(\s*\|\s*)+", " | ", text).replace("\ufeff", "")
    described = {}
    for m in re.finditer(r"\| ([A-Z][^|]{2,40}?) \| ((?:Protein|Choice)[^|]{10,400}?)(?= \|)", text):
        described.setdefault(m.group(1).strip(), m.group(2).strip())
    return {"parts": out, "described": described}


def gyg():
    doc = pdf(link("https://www.guzmanygomez.com.au/nutrition/", r"NUTRITION_ALLERGEN_GUIDE.*\.pdf"))
    allergen_heads = [("sulphites", "SULPHITES"), ("gluten", "GLUTEN"), ("egg", "EGG"), ("milk", "MILK"), ("peanut", "PEANUTS"),
                      ("sesame", "SESAME"), ("soy", "SOY"), ("hazelnut", "HAZELNUT"), ("walnut", "WALNUT"), ("lupin", "LUPINS"),
                      ("vegetarian", "VEGETARIAN"), ("vegan", "VEGAN")]
    builds_heads = [("BURRITO", "BURRITO"), ("BOWL", "BOWL"), ("ENCHILADA", "ENCHILADA"), ("CAESAR BURRITO", "CAESAR"),
                    ("CALI BURRITO", "CALI"), ("CAESAR CALI BURRITO", "CAESAR"), ("NACHOS", "NACHOS"), ("NACHO FRIES", "NACHO"),
                    ("TACO", "TACO"), ("CRISPY CHICKEN TENDER TACO", "CRISPY"), ("$3 TACO", "$3"), ("CAESAR SALAD", "CAESAR"),
                    ("KIDS NACHOS", "KIDS"), ("KIDS BURRITO", "KIDS"), ("KIDS BOWL", "KIDS"), ("QUESO FRIES", "QUESO"),
                    ("QUESADILLA", "QUESADILLA"), ("QUESADILLA PLUS", "QUESADILLA"), ("BREKKIE BURRITO", "BREKKIE"),
                    ("BREKKIE BOWL", "BREKKIE"), ("GUACAMOLE ON TOAST", "GUACAMOLE"), ("BREKKIE TACO", "BREKKIE"),
                    ("BREKKIE QUESADILLA", "BREKKIE"), ("BREKKIE QUESADILLA PLUS", "BREKKIE")]
    parts, builds, ingredients = {}, {}, {}
    for page in doc:
        text = page.get_text()
        words = page.get_text("words")
        marks = [((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, w[4]) for w in words]
        if text.startswith("ALLERGENS & DIETARY"):
            top = max(w[3] for w in words if w[4] == "SULPHITES")
            cols = columns(page, allergen_heads, (top - 150, top + 2))
            for label, vals in band_rows(page, bands(page, top, page.rect.height - 20), cols, min(cols.values()) - 15, [m for m in marks if m[1] > top]):
                if not label or label.isdigit():
                    continue
                # X contains; TRACE, TRACE* and ~ (may contain wheat, gluten, milk and egg) are may contain.
                present = [k for k, v in vals.items() if "X" in v and k not in ("vegetarian", "vegan")]
                may = [k for k, v in vals.items() if v & {"~", "TRACE", "TRACE*"} and k not in ("vegetarian", "vegan")]
                vg = None if "NO" in vals.get("vegetarian", ()) else "vegetarian" if vals.get("vegan") else "vegan"
                # GYG's gluten column is "Gluten / Wheat".
                wheat = lambda ks: ["wheat" if k == "gluten" else k for k in ks]
                parts[label] = {"al": wheat(present), "may": wheat(may), "vg": vg}
        elif "FOOD MENU ITEM" in text or "DESSERT MENU ITEM" in text:
            anchor = next((w for w in words if w[4] == "ENCHILADA"), None)
            if not anchor:
                continue
            top = anchor[3]
            cols = columns(page, builds_heads, (top - 140, top + 2), gap=20)
            for label, vals in band_rows(page, bands(page, top, page.rect.height - 20), cols, min(cols.values()) - 15, [m for m in marks if m[1] > top]):
                if label and label != "Filling of Choice":
                    builds.setdefault(label, {k: sorted(v) for k, v in vals.items()})
        elif text.startswith("INGREDIENTS LIST") or "INGREDIENTS LIST" in text[:40]:
            for m in re.finditer(r"\n([A-Z][^\n]{2,80})\n((?:[^\n]+\n){1,12}?)(?=[A-Z][^\n]{2,80}\n[A-Z]|\Z)", text):
                ingredients.setdefault(m.group(1).strip(), re.sub(r"\s+", " ", m.group(2)).strip())
    return {"parts": parts, "builds": builds, "ingredients": ingredients}


SUBWAY_COLUMNS = [("egg", "Egg"), ("fish", "Fish"), ("milk", "Milk"), ("sesame", "Sesame"), ("shellfish", "Crustaceans"), ("mollusc", "Mollusc"),
                  ("soy", "Soy"), ("peanut", "Peanut"), ("almond", "Almond"), ("brazil", "Brazil"), ("cashew", "Cashew"), ("hazelnut", "Hazelnut"),
                  ("macadamia", "Macadamia"), ("pecan", "Pecan"), ("pinenut", "Pine"), ("pistachio", "Pistachio"), ("walnut", "Walnut"),
                  ("lupin", "Lupin"), ("wheat", "Wheat"), ("gluten", "Gluten"), ("sulphites", "Sulphites"), ("yeast", "Autolyzed"),
                  ("nitrites", "Nitrites/Nitrates")]
# The section headings in Subway's guide, in the order they appear; recipes repeat under Subs, Wraps and Salads.
SUBWAY_SECTIONS = ["Mini Subs", "Breakfast", "Sides & Snacks", "Cookies", "Smoothies", "Bread", "Rice Bowls", "Bread & Rice Items", "Sauces & Dressings"]


def subway_grid(doc):
    """Subway's allergen guide: recipes down the page, an allergen in each column, ● contains and * may contain."""
    out, section, seen = {}, "Subs", collections.Counter()
    for page in doc:
        words = page.get_text("words")
        egg = [w for w in words if w[4] == "Egg" and w[1] < 250 and w[3] - w[1] > 12]   # the rotated heading
        if not egg:
            continue
        head = min(egg, key=lambda w: w[1])
        top, bottom_head = head[1], head[3]
        cols, last = {}, -1
        for key, word in SUBWAY_COLUMNS:
            hit = sorted((w for w in words if w[4] == word and top - 130 <= w[1] and w[3] <= bottom_head + 6 and (w[0] + w[2]) / 2 > last), key=lambda w: w[0])
            if hit:
                cols[key] = (hit[0][0] + hit[0][2]) / 2
                last = cols[key] + 2
        first = min(cols.values())
        body = [w for w in words if w[1] > bottom_head + 4 and w[2] < first - 3]
        label_lines = lines(body)
        marks = [((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, "C" if w[4] in ("●", "\u25cf", "•") else "m") for w in words
                 if w[4] in ("●", "*", "•", "\u25cf") and w[1] > bottom_head + 4 and w[0] >= first - 6]
        depth, names = 0, []
        for y, text in label_lines:
            if depth > 0:
                depth += text.count("(") - text.count(")")
                continue
            if text.startswith(("●", "**", "Please", "Seafood Origin", "1 ", "Page ")) or text.isdigit():
                continue
            if text.startswith("("):
                depth += text.count("(") - text.count(")")
                continue
            heading = next((h for h in SUBWAY_SECTIONS if text == h or text.startswith(h + " ")), None)
            if heading:
                # The three mini subs sit under a heading of their own, above Breakfast.
                if heading == "Breakfast":
                    names = [(y_, "Mini Subs" if sec_ == section else sec_, t_) for y_, sec_, t_ in names]
                section = heading
                continue
            if text.startswith("Wraps"):
                section = "Wraps"; continue
            if text.startswith("Salads"):
                section = "Salads"; continue
            if text.startswith("Subway 6"):
                section = "Subs"; continue
            # A heading's description, or a list's note, carries on in lower case.
            if text[:1].islower():
                continue
            m = re.match(r"^(.*?)\s*\((?!no sauce|with )(.*)$", text)
            if m and m.group(1):
                # "Smashed Avo on Toast (on white bread)" has its description on the same line.
                depth += text.count("(") - text.count(")")
                text = m.group(1).strip()
            names.append((y, section, text))
        for i, (y, sec, text) in enumerate(names):
            y1 = names[i + 1][0] - 2 if i + 1 < len(names) else y + 40
            row = {}
            for x, my, v in marks:
                if y - 4 <= my < y1:
                    key = min(cols, key=lambda k: abs(cols[k] - x))
                    if abs(cols[key] - x) < 8:
                        row[key] = v
            name = re.sub(r"[®™]", "", text).strip()
            out.setdefault((sec, name), row)
    return out


def subway():
    page = get_http1("https://www.subway.com/en-au/menunutrition/nutrition")
    def find(pattern):
        m = re.search(r'href="([^"]*%s[^"]*\.pdf)"' % pattern, page, re.I)
        if not m:
            raise SystemExit(f"No Subway link matching {pattern}")
        return html.unescape(m.group(1))
    out = {}
    for name, link_ in (("grid", find(r"Allergen(?:%20|\s)Web(?:%20|\s)Guide")), ("rice", find(r"Rice(?:%20|\s)Bowls"))):
        import pymupdf
        path = Path(tempfile.mkdtemp()) / "guide.pdf"
        path.write_bytes(get_http1(link_, binary=True))
        rows_ = subway_grid(pymupdf.open(path))
        for (sec, item), row in rows_.items():
            contains = [k for k, v in row.items() if v == "C" and k not in ("yeast", "nitrites")]
            may = [k for k, v in row.items() if v == "m" and k not in ("yeast", "nitrites")]
            out[f"{sec}|{item}"] = {"al": sorted(set(contains)), "may": sorted(set(may) - set(contains))}
    return out


def hungry_jacks():
    """Hungry Jack's nutritional guide reports: for every product, its ingredients, "Contains:" and "May be present:"."""
    page = get("https://www.hungryjacks.com.au/nutrition-info")
    urls = sorted({html.unescape(u) for u in re.findall(r'href="([^"]*Allergen[^"]*\.pdf)"', page, re.I)})
    out = {}
    for url in urls:
        for page in pdf("https://www.hungryjacks.com.au" + url if url.startswith("/") else url):
            spans = [s for b in page.get_text("dict")["blocks"] for l in b.get("lines", []) for s in l["spans"] if s["text"].strip()]
            body = next((s["size"] for s in spans if s["text"].startswith(("Contains:", "Ingredients:"))), None)
            if not body:
                continue
            # Product names are the larger bold text at the left; everything else is body size.
            titles = [s for s in spans if "Bold" in s["font"] and s["size"] > body * 1.15 and s["bbox"][0] < 12 and "Report" not in s["text"]]
            groups = []
            for t in sorted(titles, key=lambda s: s["bbox"][1]):
                if groups and t["bbox"][1] - groups[-1][-1]["bbox"][3] < 2:
                    groups[-1].append(t)
                else:
                    groups.append([t])
            for i, g in enumerate(groups):
                top, bottom = g[-1]["bbox"][3], groups[i + 1][0]["bbox"][1] if i + 1 < len(groups) else 1e9
                rows_ = {}
                for s in sorted((s for s in spans if top <= s["bbox"][1] < bottom and s["size"] <= body * 1.05), key=lambda s: s["bbox"][1]):
                    y = next((k for k in rows_ if abs(k - s["bbox"][1]) < 1.2), s["bbox"][1])
                    rows_.setdefault(y, []).append(s)
                said, text, marked = {}, [], []
                for y in sorted(rows_):
                    line, last = "", None
                    for s in sorted(rows_[y], key=lambda s: s["bbox"][0]):
                        line += ("" if last is None or s["bbox"][0] - last < 0.3 else " ") + s["text"]
                        last = s["bbox"][2]
                    line = re.sub(r"\s+", " ", line).strip()
                    bold = " ".join(s["text"] for s in sorted(rows_[y], key=lambda s: s["bbox"][0]) if "Bold" in s["font"])
                    if line.startswith("Description"):
                        break
                    m = re.match(r".*?(Contains|May be present):\s*(.*)$", line)
                    if m:
                        said[m.group(1)] = m.group(2)
                    elif not said:
                        text.append(line.replace("Ingredients:", ""))
                        # Allergens are bolded in the ingredient list too.
                        marked.append(bold.replace("Ingredients:", ""))
                name = re.sub(r"\s+", " ", " ".join(t["text"] for t in g)).strip()
                if said or text:
                    out.setdefault(name, entry([said.get("Contains", "")] + marked, [said.get("May be present", "")],
                                               text=re.sub(r"\s+", " ", " ".join(text)).strip()))
    return out


def fetch():
    out = {"fetched": time.strftime("%Y-%m-%d")}
    for chain, read in (("dominos", dominos), ("boost", boost), ("oporto", lambda: craveable(link("https://www.oporto.com.au/nutrition-and-allergen/", r"Allergen-Chart.*\.pdf"), "oporto")),
                        ("rr", lambda: craveable(link("https://www.redrooster.com.au/nutritions/", r"AllergenChart.*\.pdf"), "rr")),
                        ("spud", spud), ("schnitz", schnitz), ("zam", zambrero), ("gyg", gyg), ("hj", hungry_jacks), ("sub", subway)):
        out[chain] = read()
        print(f"{chain}: {len(out[chain]) if 'parts' not in out[chain] else len(out[chain]['parts'])} rows")
    SOURCE.write_text(json.dumps(out, indent=1, ensure_ascii=False, default=sorted) + "\n")


# Matching the guides to the menu.

def norm(name):
    name = html.unescape(name).lower().replace("&", "and").replace("’", "'")
    return re.sub(r"[^a-z0-9]", "", name)


def combine(parts, choices=()):
    """An item made of parts, plus choices where the restaurant doesn't say which: an allergen in every choice is in the item,
    one in only some of them may be."""
    std = lambda words: {k for w in words for k in keys(w)}
    al, may, unk = set(), set(), set()
    for p in parts:
        al |= std(p["al"]); may |= std(p["may"]); unk |= set(p.get("unk", []))
    for options in choices:
        everywhere = set.intersection(*(std(o["al"]) for o in options))
        al |= everywhere
        may |= set().union(*(std(o["al"]) | std(o["may"]) for o in options)) - everywhere
        unk |= set().union(*(set(o.get("unk", [])) for o in options))
    vgs = [p.get("vg") for p in parts] + [o.get("vg") for options in choices for o in options]
    vg = None if None in vgs else "vegan" if all(v == "vegan" for v in vgs) else "vegetarian"
    out = {"al": sorted(al), "may": sorted(may - al)}
    if unk - al - may:
        out["unk"] = sorted(unk - al - may)
    if vg:
        out["vg"] = vg
    return out


def lookup(table, *names):
    by = {norm(k): v for k, v in table.items()}
    for name in names:
        if norm(name) in by:
            return by[norm(name)]
    return None


DOMINOS = {"Margherita": "Margarita", "BBQ Sausage & Onion": "BBQ Sausage and Onion", "Garlic Prawn": "Garlic Prawn - Imported Seafood",
           "Surf & Turf": "Surf and Turf - Imported Seafood", "Chicken Nuggets": "Saucy Chicken Nuggets 6 Pack No Sauce",
           "Southern Fried Chicken Bites (20)": "Southern Fried Chicken Bites 20 Pack", "Crispy Chips": "Crispy Chips with Domino's Pizza Salt",
           "Cheese & Garlic Scrolls (4)": "Cheese & Garlic Scrolls (4 Pack)", "Triple Cheese Bites (5)": "Triple Cheese Bites 5 Pack",
           "Mozzarella Cheese Twist (1 of 4)": "Mozzarella Cheese Twists", "Dipping Sauce: Creamy Garlic Aioli": "Creamy Garlic Aioli Dipping Sauce",
           "Dipping Sauce: Spicy Sriracha Mayo": "Spicy Sriracha Mayo Dipping Sauce", "Dipping Sauce: Marinara": "Marinara Sauce",
           "Mini Dutch Pancakes (12)": "Mini Dutch Pancakes 12 Pack", "Churros with Choc Dipping Sauce (4)": "Churros with Choc Dipping Sauce 4 Pack",
           "Churros with Nutella (2 serves)": "Churros with Nutella (2 Serves)"}
SAUCES = {"no": "No Sauce", "hot": "Hot Sauce", "bbq": "BBQ Sauce", "peri peri": "Peri Peri Sauce", "hot honey": "Hot Honey Sauce",
          "garlic butter": "Garlic Butter Sauce", "butter chicken": "Butter Chicken Sauce"}


def match_dominos(name, guide):
    name = DOMINOS.get(name, name)
    m = re.match(r"(Saucy Chicken Wings|Chicken Tenders|Saucy Chicken Nuggets), ([A-Za-z ]+) \(\d+\)$", name)
    if m:
        sauce = SAUCES.get(re.sub(r" sauce$", "", m.group(2).lower()))
        product = {"Saucy Chicken Wings": "Saucy Chicken Wings - ", "Chicken Tenders": "Saucy Chicken Tenders 4 Pack ",
                   "Saucy Chicken Nuggets": "Saucy Chicken Nuggets 6 Pack "}[m.group(1)]
        return lookup(guide, product + (sauce or ""))
    name = re.sub(r" \(1 slice\)$", "", name)
    return lookup(guide, DOMINOS.get(name, name))


OPORTO = {"Chicken Tenders": "Grilled Chicken Tenders (No Sauce)", "Spicy Chicken Bolas": "Spicy Bolas", "Chicken Rappa": "Grilled Chicken Rappa (w Mayo)",
          "Chicken Rappsnacker": "Rappsnacker (w Mayo)", "BBQ Pulled Chicken Loaded Chips": "Pulled Chicken Loaded Chips (w BBQ Sauce)",
          "Chilli Pulled Chicken Loaded Chips": "Pulled Chicken Loaded Chips (w Chilli Sauce)", "Breakfast Bowl": "Brekkie Bowl",
          "Breakfast Deluxe Burger": "Brekkie Deluxe Burger", "Breakfast Rappa": "Brekkie Rappa", "Dipping Sauce: Prego": "Prego",
          "Dipping Sauce: Garlic": "Garlic Dip", "Dipping Sauce: Original Chilli": "Original Chilli Sauce", "Dipping Sauce: Lemon & Herb": "Lemon & Herb",
          "Dipping Sauce: Extremo Picante": "Extremo Picante", "Dipping Sauce: Mayo": "Mayonnaise",
          "Chicken, Bacon & Egg Burger": "Chicken, Egg & Bacon Burger"}


def match_oporto(food, guide):
    name = food["name"]
    if re.match(r"(Quarter|Half|Whole) Chicken$", name):
        # Oporto's chickens are flame grilled and basted; the nutrition is for original chilli basting.
        basting = "Original Chilli Sauce" if "original chilli" in (food.get("serve") or "") else None
        parts = [lookup(guide, "Flame Grilled Chicken (No Basting)"), lookup(guide, basting) if basting else None]
        return combine(parts) if all(parts) else None
    if name == "Crispy Wings with O Sauce":
        parts = [lookup(guide, "Crispy Wings"), lookup(guide, "O Sauce")]
        return combine(parts) if all(parts) else None
    return lookup(guide, OPORTO.get(name, name))


RR = {"Quarter Chicken (roast)": "Roast Chicken", "Half Chicken (roast)": "Roast Chicken", "Whole Chicken (roast)": "Roast Chicken",
      "Fried Chicken (1 piece)": "Fried Chicken", "Hot Honey Fried Chicken (1 piece)": "Hot Honey Fried Chicken",
      "Reds Hot Fried Chicken (1 piece)": "Reds Hot Fried Chicken", "10 Cheesy Nuggets": "Cheesy Nuggets", "Sweet Potato": "Sweet Potatoes",
      "Crunchy Potato": "Crunchy Potatoes", "Battered Corn Wheels (5)": "Battered Corn Wheels", "Pineapple Fritters (4)": "Pineapple Fritter",
      "Vanilla Slice Bites (10)": "Vanilla Slice Bites"}


def match_rr(name, guide):
    base = re.sub(r" \((regular|large|family)\)$", "", name)
    base = RR.get(base, base)
    base = re.sub(r"^Dipping Sauce: ", "", base)
    found = lookup(guide, base)
    if found or not name.endswith("Burger"):
        return found
    # The chart lists each burger with roast and with fried chicken; the menu item doesn't say which.
    variants = [lookup(guide, f"{name} - Roast"), lookup(guide, f"{name} - Fried Chicken")]
    return combine([], [variants]) if all(variants) else None


SPUD = {"The Chilli Bean Burrito": "THE BURRITO (CHILLI BEANS)", "The Beef Burrito": "THE BURRITO (BEEF)"}


def match_schnitz(name, source):
    parts, described = source["parts"], source["described"]
    # Minis are the same build on a slider roll or mini wrap, which share a row with the regular ones.
    m = re.match(r"(?:Mini )?(.+?) (Burger|Slider|Wrap)$", name)
    if m and not name.startswith("Teeny"):
        filling = {"OMG": "OMG!", "Chip Butty": "Royal Chip Butty"}.get(m.group(1), m.group(1))
        bread = "Wrap (Regular & Mini)" if m.group(2) == "Wrap" else "Turkish Roll (Regular & Slider)"
        # Schnitz's nutrition for every burger and wrap is for a traditional crumb chicken schnitzel.
        got = [lookup(parts, "Chicken"), lookup(parts, "Traditional Crumb"), lookup(parts, bread), lookup(parts, filling)]
        if not all(got):
            return None
        out = combine(got)
        text = lookup(described, filling, m.group(1))
        if text:
            out["text"] = text
        return out
    m = re.match(r"(Small|Regular|Large|Family) (Original|Sweet Potato) Chips$", name)
    if m:
        return lookup(parts, {"Original": "Original Chips (with Chip Seasoning)", "Sweet Potato": "Sweet Potato Chips (with Paprika Salt)"}[m.group(2)])
    m = re.match(r"Teeny-Weeny Pack (Slider|Wrap)$", name)
    if m:
        # A kids' pack, with a traditional crumb chicken schnitzel.
        got = [lookup(parts, "Teeny-Weeny Pack"), lookup(parts, "Chicken"), lookup(parts, "Traditional Crumb"),
               lookup(parts, "Wrap (Regular & Mini)" if m.group(1) == "Wrap" else "Turkish Roll (Regular & Slider)")]
        return combine(got) if all(got) else None
    if name == "Kettle-Cooked Gravy":
        return next((v for k, v in parts.items() if k.startswith("Kettle Cooked Gravy")), None)
    aliases = {"3 Pack Tenders": "Signature Tender Pack - 3pk, 5pk, 10pk", "5 Pack Tenders": "Signature Tender Pack - 3pk, 5pk, 10pk",
               "10 Pack Tenders": "Signature Tender Pack - 3pk, 5pk, 10pk", "Original Tender": "Original Chicken Tender",
               "Spicy Tender": "Spicy Chicken Tender", "Schnuggets 6 Pack": "Chicken Schnuggets - 6pk, 12pk, 18pk",
               "Schnuggets 18 Pack": "Chicken Schnuggets - 6pk, 12pk, 18pk", "Chick'n'Gravy Loaded Chips": "Chick 'N' Gravy Loaded Chips",
               "Tender Box #2": "Tender Box #2, #3, #5", "Tender Box #3": "Tender Box #2, #3, #5", "Tender Box #5": "Tender Box #2, #3, #5"}
    return lookup(parts, aliases.get(name, name))


ZAM_PROTEIN = {"Barbacoa Beef": "BARBACOA BEEF", "Grilled Chicken": "GRILLED CHICKEN", "Pork": "PULLED PORK", "Lamb": "LAMB",
               "Classic Beef Mince": "CLASSIC BEEF MINCE", "Pulled Mushroom": "PULLED MUSHROOM"}


def match_zam(name, source):
    parts, described = source["parts"], source["described"]
    P = lambda n: lookup(parts, n)
    extras = {"Add Guacamole": ["GUACAMOLE"], "Add Pickled Red Onions": ["PICKLED RED ONIONS"], "Add Sesame Crunch Mix": ["SESAME CRUNCH MIX"],
              "Corn Chips & Zam Spice": ["CORN CHIPS", "ZAM SPICE"], "Corn Chips & Guacamole": ["CORN CHIPS", "GUACAMOLE"],
              "Chips with Seasoning (regular)": ["CHIPS", "CHIP SEASONING"], "Chips with Seasoning (big)": ["CHIPS", "CHIP SEASONING"]}
    if name in extras:
        got = [P(n) for n in extras[name]]
        return combine(got) if all(got) else None
    m = re.match(r"(?:(Small|Big) )?(.+?) \((.+)\)$", re.sub(r"^Classic (Small|Big) ", r"\1 Classic ", name))
    if m:
        size, kind, filling = m.groups()
        desc = lookup(described, " ".join(x for x in (size, kind) if x), kind, kind + " Stack")
        if not desc:
            return None
        # What a vegetarian one has instead of the protein is said after the build.
        build_, _, veg = desc.partition("Vegetarian (V)")
        lower = (build_ + (" " + veg if filling == "Vegetarian" else "")).lower()
        got, choices = [], []
        if filling == "Vegetarian":
            # Vegetarian builds swap the protein for extra guacamole, beans and rice.
            got.append(P("GUACAMOLE"))
        elif ZAM_PROTEIN.get(filling):
            got.append(P(ZAM_PROTEIN[filling]))
        else:
            return None
        if re.search(r"burrito|quesadilla|taco|dos capas", kind, re.I):
            tortillas = [P("6 INCH TORTILLA"), P("10 INCH TORTILLA"), P("12 INCH TORTILLA")] if "fluffy" not in lower else [P("FLUFFY TORTILLA")]
            choices.append(tortillas)
        if "taco shell" in lower or "dos capas" in kind.lower():
            got.append(P("TACO SHELLS"))
        if "black rice" in lower:
            got.append(P("COOKED BLACK RICE"))
        elif "rice" in lower:
            got.append(P("COOKED WHITE RICE"))
        if "beans" in lower:
            choices.append([P("PINTO BEANS"), P("BLACK BEANS")])
        for word, part in (("cheese", "CHEESE"), ("sour cream", "SOUR CREAM"), ("guacamole", "GUACAMOLE"), ("lettuce", "COS LETTUCE"),
                           ("signature salsa", "SIGNATURE SALSA®"), ("jalape", "JALAPEÑOS"), ("corn chips", "CORN CHIPS"),
                           ("zam spice", "ZAM SPICE"), ("pickled", "PICKLED RED ONIONS")):
            if word in lower:
                got.append(P(part))
        if re.search(r"\bchips\b", lower) and "corn chips" not in lower:
            got += [P("CHIPS"), P("CHIP SEASONING")]
        if re.search(r"\bsalsas\b", lower):
            choices.append([P("TOMATO SALSA"), P("CORN SALSA"), P("CORIANDER SALSA")])
        elif "tomato" in lower:
            got.append(P("TOMATO SALSA"))
        if not all(got) or not all(all(c) for c in choices):
            return None
        # Leanr's Zambrero items are without sauce, so the sauce isn't counted.
        return combine(got, choices)
    sauces = re.match(r"Sauce: (.+)$", name)
    if sauces:
        return P(sauces.group(1).upper() + " SAUCE")
    return None


GYG_FILLING = {"Grilled Chicken": "Free Range Chicken", "Ground Beef": "Ground Beef (Mince)", "Pulled Pork": "Pulled Pork",
               "Shredded Beef Brisket": "Shredded Beef Brisket", "Pulled Shiitake Mushroom": "Pulled Shiitake Mushroom",
               "Sautéed Vegetables with Guacamole": "Sautéed Vegetables with Guacamole", "Sautéed Vegetables": "Sautéed Vegetables with Guacamole",
               "Crispy Chicken Tenders": "Crispy Chicken Tenders", "Crispy Chicken Tender": "Crispy Chicken Tenders", "BBQ Beef Rib": "BBQ Beef Rib",
               "Bacon": "Bacon", "Free Range Chicken Chorizo": "Chorizo"}
# The builds table's names for parts, where the allergen table names them differently.
GYG_PART = {"Free Range Chicken": "Grilled Chicken", "Ground Beef (Mince)": "Ground Beef", "Flour Tortilla": "Flour Tortilla (Burrito, Enchilada, Soft Taco, Brekkie Taco, Quesadilla, Quesadilla Plus)",
            "Corn Tortilla (Hard taco shell (seasoned)": "Corn Tortilla (Hard Shell Tacos (Seasoned)", "GYG Spicy Sauce (Spicy Only)": "Spicy Sauce",
            "Pico de Gallo (fresh tomato salsa)": "Pico de Gallo", "Lettuce (Iceberg)": "Lettuce (Shredded Iceberg)", "Cos Lettuce": "Lettuce (Shredded Iceberg)",
            "Fresh Jalapeños": "Pickled Jalapeños & Carrots", "Queso": "Queso (Plain)", "Hash Brown": "Hash Browns (Brekkie only)",
            "Sourdough Bread": "Sourdough Bread (Brekkie Only)", "Scrambled Eggs / Egg Mix": "Scrambled Eggs (Brekkie Only)", "Avocado": "Avocado (Brekkie only)",
            "Chorizo": "Free Range Chicken Chorizo (Brekkie only)", "Bacon": "Bacon (Brekkie only)"}


def gyg_build(kind, filling, name, source):
    builds, parts = source["builds"], source["parts"]
    lower = name.lower()
    spicy = "spicy" in lower
    got = []
    for part, cols in builds.items():
        marks = set(cols.get(kind, []))
        if not marks:
            continue
        if "*" in marks:
            if part != filling:
                continue
        elif "•" in marks:
            hard = "hard" in lower
            if ("Corn" in part) != hard:
                continue
        elif "R" in marks and filling == "BBQ Beef Rib":
            continue
        elif "T" in marks and filling in ("BBQ Beef Rib", "Crispy Chicken Tenders"):
            continue
        elif "S" in marks and filling != "BBQ Beef Rib":
            continue
        elif "P" in marks and "plain" in lower:
            continue
        elif "Spicy Only" in part and not spicy or "on request" in part:
            continue
        elif "SPICY" in marks and not spicy:
            continue
        got.append(lookup(parts, GYG_PART.get(part, part), part))
    if filling and not any(cols.get(kind) == ["*"] for p, cols in builds.items() if p == filling):
        if filling not in builds or kind not in builds[filling]:
            return None
    return combine(got) if got and all(got) else None


def match_gyg(name, source):
    parts = source["parts"]
    clean = re.sub(r"^Little G's ", "Kids ", name)
    clean = re.sub(r" Mini ", " ", clean)
    clean = re.sub(r"^Mini ", "", clean)
    fillings = sorted(GYG_FILLING, key=len, reverse=True)
    kinds = [("Caesar Cali Burrito", "CAESAR CALI BURRITO"), ("Caesar Burrito", "CAESAR BURRITO"), ("Cali Burrito", "CALI BURRITO"),
             ("Burrito Bowl", "BOWL"), ("Burrito", "BURRITO"), ("Bowl", "BOWL"), ("Enchilada", "ENCHILADA"), ("Nacho Fries", "NACHO FRIES"),
             ("Nachos", "NACHOS"), ("Quesadilla Plus", "QUESADILLA PLUS"), ("Quesadilla", "QUESADILLA"), ("Caesar Salad", "CAESAR SALAD"),
             ("Soft Taco (1)", "TACO"), ("Hard Taco (1)", "TACO")]
    kids = clean.startswith("Kids ")
    body = clean[5:] if kids else clean
    for word, kind in kinds:
        for f in fillings:
            if body == f"{f} {word}":
                if kids:
                    kind = {"BURRITO": "KIDS BURRITO", "BOWL": "KIDS BOWL", "NACHOS": "KIDS NACHOS"}.get(kind)
                    if not kind:
                        return None
                return gyg_build(kind, GYG_FILLING[f], body, source)
    if clean in ("Cheese Quesadilla",):
        return gyg_build("QUESADILLA", None, clean, source)
    if clean == "Kids Cheese Nachos":
        return gyg_build("KIDS NACHOS", None, clean, source)
    m = re.match(r"\$3 Taco \((mild|spicy) ground beef\)$", clean)
    if m:
        return gyg_build("$3 TACO", "Ground Beef (Mince)", clean, source)
    m = re.match(r"Crispy Chicken Tender Taco, (chipotle mayo|honey habanero ranch) - (soft|hard) shell$", clean)
    if m:
        out = gyg_build("CRISPY CHICKEN TENDER TACO", "Crispy Chicken Tenders", m.group(2), source)
        if out and m.group(1) != "chipotle mayo":
            return None  # the table only lists the chipotle mayo build
        return out
    m = re.match(r"Brekkie (Burrito|Bowl|Taco|Quesadilla Plus|Quesadilla) with (.+)$", clean.replace("Big Brekkie", "Brekkie"))
    if m:
        f = GYG_FILLING.get(m.group(2))
        return gyg_build("BREKKIE " + m.group(1).upper(), f, clean, source) if f else None
    m = re.match(r"(Small|Medium|Large) Queso \((plain|mild|spicy)\)$", clean)
    if m:
        return lookup(parts, f"Queso ({m.group(2).title()})")
    sides = {"Black Beans": "Black Beans", "Pinto Beans": "Pinto Beans", "Brown Rice": "Brown Rice", "White Rice": "White Rice", "Sour Cream": "Sour Cream",
             "Corn Chips": "Corn Chips", "Dipping Sauce: Sweet Chipotle BBQ": "Sweet Chipotle BBQ Sauce", "Dipping Sauce: Chipotle Mayo": "Chipotle Mayo",
             "Dipping Sauce: Herb Mayo": "Herb Mayo (VG)", "Dipping Sauce: Jalapeño Ketchup": "Jalapeño Ketchup", "Caesar Dressing": "Caesar Dressing",
             "Mini Caesar Dressing": "Caesar Dressing", "Kids Apple": "Apple", "Spicy Sauce (add to any item)": "Spicy Sauce", "Extra Guacamole": "Guacamole",
             "Chocolate Sauce portion": "Chocolate Sauce", "Dulce de Leche portion": "Dulce de Leche", "Soft Serve Cone": "Waffle Cone with Ice Cream",
             "Brekkie Extra: Bacon": "Bacon (Brekkie only)", "Brekkie Extra: Free Range Chicken Chorizo": "Free Range Chicken Chorizo (Brekkie only)",
             "Brekkie Extra: Free Range Scrambled Eggs": "Scrambled Eggs (Brekkie Only)", "Brekkie Extra: Hashbrown": "Hash Browns (Brekkie only)",
             "Brekkie Extra: Toast (1 Slice)": "Sourdough Bread (Brekkie Only)", "Brekkie Extra: Guacamole": "Guacamole", "Brekkie Extra: Pico de Gallo": "Pico de Gallo",
             "Brekkie Extra: Pulled Shiitake Mushroom": "Pulled Shiitake Mushroom", "Brekkie Extra: Sautéed Vegetables with Guacamole": "Sautéed Vegetables with Guacamole"}
    if clean in sides:
        return lookup(parts, sides[clean])
    m = re.match(r"(Small|Medium|Large) (Guacamole|Pico de Gallo|Tomatillo Salsa)$", clean)
    if m:
        return lookup(parts, m.group(2))
    m = re.match(r"Extra:? (Grilled Chicken|Ground Beef|Pulled Pork|Pulled Shiitake Mushroom|Sautéed Vegetables with Guacamole|Sautéed Vegetables|"
                 r"Shredded Beef Brisket|Guacamole|Crispy Chicken Tenders? \(\d\))$", clean)
    if m:
        f = re.sub(r" \(\d\)$", "", m.group(1))
        return lookup(parts, GYG_PART.get(GYG_FILLING.get(f, f), GYG_FILLING.get(f, f)))
    extras = {"Black Beans": "Black Beans", "Habanero Salsa": "Habanero Salsa (Salsa Station)", "Roasted Jalapeño Salsa": "Roasted Jalapeño Salsa (Salsa Station)",
              "Smokey Chipotle Salsa": "Smokey Chipotle Salsa (Salsa Station)", "Pickled Jalapeños": "Pickled Jalapeños & Carrots", "Queso (plain)": "Queso (Plain)",
              "Queso (mild)": "Queso (Mild)", "Lettuce (Bowl)": "Lettuce (Shredded Iceberg)", "Lettuce (Burrito)": "Lettuce (Shredded Iceberg)",
              "Cos Lettuce": "Lettuce (Shredded Iceberg)", "Crushed Corn Chips": "Corn Chips", "Crushed corn chips - Mini / Kids": "Corn Chips", "Spicy Sauce": "Spicy Sauce"}
    m = re.match(r"Extra:? (.+)$", clean)
    if m and m.group(1) in extras:
        return lookup(parts, extras[m.group(1)])
    if re.match(r"Brown Rice \((bowl|burrito) portion\)$", clean):
        return lookup(parts, "Brown Rice")
    dips = {"BBQ Sauce": "Sweet Chipotle BBQ Sauce", "Chipotle Mayo": "Chipotle Mayo", "Ketchup": "Ketchup"}
    m = re.match(r"(?:\d )?Crispy Chicken Tenders( & Fries)?(?: with (.+))?$", clean)
    if m:
        got, choices = [lookup(parts, "Crispy Chicken Tenders")], []
        if m.group(2):
            got.append(lookup(parts, dips.get(m.group(2), "")))
        if m.group(1):
            # The menu doesn't say which fries.
            choices.append([lookup(parts, "Fries (Unseasoned)"), lookup(parts, "Fries with Chipotle Seasoning")])
        return combine(got, choices) if all(got) and all(all(c) for c in choices) else None
    if clean == "Toast with guacamole":
        return gyg_build("GUACAMOLE ON TOAST", None, clean, source)
    if clean == "Toast with avocado":
        got = [lookup(parts, "Sourdough Bread (Brekkie Only)"), lookup(parts, "Avocado (Brekkie only)")]
        return combine(got) if all(got) else None
    m = re.match(r"(Churro|Large) Sundae with (Chocolate Sauce|Dulce de Leche|no topping)$", clean)
    if m:
        got = [lookup(parts, "Soft Serve Ice Cream")] + ([lookup(parts, "Churros"), lookup(parts, "Cinnamon Sugar")] if m.group(1) == "Churro" else []) + \
              ([lookup(parts, m.group(2))] if m.group(2) != "no topping" else [])
        return combine(got) if all(got) else None
    m = re.match(r"Fries with Chipotle Seasoning \((medium|large|family)\)$|Kids Fries with Chipotle Seasoning$", clean)
    if m:
        return lookup(parts, "Fries with Chipotle Seasoning")
    if clean == "Kids Fries with Plain Salt":
        return lookup(parts, "Fries (Unseasoned)")
    m = re.match(r"Corn Chips with (Medium|Large) (Guac|Pico de Gallo|Tomatillo Salsa|Queso|Mild Queso|Spicy Queso)$", clean)
    if m:
        dip = {"Guac": "Guacamole", "Queso": "Queso (Plain)", "Mild Queso": "Queso (Mild)", "Spicy Queso": "Queso (Spicy)"}.get(m.group(2), m.group(2))
        got = [lookup(parts, "Corn Chips"), lookup(parts, dip)]
        return combine(got) if all(got) else None
    m = re.match(r"Churros with (Chocolate Sauce|Dulce de Leche)$", clean)
    if m:
        got = [lookup(parts, "Churros"), lookup(parts, "Cinnamon Sugar"), lookup(parts, m.group(1))]
        return combine(got) if all(got) else None
    m = re.match(r"Queso Fries \((plain|mild|spicy), large\)$", clean)
    if m:
        out = gyg_build("QUESO FRIES", None, f"{m.group(1)} queso fries", source)
        if out:
            # The build lists "Queso"; the flavour is in the name.
            q = lookup(parts, f"Queso ({m.group(1).title()})")
            out = combine([out, q]) if q else None
        return out
    return None


HJ = {"Whopper with Cheese": "Whopper Cheese", "Double Whopper": "Whopper Double", "Whopper Junior with Cheese": "Whopper Junior Cheese",
      "Big Jack": "Big Jack Single", "Double Big Jack": "Big Jack Double", "Classic Jack's Fried Chicken": "Jack's Fried Chicken Classic",
      "Spicy Jack's Fried Chicken": "Jack's Fried Chicken Spicy", "Grilled Chicken Burger": "Grilled Chicken Classic",
      "Spicy Grilled Chicken Burger": "Grilled Chicken Spicy", "3 Nuggets": "Nugget 3 Pack", "6 Nuggets": "Nugget 6 Pack", "12 Nuggets": "Nugget 12 Pack",
      "3 Jack's Fried Chicken Tenders": "Chicken Tender Strips 3 x pack", "5 Jack's Fried Chicken Tenders": "Chicken Tender Strips 5 x pack",
      "Smoky BBQ Tender Snack Wrap": "JFC Tender Snack Wrap Smoky BBQ", "Creamy Pepper Tender Snack Wrap": "JFC Tender Snack Wrap Peppercorn",
      "Spicy Tender Snack Wrap": "JFC Tender Snack Wrap Spicy", "Sausage & Egg Turkish Brekky Roll": "Turkish Bread Sausage Egg",
      "Thick Cut Chips": "Chips", "Battered Onion Rings": "Onion Rings", "Big BBQ Brekky Wrap": "Wrap Big BBQ Brekky",
      "French Toast Fingers (4)": "French Toast Fingers 4 x pack", "French Toast Fingers (6)": "French Toast Fingers 6 x pack",
      "Cheese Toastie": "Toastie Cheese", "Ham & Cheese Toastie": "Toastie Ham Cheese", "Ham, Cheese & Tomato Toastie": "Toastie Ham Cheese Tomato",
      "Double Whopper with Cheese": "Whopper Double Cheese", "Triple Whopper with Cheese": "Whopper Triple Cheese", "Double Cheeseburger": "Cheeseburger Double",
      "Triple Cheeseburger": "Cheeseburger Triple", "Grill Masters Double BBQ Smokehouse Angus": "Grill Masters BBQ Smokehouse Angus Double",
      "Grill Masters Spicy Chipotle Angus": "Grill Masters Spicy Chipotle", "Grill Masters Double Spicy Chipotle Angus": "Grill Masters Spicy Chipotle Double",
      "Grill Masters Smoky Chipotle Angus": "Grill Masters Smoky Chipotle", "Grill Masters Double Smoky Chipotle Angus": "Grill Masters Smoky Chipotle Double",
      "Grill Masters Cowboy Angus": "Grill Masters Angus Cowboy", "Grill Masters Double Cowboy Angus": "Grill Masters Angus Cowboy Double",
      "Grill Masters Chicago Angus": "Grill Masters Angus Chicago", "Grill Masters Double Chicago Angus": "Grill Masters Angus Chicago Double",
      "Grill Masters Double Angus Bacon & Cheese": "Grill Masters Angus Bacon & Cheese Double",
      "Cheesy Bacon Classic Jack's Fried Chicken": "Jack's Fried Chicken Classic Cheese & Bacon",
      "Cheesy Bacon Spicy Jack's Fried Chicken": "Jack's Fried Chicken Spicy Cheese & Bacon", "Veggie Whopper with Cheese": "Whopper Veggie Cheese",
      "Plant-Based Whopper": "Whopper Plant Based", "Plant-Based Whopper with Cheese": "Whopper Plant Based Natural Cheese",
      "Plant-Based Angry Whopper": "Whopper Plant Based Angry Natural Cheese", "Chocolate Shake": "Shake Chocolate", "Strawberry Shake": "Shake Strawberry",
      "Vanilla Shake": "Shake Vanilla", "Caramel Shake": "Shake Caramel", "Pistachio Papi Shake": "Pistachio Shake", "Coke": "Coke POM",
      "Coke No Sugar": "Coke No Sugar POM", "Sprite": "Sprite POM", "Fanta Orange": "Fanta Orange POM", "Fanta Raspberry": "Fanta Raspberry POM",
      "Dirty Cola": "Jack'd Up Soda Dirty Cola", "Blue Lagoon": "Jack'd Up Soda Blue Lagoon", "Strawberry Dream": "Jack'd Up Soda Strawberry Dream",
      "Frozen Coke": "Coke FCB", "Frozen Coke Spider": "Coke FCB Spider", "Frozen Fanta Raspberry": "Fanta Raspberry FCB", "Frozen Keri Orange Mango": "Keri Orange Mango FCB",
      "Oreo Storm": "Storm Oreo", "Cadbury Flake Storm": "Storm Flake", "Pistachio Papi Storm": "Pistachio Storm", "Chocolate Sundae": "Sundae Chocolate",
      "Caramel Sundae": "Sundae Caramel", "Strawberry Sundae": "Sundae Strawberry", "Sticky Date Pudding": "Pudding Sticky Date", "Drumstick Mini Vanilla": "Drumstick Mini",
      "Dipping Sauce: BBQ Plum": "BBQ Plum Sauce Dipping Tub", "Dipping Sauce: Creamy Garlic Aioli": "Creamy Garlic Aioli Sauce Dipping Tub",
      "Dipping Sauce: Spicy": "Spicy Sauce Dipping Tub", "Dipping Sauce: Sweet 'n' Sour": "Sweet ’n’ Sour Sauce Dipping Tub",
      "Dipping Sauce: Ketchup": "Ketchup Sachet", "Dipping Sauce: Cheese Cup": "Dipper Cup Cheese", "Dipping Sauce: Crispy Onion Cup": "Dipper Cup Onion"}
# Jack's Cafe drinks, made with full cream milk.
HJ_CAFE = {"Cappuccino": "Cappuccino", "Flat White": "Flat White", "Latte": "Latte", "Long Black": "Long Black", "Mocha": "Mocha",
           "Hot Chocolate": "Hot Chocolate", "Chai Latte": "Chai", "Dirty Chai Latte": "Dirty Chai", "Iced Coffee": "Iced Coffee", "Iced Chocolate": "Iced Chocolate",
           "Iced Mocha": "Iced Mocha", "Iced Chai": "Chai Iced", "Iced Dirty Chai": "Dirty Chai Iced"}


def match_hj(name, guide):
    saucy = re.match(r"(\d) (.+) Saucy Tenders$", name)
    if saucy:
        name = f"JFC Saucy Tender {saucy.group(2)} {saucy.group(1)} x Pack"
    found = lookup(guide, HJ.get(name, name))
    if found:
        return found
    if name in HJ_CAFE:
        pattern = rf"jack.?s caf. {re.escape(HJ_CAFE[name].lower())} (small|medium|large)$"
    else:
        pattern = rf"{re.escape(HJ.get(name, name).lower())} (small|medium|large)$"
    sizes = [v for k, v in guide.items() if re.match(pattern, k.lower().replace("’", "'"))]
    # Leanr's item is one size; an allergen that differs between sizes may be in it.
    return combine([], [sizes]) if sizes else None


SUBWAY_BREKKIE = {"Classic Ham & Egg": "Classic Ham & Egg Sub", "Steak & Egg Brekkie": "Steak & Egg Brekkie Sub",
                  "Mexican-Style Brekkie": "Mexican-Style Brekkie Wrap", "Spinach & Egg Brekkie": "Spinach & Egg Wrap"}
SUBWAY_PARTS = {"Extra Chicken Strips": "Chicken Strips", "Extra Rotisserie-Style Chicken": "Rotisserie-Style Chicken", "Extra Chicken Teriyaki": "Chicken Teriyaki",
                "Extra Chicken Schnitzel": "Chicken Schnitzel", "Extra Smoky Bacon": "Bacon, Smoky", "Extra Leg Ham": "Leg Ham", "Poached Egg": "Poached Egg",
                "Extra Meatballs": "Meatballs", "Extra Diced Steak": "Steak, Diced", "Extra Sliced Turkey": "Turkey, Sliced", "Extra Avocado": "Avocado",
                "Extra Tuna & Mayo": "Tuna & Mayo (with Mayonnaise)", "Extra Cheddar Cheese": "Natural Cheddar Cheese", "Extra Mozzarella": "Mozzarella Cheese",
                "Italian Herbs & Cheese Bread": "Italian Herbs and Cheese Bread", "Regular Flour": "Wrap, Flour", "Ghost Pepper Bread": "Ghost Pepper Bread"}


def match_subway(name, guide):
    by = {norm(k.split("|", 1)[1]) + "|" + k.split("|", 1)[0]: v for k, v in guide.items()}
    def find(section, item):
        return by.get(norm(item) + "|" + section)
    bread = {"6\" White Bread": "White Bread", "6\" Wheat Bread": "Wheat Bread", "6\" Malted Rye Bread": "Malted Rye Bread",
             "6\" Italian Herbs & Cheese Bread": "Italian Herbs and Cheese Bread", "6\" Ghost Pepper Bread": "Ghost Pepper Bread",
             "Regular Flour Wrap": "Wrap, Flour"}
    if name in bread:
        return find("Bread", bread[name])
    # "Steak & Egg Brekkie 6"", "Mexican-Style Brekkie Wrap" and "Spinach & Egg Brekkie Wrap" are the guide's breakfast rows.
    m = re.match(r'^(.+?) (?:6"|Wrap)$', name)
    if m and m.group(1).replace(" Brekkie", "") in {k.replace(" Brekkie", "") for k in SUBWAY_BREKKIE}:
        base = next(k for k in SUBWAY_BREKKIE if k.replace(" Brekkie", "") == m.group(1).replace(" Brekkie", ""))
        return find("Breakfast", SUBWAY_BREKKIE[base])
    m = re.match(r'^(?:6"|Footlong) (.+)$', name)
    if m:
        item = "Turkey on Rye" if m.group(1) == "Turkey" else m.group(1)
        return find("Subs", item)
    m = re.match(r"^(.+?) (Wrap|Salad)(?: \((?:large|regular)\))?$", name)
    if m:
        item = "Turkey on Rye" if m.group(1) == "Turkey" else m.group(1)
        return find("Wraps" if m.group(2) == "Wrap" else "Salads", item)
    m = re.match(r"^(.+?) Rice Bowl \((?:regular|large)\)$", name)
    if m:
        return find("Rice Bowls", m.group(1))
    m = re.match(r"^Mini Sub: (.+)$", name)
    if m:
        return find("Mini Subs", m.group(1).replace("Veggie Delite with Avo", "Veggie Delite with Avo"))
    if name in SUBWAY_BREKKIE:
        return find("Breakfast", SUBWAY_BREKKIE[name])
    m = re.match(r"^Southern Style Chicken Bites \((no sauce|spicy mayo)\)$", name)
    if m:
        return find("Sides & Snacks", "Southern Style Chicken Bites (no sauce)" if m.group(1) == "no sauce" else "Southern Style Chicken Bites (with spicy mayo)")
    if re.search(r"Cookie$", name):
        return find("Cookies", name)
    m = re.match(r"^(Mango|Mixed Berry Banana|Tropical) Smoothie$", name)
    if m:
        return find("Cookies", m.group(1))   # the smoothies list sits under the cookies on the page
    if name in SUBWAY_PARTS:
        part = SUBWAY_PARTS[name]
        return find("Bread", part) or find("Sauces & Dressings", part)
    for section in ("Sides & Snacks", "Bread"):
        found = find(section, name)
        if found:
            return found
    return None


MCD_ALIAS = {
    "Chicken McWings 3 pc": "chicken-mcwings", "Chicken McNuggets 3 pc": "3pc-chicken-mcnuggets", "Chicken McNuggets 6 pc": "6pc-chicken-mcnuggets",
    "Chicken McNuggets 10 pc": "10pc-chicken-mcnuggets", "Chicken McNuggets 20 pc": "20pc-chicken-mcnuggets", "Chicken McNuggets 40 pc": "40pc-chicken-mcnuggets",
    # The same food in another size has the same allergens.
    "Fries (small)": "small-fries", "Fries (medium)": "small-fries", "Fries (large)": "small-fries",
    "Flat White (medium, full cream)": "flat-white-medium", "Cappuccino (medium, full cream)": "cappuccino-large", "Cappuccino (large, full cream)": "cappuccino-large",
    "Latte (medium, full cream)": "latte-medium", "Mocha (medium, full cream)": "mocha-medium", "Hot Chocolate (medium, full cream)": "hot-chocolate-medium",
    "Vanilla Chai Latte (medium)": "chai-latte-medium", "Long Macchiato (small)": "macchiato", "Earl Grey Tea (medium)": "earl-grey-tea-small",
    "Red Bull Dragonberry Energiser": "red-bull-dragonberry-energiser-medium", "Red Bull (250 ml can)": "red-bull-energy-drink-250ml",
    "Lemon Drink (medium)": "lemon-flavour-drink-medium", "Lemon Lime & Bitters (medium)": "kirks-lemon-lime-bitters-medium",
    "Vanilla Coke (medium)": "coca-cola-vanilla-medium", "Fanta Orange (medium)": "fanta-medium", "Raspberry Fanta (medium)": "fanta-raspberry-medium",
    "Frozen Fanta Mango with Strawberry Popping Pearls (medium)": "frozen-fanta-mango-strawberry-popping-pearls-medium",
    "Coca-Cola (large)": "coca-cola-medium", "Sprite (large)": "sprite-medium", "Fanta Orange (large)": "fanta-medium", "Frozen Coke (large)": "frozen-coke-medium",
    "Frozen Fanta Orange (large)": "frozen-fanta-orange-medium", "Apple Juice (250 ml)": "pop-tops-apple-juice", "Calciyum Chocolate Milk (250 ml)": "calcium-chocolate",
    "Dipping Sauce: Big Mac": "big-mac-special-sauce", "Dipping Sauce: Ranch": "ranch-sauce", "Dipping Sauce: Aioli": "aioli-sauce",
    "Dipping Sauce: Sweet Mustard": "sweet-mustard-sauce", "Dipping Sauce: Spicy Buffalo": "spicy-buffalo-sauce", "Dipping Sauce: BBQ": "barbeque-sauce",
    "Dipping Sauce: Sweet & Sour": "sweet-n-sour-sauce", "Dipping Sauce: Ketchup": "ketchup", "Dipping Sauce: McChicken": "mcchicken-sauce",
    "Dipping Sauce: Tartare": "tartare-sauce", "Berry McPop": "berry-mcpops", "Biscoff McPop": "biscoff-mcpops", "Choc McPop": "choc-mcpops",
}


def match_mcd(food, source, ingredient_ids):
    items = source["items"]
    pid = ingredient_ids.get(food["id"])
    found = items.get(str(pid)) if pid else None
    if not found:
        by_slug = {v["h"]: v for v in items.values()}
        slug = re.sub(r"[^a-z0-9]+", "-", food["name"].lower()).strip("-")
        found = by_slug.get(MCD_ALIAS.get(food["name"])) or by_slug.get(food["id"].split(":", 1)[1]) or by_slug.get(slug)
    return {"al": found["al"], "may": found["may"]} if found else None


def match_kfc(name, source):
    import unicodedata
    clean = lambda x: re.sub(r"[^a-z0-9]", "", unicodedata.normalize("NFKD", re.sub(r"[®™]", "", x)).encode("ascii", "ignore").decode().lower())
    by = {clean(k): v for k, v in source["items"].items()}
    name = re.sub(r"^Dipping Sauce: (.+)$", r"\1 Dip", name)
    sized = re.match(r"^(.+) \((regular|large)\)$", name)
    tries = [name, f"{sized.group(2)} {sized.group(1)}" if sized else name, f"{sized.group(1)} - {sized.group(2)}" if sized else name,
             "new " + name, name.replace("Pieces of", "Pieces Of")]
    for t in tries:
        found = by.get(clean(t))
        if found:
            return {"al": found["al"], "may": found["may"]}
    return None


def build():
    source = json.loads(SOURCE.read_text())
    catalog = json.loads(CATALOG.read_text())["foods"]
    out, missed = {}, {}
    # McDonald's and KFC only show their allergens inside their own pages, so those are read once in a browser and saved
    # (mcd-allergens.json, kfc-allergens.json); the notes in each say how.
    mcd_source = json.loads((HERE / "mcd-allergens.json").read_text()) if (HERE / "mcd-allergens.json").exists() else None
    kfc_source = json.loads((HERE / "kfc-allergens.json").read_text()) if (HERE / "kfc-allergens.json").exists() else None
    mcd_ids = {k: v[0] for k, v in json.loads((HERE / "mcd-ingredients.json").read_text())["items"].items()}
    for food in catalog:
        chain, name = food["chain"], food["name"]
        got = None
        if chain == "dominos":
            got = match_dominos(name, source["dominos"])
        elif chain == "boost":
            got = lookup(source["boost"], re.sub(r" \((original|medium)\)$", "", name))
        elif chain == "oporto":
            got = match_oporto(food, source["oporto"])
        elif chain == "rr":
            got = match_rr(name, source["rr"])
        elif chain == "spud":
            got = lookup(source["spud"], SPUD.get(name, name))
        elif chain == "schnitz":
            got = match_schnitz(name, source["schnitz"])
        elif chain == "zam":
            got = match_zam(name, source["zam"])
        elif chain == "gyg":
            got = match_gyg(name, source["gyg"])
        elif chain == "hj":
            got = match_hj(name, source["hj"])
        elif chain == "sub":
            got = match_subway(name, source["sub"])
        elif chain == "mcd" and mcd_source:
            got = match_mcd(food, mcd_source, mcd_ids)
        elif chain == "kfc" and kfc_source:
            got = match_kfc(name, kfc_source)
        else:
            continue
        if got:
            out[food["id"]] = {**got, "src": "guide"}
        else:
            missed.setdefault(chain, []).append(name)
    OUT.write_text(json.dumps({"fetched": source["fetched"], "items": out}, indent=1, ensure_ascii=False) + "\n")
    print(f"Allergens for {len(out)} items")
    for chain, names in sorted(missed.items()):
        print(f"  {chain}: no guide row for {len(names)}: {', '.join(names[:12])}{' …' if len(names) > 12 else ''}")


if __name__ == "__main__":
    {"fetch": fetch, "build": build}[sys.argv[1] if len(sys.argv) > 1 else "build"]()
