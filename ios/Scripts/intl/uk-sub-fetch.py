#!/usr/bin/env python3
"""Subway (UK): the UK & ROI "Builds and Ingredients Nutritional Information" PDF linked from subway.com/en-gb.

Pages 1-3 are menu builds (Subs, Toasties, Wraps, Salads, Spuds, Footlong Pizza, Sides, Protein Pots, Cookies,
Grab & Go, Pots), pages 4-5 the ingredients (breads, proteins, cheese, vegetables, sauces, dunk pots, toppings, other).
Each row is a name at the left and ten per-serving figures (serving g, kJ, kcal, fat, saturates, carbohydrate, sugars,
fibre, protein, salt) then the same per 100 g. Rows are rebuilt from word positions, since a few figures sit a line
off their name. Subs are 6-inch; Subway says a footlong is two 6-inch servings, so footlongs are doubled.
Subway's allergen guide lists allergens per ingredient, not per build, so allergens are left null.
subway.com drops HTTP/2 requests from scripts, so everything is fetched with curl --http1.1.
Writes uk-sub-source.json; the PDF goes to SUBWAY_PDF_DIR (default: the scratch pdfs folder), never into the repo.
"""
import datetime
import tempfile
import html
import json
import os
import re
import subprocess
from pathlib import Path

import pymupdf

PAGE = "https://www.subway.com/en-gb/menunutrition/nutrition"
OUT = Path(__file__).with_name("uk-sub-source.json")
PDF_DIR = Path(os.environ.get("SUBWAY_PDF_DIR",
                              tempfile.gettempdir()))

SECTIONS = {"Subs", "Toasties", "Wraps", "Salads", "Spuds", "Footlong Pizza", "Sides", "Protein Pots", "Cookies",
            "Grab & Go", "Pots", "BREADS", "PROTEINS", "CHEESE", "VEGETABLES", "SAUCES & CONDIMENTS", "DUNK POTS",
            "TOPPINGS", "OTHER"}
BREAKFAST = {"Bacon", "Poached Egg and Cheese", "Lincolnshire Sausage", "Lincolnshire Sausage and Bacon", "Big Breakwich"}
NUM = re.compile(r"^<?\d+(\.\d+)?$")


def curl(url, binary=False):
    # No browser User-Agent here: subway.com stalls curl requests that claim to be Chrome.
    out = subprocess.run(["curl", "-sfL", "--http1.1", "-m", "120", url], capture_output=True, check=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def guide_url():
    page = curl(PAGE)
    m = re.search(r'href="([^"]*Builds[^"]*Nutritional[^"]*\.pdf)"', page, re.I)
    if not m:
        raise SystemExit("No Builds and Ingredients nutrition PDF linked on the Subway UK page")
    return html.unescape(m.group(1))


def rows(doc):
    """[(section, name, [10 per-serving figures], [per-100 g figures])] in page order."""
    out, section = [], None
    for page in doc:
        names, nums = [], []
        for b in page.get_text("dict")["blocks"]:
            for l in b.get("lines", []):
                if l["dir"] != (1, 0):
                    continue
                for s in l["spans"]:
                    t = s["text"].strip()
                    if not t:
                        continue
                    x0, y0, x1, y1 = s["bbox"]
                    t2 = t.replace("#", "").strip()
                    if x0 >= 145 and NUM.match(t2):
                        nums.append((x0, y0, float(t2.lstrip("<"))))
                    elif x0 < 145 and y0 > 45:
                        names.append([y0, t, []])
        names.sort()
        if not names:
            continue
        for x, y, v in nums:
            n = min(names, key=lambda n: abs(n[0] - y))
            if abs(n[0] - y) <= 8:
                n[2].append((x, v))
        for y, t, cells in names:
            name = re.sub(r"\s+", " ", t).strip()
            if name in SECTIONS:
                section = name
                continue
            if len(cells) < 10:
                continue
            cells.sort()
            vals = [v for _, v in cells]
            out.append((section, name, vals[:10], vals[10:]))
    return out


def num(v):
    v = round(v, 2)
    return int(v) if float(v).is_integer() else v


def display(section, name):
    """(name, category, serve-noun), or None to leave the row out."""
    n = name.replace("Ulitmate", "Ultimate").replace("Rostisserie", "Rotisserie").replace("FajitaChicken", "Fajita Chicken")
    n = re.sub(r"\s+", " ", n).replace(" (Pork & Beef Meatballs)", "").strip()
    if "(ROI)" in n:
        return None
    halal = n.startswith("HALAL ")
    if halal:
        n = "Halal " + n[6:]
    s = section
    if s == "Subs":
        return n + " Sub", ("breakfast" if name in BREAKFAST else "main"), "sub"
    if s == "Toasties":
        return n + " Toastie", "main", "toastie"
    if s == "Wraps":
        return n + " Wrap", ("breakfast" if name in BREAKFAST else "main"), "wrap"
    if s == "Salads":
        return n + " Salad", "main", "salad"
    if s == "Spuds":
        return n.replace("  ", " ") + " Spud", "main", "spud"
    if s == "Footlong Pizza":
        return n.replace(" Pizza", " Footlong Pizza"), "main", "pizza"
    if s == "Sides":
        n = re.sub(r"\s*x\s*(\d+)$", r" (\1)", n)
        n = re.sub(r"\((\d+) [Pp]ieces\)", r"(\1)", n)
        if re.search(r"(Fries|Cheese)\s*-", n):
            n = re.sub(r"\s*-\s*", " (", n, count=1) + ")"
        return n, "side", "side"
    if s == "Protein Pots":
        return n + " Protein Pot", "main", "pot"
    if s == "Cookies":
        return n, "sweet", "cookie"
    if s == "Grab & Go":
        return n + " (Grab & Go)", "main", "sub"
    if s == "Pots":
        return n + " (side pot)", "extra", "pot"
    if s == "BREADS":
        return n + (" (6-inch)" if "Wrap" not in n else ""), "extra", "bread"
    if s in ("PROTEINS", "CHEESE", "VEGETABLES", "TOPPINGS"):
        if s in ("PROTEINS", "CHEESE"):
            n = n[:-1] + ", add-on)" if n.endswith(")") else n + " (add-on)"
        return n, "extra", "portion"
    if s == "SAUCES & CONDIMENTS":
        n = re.sub(r"\s*sauce Dip$|\s*Sauce Dip$|\s*Dip$", "", n, flags=re.I)
        n = n if "Sauce" in n or "Mayo" in n or "Ketchup" in n else n + " Sauce"
        return n + " (sub portion)", "extra", "portion"
    if s == "DUNK POTS":
        n = n.replace(" Dunk Pot", "")
        return n + " Dunk Pot", "extra", "pot"
    if s == "OTHER":
        return n, ("side" if n == "Jacket Potato" else "extra"), "portion"
    return n, "main", "serving"


def main():
    url = guide_url()
    PDF_DIR.mkdir(parents=True, exist_ok=True)
    path = PDF_DIR / "uk-sub-nutrition.pdf"
    path.write_bytes(curl(url, binary=True))
    doc = pymupdf.open(path)
    first = doc[0].get_text()
    dated = re.search(r"Nutrition Information (\w+ \d{4})", first)
    dated = dated.group(1) if dated else "undated"
    items, dropped, kj_fixed = [], [], []
    seen = {}
    table = rows(doc)
    macs = {display(sec, raw)[0]: tuple(per) for sec, raw, per, _ in table if raw.startswith("Mac & Cheese")}
    for section, raw, per, per100 in table:
        d = display(section, raw)
        if d is None:
            dropped.append(f"{raw} (Ireland only)")
            continue
        name, cat, noun = d
        grams, kj, kcal, fat, sat, carb, sugar, fibre, prot, salt = per
        est = 4 * prot + 4 * carb + 9 * fat
        if kcal >= 60 and abs(est - kcal) / kcal > 1 / 3:
            dropped.append(f"{name} ({num(kcal)} kcal, macros add up to {round(est)})")
            continue
        if name in seen:
            continue
        # A loaded-fries row carrying exactly the figures of a Mac & Cheese row is a copy slip in the guide.
        twin = next((n for n, k in macs.items() if k == tuple(per)), None) if name.startswith("Loaded") else None
        if twin:
            dropped.append(f"{name} (same figures as {twin}, a copy slip)")
            continue
        seen[name] = tuple(per)
        kj_out = kj
        if kcal >= 20 and abs(kj / 4.184 - kcal) / kcal > 0.15:
            kj_out = None  # kJ misprinted; the kcal agrees with the macros
            kj_fixed.append(name)
        if section == "Footlong Pizza":
            serve = f"whole footlong pizza ({num(grams)} g)"
        elif section == "Subs":
            serve = f'6-inch sub ({num(grams)} g)'
        else:
            serve = f"1 {'pack' if name.startswith('Mini Cookies') else noun} ({num(grams)} g)"
        row = {
            "name": name, "cat": cat, "serve": serve,
            "cal": num(kcal), "kj": num(kj_out) if kj_out is not None else None,
            "p": num(prot), "c": num(carb), "f": num(fat),
            "sat": num(sat), "sugar": num(sugar), "fibre": num(fibre),
            "sodium": None, "salt": num(salt),
            "contains": None, "may": None, "vg": None,
            "meat": ["pork", "beef"] if "Meatball" in name and "Halal" not in name else None,
        }
        if section == "Subs":
            six = dict(row, name=name + " (6-inch)")
            foot = dict(row, name=name + " (footlong)", serve=f"footlong sub ({num(grams * 2)} g)")
            for k in ("cal", "kj", "p", "c", "f", "sat", "sugar", "fibre", "salt"):
                if foot[k] is not None:
                    foot[k] = num(foot[k] * 2)
            items += [six, foot]
        else:
            items.append(row)
    today = datetime.date.today().isoformat()
    out = {
        "chain": "uk-sub",
        "name": "Subway",
        "how": "Official nutrition guide",
        "url": PAGE,
        "src": (f"Subway UK & ROI Nutrition Information, {dated} (checked {today}), per serving as listed. Subs, wraps "
                f"and toasties are bread, protein, onions, cucumbers and lettuce, with no cheese or sauce unless named; footlongs are double the 6-inch, "
                f"as Subway says. Footlong pizzas are the whole pizza. Ingredients (breads, proteins, cheese, sauces) are add-ons. "
                f"Left out {len(dropped)}: " + "; ".join(dropped) + ". "
                + (f"kJ left blank where Subway's kJ doesn't match its kcal (the kcal matches the macros): {', '.join(kj_fixed)}. " if kj_fixed else "")
                + "Subway lists allergens per ingredient, not per sub, so none are given here."),
        "checked": today,
        "energy": "cal",
        "halal": False,
        "items": items,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(items)} items, left out {len(dropped)}, kJ blanked {len(kj_fixed)}")


if __name__ == "__main__":
    main()
