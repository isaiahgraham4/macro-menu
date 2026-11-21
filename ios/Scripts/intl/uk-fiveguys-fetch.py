#!/usr/bin/env python3
"""Five Guys (UK): the UK allergen, ingredient and nutrition guide PDF linked from fiveguys.co.uk.

The guide is one tall page: an allergen grid (a dot = contains, "1" = not suitable for that allergy because of how it is
made or prepared), the ingredient listing, then the nutrition table (per serving, then per 100 g). Nutrition is read
from the text in order; allergens from the grid by position. Writes uk-fiveguys-source.json next to this script.
The PDF is downloaded to the scratch folder given by FIVEGUYS_PDF_DIR (default: /tmp), never into the repo.
"""
import datetime
import tempfile
import json
import os
import re
import urllib.request
from pathlib import Path

import pymupdf

PAGE = "https://www.fiveguys.co.uk/nutritional-allergy-information/"
OUT = Path(__file__).with_name("uk-fiveguys-source.json")
PDF_DIR = Path(os.environ.get("FIVEGUYS_PDF_DIR",
                              tempfile.gettempdir()))
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

# Allergen grid columns, left to right (celery and mustard have no key in the app).
COLS = ["treenut", "peanut", "sesame", "milk", "egg", "lupin", "soy", "gluten", "fish", "shellfish", None,
        "shellfish", "sulphites", None]
ORDER = ["gluten", "wheat", "milk", "egg", "soy", "sesame", "peanut", "treenut", "fish", "shellfish", "lupin", "sulphites"]


def get(url, binary=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-GB"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    return data if binary else data.decode("utf-8", "replace")


def guide_url():
    page = get(PAGE)
    links = re.findall(r'https://[^"\']*FGUK[^"\']*allergen[^"\']*nutrition[^"\']*\.pdf', page, re.I)
    if not links:
        raise SystemExit("No UK allergen/nutrition guide linked on the Five Guys page")
    return links[0]


def clean(name):
    name = re.sub(r"[*®]", "", name)
    name = name.replace("’", "'")
    return re.sub(r"\s+", " ", name).strip()


def key(name):
    k = clean(name).split(" Patty,")[0].lower()
    k = re.sub(r"\(including diced\)|\(pasteurised\)|\(\d+g\)", "", k)
    k = re.sub(r"\blittle\b", "", k)
    k = k.replace("sand- wich", "sandwich").replace("crispy fried onions", "crispy onions")
    k = re.sub(r"^diced ", "", k)
    k = re.sub(r"[^a-z&]+", " ", k)
    return re.sub(r"\s+", " ", k).strip()


# ---- allergen grid --------------------------------------------------------------------------------------------------

def allergen_grid(page, stop_y):
    words = [w for w in page.get_text("words") if 330 < w[1] < stop_y]
    names, marks = [], []
    for w in words:
        if w[0] < 395:
            names.append(w)
        elif w[4] in ("•", "1"):
            marks.append(((w[0] + w[2]) / 2, (w[1] + w[3]) / 2, w[4]))
    # Left-hand text into lines, then lines less than 22 units apart into one product name.
    lines = {}
    for w in names:
        y = next((k for k in lines if abs(k - w[1]) < 4), w[1])
        lines.setdefault(y, []).append(w)
    groups = []
    for y in sorted(lines):
        text = " ".join(w[4] for w in sorted(lines[y], key=lambda w: w[0]))
        if groups and y - groups[-1]["y1"] < 22:
            groups[-1]["text"] += " " + text
            groups[-1]["y1"] = y
        else:
            groups.append({"text": text, "y0": y, "y1": y, "marks": []})
    for x, y, v in marks:
        g = min(groups, key=lambda g: 0 if g["y0"] - 6 <= y <= g["y1"] + 22 else min(abs(y - g["y0"]), abs(y - g["y1"])))
        col = round((x - 407) / 110)
        if 0 <= col < len(COLS) and abs(407 + 110 * col - x) < 15:
            g["marks"].append((col, v))
    out = {}
    for g in groups:
        if g["text"].isupper() and not g["marks"]:
            continue  # section heading
        contains = {COLS[c] for c, v in g["marks"] if v == "•" and COLS[c]}
        may = {COLS[c] for c, v in g["marks"] if v == "1" and COLS[c]} - contains
        out.setdefault(key(g["text"]), []).append((contains, may))
    return out


# ---- nutrition table ------------------------------------------------------------------------------------------------

NUM = re.compile(r"^-?\d+(\.\d+)?$")


def nutrition(text):
    start = text.index("INGREDIENT LISTING - GUIDE FOR USE IN UK LOCATIONS ONLY")
    end = text.index("NUTRITION GUIDE - UK LOCATIONS ONLY")
    lines = [l.strip() for l in text[start:end].split("\n") if l.strip()]
    lines = lines[lines.index("Salt, g", lines.index("Salt, g") + 1) + 1:]
    rows, section, name, nums = [], None, [], []

    def flush():
        if name and nums:
            rows.append((section, clean(" ".join(name)), nums[:9], nums[9:18]))

    for l in lines:
        if NUM.match(l):
            nums.append(float(l))
            continue
        if nums:
            flush()
            name, nums = [], []
        head = l[:12]
        if head == head.upper() and re.match(r"[A-Z]{3,}", head) and not l.startswith("BLT"):
            section = l
            name = []
        else:
            name.append(l)
    flush()
    return rows


def num(v):
    return int(v) if float(v).is_integer() else round(v, 2)


def main():
    url = guide_url()
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / "uk-fiveguys-guide.pdf"
    path.write_bytes(get(url, binary=True))
    doc = pymupdf.open(path)
    page = doc[0]
    text = page.get_text()
    stamp = re.search(r"FGUK_(\d{8})", text)
    dated = datetime.datetime.strptime(stamp.group(1), "%Y%m%d").strftime("%-d %B %Y") if stamp else "undated"
    heading_y = next(w[1] for w in page.get_text("words") if w[4] == "INGREDIENT" and w[0] < 200)
    grid = allergen_grid(page, heading_y)
    hp = re.search(r"HP Brown Sauce\n(.*?)\nJalap", text[text.index("INGREDIENT LISTING"):], re.S)
    hp_wheat = bool(hp and "WHEAT" in hp.group(1))

    items, dropped, unmatched = [], [], []
    seen = set()
    for section, raw, per, per100 in rows_of(text):
        if len(per) < 9:
            continue
        kj, kcal, fat, sat, carb, sugar, fibre, prot, salt = per
        sec = section or ""
        name, cat = rename(sec, raw)
        if name is None:
            continue
        if kcal == 0 and prot == carb == fat == 0:
            dropped.append(f"{raw} (no figures)")
            continue
        est = 4 * prot + 4 * carb + 9 * fat
        if (kcal >= 60 and abs(est - kcal) / kcal > 1 / 3) or (fat * 9 > kcal * 1.5 + 10):
            why = f"{raw} ({num(kcal)} kcal, macros add up to {round(est)})"
            if why not in dropped:
                dropped.append(why)
            continue
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        k = key(raw)
        if "milkshake base" in k:
            k = "five guys milkshake base"
        elif k == "egg sandwich":
            k = "egg sandwich"
        k = {"add bacon": "bacon", "mini fries": "fries", "reg fries": "fries", "large fries": "fries"}.get(k, k)
        rows_ = grid.get(k) or []
        # "Hot Dog" is both the sausage (MEAT) and the menu item (HOT DOGS): the grid lists them in that order.
        al = rows_[min(1, len(rows_) - 1)] if (rows_ and sec == "HOT DOGS") else (rows_[0] if rows_ else None)
        if al is None:
            unmatched.append(raw)
            contains, may = set(), set()
        else:
            contains, may = set(al[0]), set(al[1])
        if "gluten" in contains and (raw != "HP Brown Sauce" or hp_wheat):
            contains.add("wheat")
        weight = None
        if per100 and len(per100) >= 2 and per100[1] >= 20 and kcal > 0:
            weight = round(kcal / per100[1] * 100)
        items.append({
            "name": name, "cat": cat,
            "serve": f"1 serving ({weight} g)" if weight else "1 serving",
            "cal": num(kcal), "kj": num(kj),
            "p": num(prot), "c": num(carb), "f": num(fat),
            "sat": num(sat), "sugar": num(sugar), "fibre": num(fibre),
            "sodium": None, "salt": num(salt),
            "contains": [a for a in ORDER if a in contains],
            "may": [a for a in ORDER if a in may - contains],
            "vg": None, "meat": meat_of(name),
        })
    if unmatched:
        raise SystemExit(f"No allergen row for: {unmatched}")
    today = datetime.date.today().isoformat()
    out = {
        "chain": "uk-fiveguys",
        "name": "Five Guys",
        "how": "Official nutrition guide",
        "url": PAGE,
        "src": (f"Five Guys UK Allergen, Ingredient & Nutrition Guide, UK locations only (dated {dated}; checked {today}), "
                f"per serving as listed; serving weights are worked out from the per-100 g column. Milkshakes are the base plus "
                f"whipped cream and mix-ins, each listed on its own. Breakfast items are Heathrow only. Left out {len(dropped)}: "
                + "; ".join(dropped) + ". Allergens from the guide's grid; 'may' is Five Guys' 'not suitable due to "
                "manufacturing and preparation' mark."),
        "checked": today,
        "energy": "cal",
        "halal": False,
        "items": items,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(items)} items, left out {len(dropped)}")


def rows_of(text):
    return nutrition(text)


def rename(section, raw):
    """(display name, category), or (None, None) to skip."""
    r = raw
    s = section
    if r in ("Add Cheese",):
        return None, None  # same figures as the Cheese topping
    if s == "MEAT":
        return {"Bacon": "Bacon (add-on)", "Beef Burger Patty": "Beef Patty (add-on)",
                "Hot Dog": "Hot Dog Sausage (add-on)"}.get(r, r + " (add-on)"), "extra"
    if s == "BUN":
        return r, "extra"
    if s.startswith("FRIES"):
        m = re.match(r"(Mini|Little|Reg|Large) Fries", r)
        if m:
            return f"Fries ({ {'Reg': 'regular'}.get(m.group(1), m.group(1).lower()) })", "side"
        return r, "extra"
    if s.startswith("LOADED FRIES"):
        if r.startswith("Loaded"):
            return r, "side"
        return (r if not r.startswith("Fresh") else "Diced Onions") + " (loaded fries topping)", "extra"
    if s == "TOPPINGS":
        return {"Cheese (pasteurised)": "Cheese (1 slice)", "Crispy Fried Onions": "Crispy Onions"}.get(r, r), "extra"
    if s.startswith("MILKSHAKES"):
        if r == "Five Guys Milkshake Base":
            return "Milkshake base (regular)", "drink"
        if r == "Whipped Cream":
            return "Whipped Cream (regular shake)", "extra"
        return re.sub(r"\s*\((\d+)g\)", r" mix-in (\1 g, regular shake)", r) if "(" in r else r + " mix-in (regular shake)", "extra"
    if s.startswith("LITTLE MILKSHAKES"):
        base = re.sub(r"\s+Little$", "", r.replace(" Little ", " ")).strip()
        if base == "Five Guys Milkshake Base":
            return "Milkshake base (little)", "drink"
        if base == "Whipped Cream":
            return "Whipped Cream (little shake)", "extra"
        if "(" in base:
            return re.sub(r"\s*\((\d+)g\)", r" mix-in (\1 g, little shake)", base), "extra"
        return base + " mix-in (little shake)", "extra"
    if s == "BURGERS" or s == "HOT DOGS" or s == "SANDWICHES":
        if r.startswith("Lettuce Wrap"):
            return "Lettuce Wrap (patty with tomatoes, pickles, grilled onions, green peppers, mushrooms)", "main"
        if r.startswith("Bulk Peanuts"):
            return "Peanuts (shelled)", "side"
        return r.replace("BLT", "BLT"), "main"
    if s.startswith("BREAKFAST"):
        if r in ("Latte", "Cappuccino", "Flat White", "Americano Black", "Americano White", "Double Espresso", "Breakfast Tea"):
            return r, "drink"
        return r.replace("Sand- wich", "Sandwich"), "breakfast"
    if s.startswith("BUILD YOUR OWN"):
        if r == "Add Bacon":
            return "Bacon (breakfast add-on)", "extra"
        if r.startswith("Sausage Patty"):
            return "Sausage Patty (breakfast add-on)", "extra"
        return r, "breakfast"
    if s.startswith("SIDES"):
        return r, "breakfast"
    if s == "OTHER ITEMS":
        if r == "Egg":
            return "Egg (breakfast add-on)", "extra"
        if r.lower().startswith("cajun"):
            return "Cajun Seasoning", "extra"
    return r, "main"


def meat_of(name):
    n = name.lower()
    if "bacon" in n and ("dog" in n or "burger" in n or "cheeseburger" in n):
        return ["beef", "pork"]
    if "bun" in n:
        return None
    if "burger" in n or "patty (add-on)" in n or "lettuce wrap" in n:
        return ["beef"]
    if "hot dog" in n or "cheese dog" in n:
        return ["beef"]
    if "bacon" in n or "sausage" in n or n == "blt":
        return ["pork"]
    return None


if __name__ == "__main__":
    main()
