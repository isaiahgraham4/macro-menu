#!/usr/bin/env python3
"""Costa Coffee (UK): every drink and food item on costa.co.uk/menu, with Costa's own nutrition and allergens.

The menu page is an Astro page; its one <astro-island> (MenuPage) carries the whole catalogue in its props attribute,
Astro-serialised ([0, value] for values, [1, [...]] for arrays). Each product lists a nutrition record per variation
(size, milk, coffee blend, eat in / takeaway, topping), each with per-portion figures, allergens and dietary flags.
For drinks this keeps Costa's default milk, blend and topping, takeaway, one row per size. Writes uk-costa-source.json.
"""
import datetime
import gzip
import html
import json
import re
import time
import urllib.request
from pathlib import Path

URL = "https://www.costa.co.uk/menu"
OUT = Path(__file__).with_name("uk-costa-source.json")
HEADERS = {
    # costa.co.uk only answers requests that look like a browser navigation.
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-GB,en;q=0.9",
    "Sec-Fetch-Mode": "navigate", "Sec-Fetch-Dest": "document", "Sec-Fetch-Site": "none",
    "Upgrade-Insecure-Requests": "1",
}
ORDER = ["gluten", "wheat", "milk", "egg", "soy", "sesame", "peanut", "treenut", "fish", "shellfish", "lupin", "sulphites"]
EMPTY = (None, "NA", "None")
SIZES = {"Small": 0, "Medium": 1, "Large": 2, "Single": 0, "Double": 1}


def get():
    req = urllib.request.Request(URL, headers=dict(HEADERS, **{"Accept-Encoding": "gzip"}))
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                body = r.read()
                if r.headers.get("Content-Encoding") == "gzip":
                    body = gzip.decompress(body)
                return body.decode("utf-8")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(5)


def astro(v):
    if isinstance(v, list) and len(v) == 2 and isinstance(v[0], int):
        t, x = v
        if t == 1:
            return [astro(y) for y in x]
        if t == 0 and isinstance(x, dict):
            return {k: astro(y) for k, y in x.items()}
        return x
    if isinstance(v, dict):
        return {k: astro(y) for k, y in v.items()}
    return v


def catalogue(page):
    m = re.search(r'<astro-island[^>]*component-url="[^"]*MenuPage[^"]*"[^>]*>', page) or re.search(r"<astro-island[^>]*>", page)
    props = re.search(r'props="([^"]*)"', m.group(0)).group(1)
    data = {k: astro(v) for k, v in json.loads(html.unescape(props)).items()}
    return data["catalog"]


def allergens(a):
    yes, may = set(), set()

    def put(state, keys):
        if state == "Yes":
            yes.update(keys)
        elif state and state != "No":
            may.update(keys)

    cereals = a.get("cereals") or {}
    put(cereals.get("wheat"), ["gluten", "wheat"])
    for k in ("rye", "barley", "oat", "spelt"):
        put(cereals.get(k), ["gluten"])
    for key, out in (("milk", "milk"), ("egg", "egg"), ("soya", "soy"), ("sesame", "sesame"), ("peanut", "peanut"),
                     ("treeNuts", "treenut"), ("fish", "fish"), ("crustacean", "shellfish"), ("mollusc", "shellfish"),
                     ("lupin", "lupin"), ("sulphite", "sulphites")):
        put(a.get(key), [out])
    return [k for k in ORDER if k in yes], [k for k in ORDER if k in may - yes]


def num(v):
    if v is None:
        return None
    return int(v) if float(v).is_integer() else round(float(v), 2)


def pick(records, field, prefer):
    """Narrow records to the first preferred value of one variation field that some record has."""
    for want in prefer:
        hit = [r for r in records if r["variations"].get(field) in (want if isinstance(want, tuple) else (want,))]
        if hit:
            return hit
    return records


def clean_name(n):
    n = re.sub(r"[®™]", "", n).replace("\u2019", "'")
    n = re.sub(r"\s*\(V\)$", "", n.strip())
    return re.sub(r"\s+", " ", n).strip()


def food_cat(section, name):
    if section == "Breakfast":
        return "breakfast"
    if section == "Lunch":
        return "main"
    if section == "Pastries & Sweets":
        if re.search(r"cheese twist|cheddar", name, re.I):
            return "side"
        return "breakfast" if re.search(r"croissant|pain au|porridge|bircher|granola", name, re.I) else "sweet"
    if section == "Snacks":
        return "sweet" if re.search(r"choc|cookie|biscuit|brownie|flapjack|shortbread|cake|bar\b|caramel|bites|tiffin|millionaire|tart|mince|waffle|mochi", name, re.I) else "side"
    return "main"


def main():
    cat = catalogue(get())
    items, dropped = [], []
    seen = set()
    for section in cat["drinks"]:
        for p in section.get("products") or []:
            name = clean_name(p["name"])
            recs = [r for r in p.get("nutrition") or [] if r.get("nutritionPerPortion")]
            if not recs:
                dropped.append(f"{name} (no figures)")
                continue
            d = {v["categoryName"]: v["defaultValue"] for v in p.get("allowedVariations") or []}
            recs = pick(recs, "milkType", [d.get("Milk Choices"), "Semi-skimmed", "Whole", EMPTY])
            recs = pick(recs, "coffeeType", [d.get("Coffee Choices"), "Signature", EMPTY, "Smooth Medium Roast"])
            recs = pick(recs, "topping", [d.get("Toppings"), EMPTY])
            recs = pick(recs, "serviceDelivery", ["Takeaway", "Eat In", EMPTY])
            by_size = {}
            for r in recs:
                by_size.setdefault(r["variations"].get("size"), r)
            if any(k not in EMPTY for k in by_size):
                by_size = {k: v for k, v in by_size.items() if k not in EMPTY}
            sizes = sorted(by_size, key=lambda s: SIZES.get(s, 9))
            for size in sizes:
                r = by_size[size]
                n = r["nutritionPerPortion"]
                v = r["variations"]
                label = name + (f" ({size.lower()})" if len(sizes) > 1 and size not in EMPTY else "")
                kcal, prot, carb, fat = n.get("energykCal"), n.get("protein"), n.get("carbohydrates"), n.get("fat")
                if None in (kcal, prot, carb, fat):
                    dropped.append(f"{label} (no figures)")
                    continue
                est = 4 * prot + 4 * carb + 9 * fat
                if kcal >= 60 and abs(est - kcal) / kcal > 1 / 3:
                    dropped.append(f"{label} ({kcal} kcal, macros add up to {round(est)})")
                    continue
                if label.lower() in seen:
                    continue
                seen.add(label.lower())
                bits = []
                if size not in EMPTY:
                    bits.append(size.lower())
                if v.get("serviceDelivery") not in EMPTY:
                    bits.append(v["serviceDelivery"].lower())
                if v.get("milkType") not in EMPTY:
                    bits.append(f"{v['milkType'].lower()} milk")
                if v.get("topping") not in EMPTY:
                    bits.append(v["topping"].lower())
                vol = n.get("portionVolume")
                serve = ", ".join(bits) or "1 drink"
                if vol:
                    serve += f" ({num(vol)} ml)"
                contains, may = allergens(r.get("allergens") or {}) if r.get("allergens") else (None, None)
                dc = r.get("dietaryChoices") or {}
                items.append({
                    "name": label, "cat": "drink", "serve": serve,
                    "cal": num(kcal), "kj": num(n.get("energykJ")),
                    "p": num(prot), "c": num(carb), "f": num(fat),
                    "sat": num(n.get("saturates")), "sugar": num(n.get("sugars")), "fibre": num(n.get("fibre")),
                    "sodium": None, "salt": num(n.get("salt")),
                    "contains": contains if contains is not None else [], "may": may if may is not None else [],
                    "vg": "vegan" if dc.get("suitableForVegans") == "Yes" else ("vegetarian" if dc.get("suitableForVegetarians") == "Yes" else None),
                    "meat": None,
                })
    for section in cat["food"]:
        for p in section.get("products") or []:
            name = clean_name(p["name"])
            recs = [r for r in p.get("nutrition") or [] if r.get("nutritionPerPortion")]
            if not recs:
                dropped.append(f"{name} (no figures)")
                continue
            r = recs[0]
            n = r["nutritionPerPortion"]
            kcal, prot, carb, fat = n.get("energykCal"), n.get("protein"), n.get("carbohydrates"), n.get("fat")
            if None in (kcal, prot, carb, fat):
                dropped.append(f"{name} (no figures)")
                continue
            est = 4 * prot + 4 * carb + 9 * fat
            if kcal >= 60 and abs(est - kcal) / kcal > 1 / 3:
                dropped.append(f"{name} ({kcal} kcal, macros add up to {round(est)})")
                continue
            if name.lower() in seen:
                continue
            seen.add(name.lower())
            contains, may = allergens(r.get("allergens") or {})
            dc = r.get("dietaryChoices") or {}
            w = n.get("portionWeight")
            items.append({
                "name": name, "cat": food_cat(section["name"], name),
                "serve": f"1 serving ({num(w)} g)" if w else "1 serving",
                "cal": num(kcal), "kj": num(n.get("energykJ")),
                "p": num(prot), "c": num(carb), "f": num(fat),
                "sat": num(n.get("saturates")), "sugar": num(n.get("sugars")), "fibre": num(n.get("fibre")),
                "sodium": None, "salt": num(n.get("salt")),
                "contains": contains, "may": may,
                "vg": "vegan" if dc.get("suitableForVegans") == "Yes" else ("vegetarian" if dc.get("suitableForVegetarians") == "Yes" else None),
                "meat": None,
            })
    if len(items) < 80:
        raise SystemExit(f"Only {len(items)} Costa items; the menu page may have changed")
    today = datetime.date.today().isoformat()
    out = {
        "chain": "uk-costa",
        "name": "Costa Coffee",
        "how": "Official online menu",
        "url": URL,
        "src": (f"costa.co.uk menu nutrition and allergens ({today}). Drinks are takeaway, one row per size, with Costa's "
                f"default milk (semi-skimmed for most), blend and topping, as named in each serve. Left out {len(dropped)}: "
                + "; ".join(dropped) + ". 'May' is Costa's cross-contamination risk."),
        "checked": today,
        "energy": "cal",
        "halal": False,
        "items": items,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(items)} items, left out {len(dropped)}")


if __name__ == "__main__":
    main()
