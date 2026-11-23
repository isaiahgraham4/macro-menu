#!/usr/bin/env python3
"""Builds Greenstreat for Leanr from Greenstreat's own menu page.

greenstreat.com.au/menu is a Next.js page that carries the whole menu as data: every salad, warm bowl, burrito, protein plate
and smoothie with its nutrition panel, allergens ("Contains" / "May Contain") and vegan/vegetarian flags, and the same for
each build-your-own part (bases, standards, premiums, proteins, dressings). One plain request reads it.

- Meals are without dressing. Greenstreat lists each meal's recommended dressing separately, so dressings are add-ons.
- Dressings are per 30 g, the standard serve. The menu page halves that for "Light" and doubles it for "Heavy".
- Kids' meals, meal packs and party platters carry no figures, so they're left out.
- Allergens the app has no key for (celery, mustard, lentil) are dropped; the rest map to the app's keys. Parts with an empty
  allergen list stay unknown rather than allergen-free, because Greenstreat doesn't say they were checked.
- Meats come from each meal's ingredient list on the same page.
- Meal options (greenstreat-mods.json): each meal's panel is the sum of its listed parts, so taking a part off, swapping the
  protein or rice, having a burrito as a bowl (no tortilla) and the meal's own dressing light or heavy all come from the
  parts' own panels. A meal whose parts add up to more than its panel (Muscle Plate) gets none.

Usage:
    python3 ios/Scripts/greenstreat-menu.py fetch   # reads the menu page into ios/Scripts/greenstreat-source.json
    python3 ios/Scripts/greenstreat-menu.py build   # writes the rows into menu-source.js and the diet info into more-chains-diet.json
"""
import json, re, sys, time, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "greenstreat-source.json"
DIET = HERE / "more-chains-diet.json"
MODS = HERE / "greenstreat-mods.json"
MENU_SOURCE = HERE / "menu-source.js"
URL = "https://www.greenstreat.com.au/menu"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

MEALS = {"SALADS": "Salad", "WARM BOWLS": "Bowl", "BURRITOS": "Burrito", "PROTEIN PLATES": "Plate"}
# Parts sold as add-ons on a meal; bases and standards are sides, so a build-your-own can be put together.
EXTRAS = {"PROTEINS": "Add ", "PREMIUMS": "Add ", "DRESSINGS": ""}
SIDES = ("BASES", "STANDARDS")
ALLERGENS = {"Dairy": "milk", "Egg": "egg", "Soy": "soy", "Sesame": "sesame", "Peanuts": "peanut", "Tree nuts": "treenut",
             "Gluten": "gluten", "Oats": "oats", "Fish": "fish", "Crustacean": "shellfish", "Molluscs": "shellfish",
             "Sulphur Dioxide": "sulphites", "Celery": None, "Mustard": None, "Lentil": None}
MEATS = [("chicken", "chicken"), ("bacon", "pork"), ("pork", "pork"), ("brisket", "beef"), ("beef", "beef")]
SMALL = {"A", "AND", "OF", "WITH"}
# The words each meal's ingredient list uses for a part with its own panel. Each meal's panel is the sum of its parts
# (The O.G.'s add up to 1,850 kJ against 1,847), so taking one off subtracts that part's own panel exactly. Parts without a
# panel of their own (corn, corn chips, the shallot, peanut & sesame topping, pepitas, tex veg, mango) stay on.
PARTS = {"avocado": "Avocado", "smashed avo": "Avocado", "smashed avocado": "Avocado", "baby spinach": "Baby Spinach",
         "bean shoots": "Bean Shoots", "black beans": "Black Beans", "broccoli": "Broccoli", "cheddar cheese": "Cheddar Cheese",
         "cherry tomatoes": "Cherry Tomatoes", "chopped cos": "Chopped Cos", "cos lettuce": "Chopped Cos", "coriander": "Coriander",
         "cracked pepper": "Cracked Pepper", "cucumber": "Cucumber", "edamame": "Edamame", "kale mix": "Kale Mix",
         "lime wedge": "Lime Wedge", "mixed leaf": "Mixed Leaf", "parsley": "Parsley", "rainbow slaw": "Rainbow Slaw",
         "raw slaw": "Raw Slaw", "red onion": "Red Onion", "rocket": "Rocket", "spicy broccoli": "Spicy Broccoli",
         "spring onions": "Spring Onion", "vermicelli noodles": "Vermicelli Noodles", "jalapenos": "Jalapenos",
         "boiled egg": "Boiled Egg", "free range boiled egg": "Boiled Egg", "brown rice": "Warm Brown Rice",
         "warm brown rice": "Warm Brown Rice", "white rice": "Warm White Rice", "warm white rice": "Warm White Rice",
         "crispy bacon": "Crispy Bacon", "feta": "Crumbled Feta", "crumbled feta": "Crumbled Feta", "house pickles": "Pickles",
         "parmesan": "Shaved Parmesan", "parmesan crisps": "Parmi Crisps", "sweet potato": "Roasted Sweet Potato",
         "roasted sweet potato": "Roasted Sweet Potato", "sour cream": "Sour Cream", "sour-cream": "Sour Cream",
         "tomato & onion": "Tomato & Onion", "toasted almonds": "Toasted Almonds", "warm shrooms": "Warm Shrooms",
         "slow cooked beef brisket": "Slow Cooked Beef Brisket", "slow-cooked pulled pork": "Slow Cooked Pulled Pork",
         "warm blackened chicken": "Blackened Chicken", "warm roasted chicken": "Warm Roasted Chicken",
         "roasted tofu": "Marinated Tofu", "warm roasted tofu": "Marinated Tofu", "plant-based chilli": "Slow Cooked Plant Based Chilli"}
# The protein a meal is built on, which can be swapped for another. Satay Plant Power Plate is Chicken Satay Power Plate on
# tofu, and the two differ by exactly the chicken and tofu panels, so "roasted tofu" is the marinated tofu panel.
PROTEINS = ["Warm Roasted Chicken", "Blackened Chicken", "Marinated Tofu", "Slow Cooked Pulled Pork", "Slow Cooked Beef Brisket",
            "Slow Cooked Plant Based Chilli"]
SHORT = {"Warm Roasted Chicken": "Roasted Chicken", "Marinated Tofu": "Tofu", "Slow Cooked Pulled Pork": "Pulled Pork",
         "Slow Cooked Beef Brisket": "Beef Brisket", "Slow Cooked Plant Based Chilli": "Plant-Based Chilli",
         "Warm Brown Rice": "Brown Rice", "Warm White Rice": "White Rice", "Slow Cooked Plant Based Chilli": "Plant-Based Chilli"}


def read_items():
    """Every item the menu page carries, as Greenstreat's own data (menu-watch.py reads this too)."""
    req = urllib.request.Request(URL, headers={"User-Agent": UA})
    page = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', page, flags=re.S)
    flight = "".join(json.loads('"' + c + '"') for c in chunks)
    items, starts = [], set()
    for m in re.finditer(r'"supyCode"', flight):
        i, depth = m.start(), 0
        while i > 0:
            i -= 1
            if flight[i] == "}":
                depth += 1
            elif flight[i] == "{":
                if depth == 0:
                    break
                depth -= 1
        if i in starts:
            continue
        starts.add(i)
        j, depth = i, 0
        while j < len(flight):
            depth += {"{": 1, "}": -1}.get(flight[j], 0)
            if depth == 0:
                break
            j += 1
        items.append(json.loads(flight[i:j + 1]))
    if len(items) < 60:
        raise RuntimeError(f"only {len(items)} items on {URL}; the page has changed")
    return items


def fetch():
    items = read_items()
    SOURCE.write_text(json.dumps({"fetched": time.strftime("%Y-%m-%d"), "items": items}, indent=1, ensure_ascii=False) + "\n")
    print(f"Saved {len(items)} items")


def num(x):
    if x in (None, ""):
        return None
    x = float(x)
    return int(x) if x.is_integer() else round(x, 1)


def title(name):
    words = re.sub(r"\s+", " ", name.strip()).split(" ")
    out = []
    for i, w in enumerate(words):
        if re.fullmatch(r"[A-Z0-9.&+',]+", w) and re.search(r"[A-Z]", w):
            w = "O.G." if w == "O.G." else (w.lower() if i and w in SMALL else w.capitalize())
        out.append(w)
    return " ".join(out)


def panel(item):
    n = item.get("nutritional") or {}
    get = lambda *keys: next((num(n[k]) for k in keys if n.get(k) not in (None, "")), None)
    kj, p, c, f = get("Kilojoules (kJ)"), get("Protein (g)"), get("Carbohydrates (g)"), get("Total Fat (g)")
    nut = {"sat": get("Saturated Fat (g)"), "sugar": get("Sugars (g)", "Sugar (g)"), "fibre": get("Dietary Fibre (g)", "Fibre (g)"),
           "sodium": get("Sodium (mg)")}
    return kj, p, c, f, {k: v for k, v in nut.items() if v is not None}, get("Quantity (g)")


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower())   # as menu-source.js makes item IDs


def option(kind, name, part, times, meal_nut):
    """One change to a meal: `times` of a part's panel (negative to take it off). Nutrients the meal itself doesn't list
    are left out, so a change can't give the meal a figure Greenstreat doesn't publish for it."""
    kj, p, c, f, nut, _ = part
    r = lambda x: None if x is None else (lambda v: int(v) if float(v).is_integer() else v)(round(x * times, 1))
    tag = {"r": "no", "s": "swap", "a": "extra"}[kind]
    what = slug(re.sub(r"^(No|Swap to|Add) ", "", name)).strip("-")
    out = {"key": f"{kind}:{what}", "id": f"{tag}-{what}", "kind": kind, "name": name,
           "kj": round(kj * times), "p": r(p), "c": r(c or 0), "f": r(f or 0)}
    n = {k: r(v) for k, v in nut.items() if k in meal_nut}
    if n:
        out["nut"] = n
    return out


def combine(kind, name, plus, minus, meal_nut):
    a, b = option(kind, name, plus, 1, meal_nut), option(kind, name, minus, -1, meal_nut)
    out = dict(a)
    out["kj"] = a["kj"] + b["kj"]
    for k in ("p", "c", "f"):
        out[k] = round(a[k] + b[k], 1)
        out[k] = int(out[k]) if float(out[k]).is_integer() else out[k]
    n = {k: round(a.get("nut", {}).get(k, 0) + b.get("nut", {}).get(k, 0), 1) for k in set(a.get("nut", {})) | set(b.get("nut", {}))}
    if n:
        out["nut"] = {k: int(v) if float(v).is_integer() else v for k, v in sorted(n.items())}
    return out


def meal_options(items, names, rows):
    """{food id: [changes]} for every meal: take a part off, swap the protein or the rice, have a burrito as a bowl, and
    the meal's own dressing light (half) or heavy (double), as Greenstreat's menu page works them out."""
    parts, twice = {}, set()
    for item, name in zip(items, names):
        cat = (item.get("category") or "").strip().upper()
        if cat in SIDES or cat in EXTRAS:
            if name in parts and not (name == "Lime Wedge" and cat == "DRESSINGS"):
                if parts[name][1] != cat and name == "Lime Wedge":
                    continue
                twice.add(name)
            if not (name == "Lime Wedge" and cat == "DRESSINGS"):
                parts.setdefault(name, (panel(item), cat))
    parts = {k: v[0] for k, v in parts.items() if k not in twice}
    dressings = {re.sub(r"[^a-z]", "", n.lower()): n for item, n in zip(items, names) if item.get("category") == "DRESSINGS"}
    by_name = {r[0]: r for r in rows}
    out, report = {}, []
    for item, title_name in zip(items, names):
        cat = (item.get("category") or "").strip().upper()
        if cat not in MEALS:
            continue
        name = title_name if MEALS[cat].lower() in title_name.lower() else f"{title_name} {MEALS[cat]}"
        if name not in by_name:
            continue
        row = by_name[name]
        meal_nut = row[7]
        # The recommended dressing is the last dressing the description names ("... rainbow slaw + thai streat
        # vinaigrette"); it isn't in the meal's panel. Dressing names aren't parts, so the list below skips them.
        desc = item.get("description") or ""
        flat = re.sub(r"[^a-z]", "", desc.lower())
        named = [(flat.rfind(k), n) for k, n in dressings.items() if k in flat]
        own = max(named)[1] if named else None
        desc = re.sub(r"\(.*?\)", "", desc.lower()).replace("tomato + onion mix", "tomato & onion").replace("tomato + onion", "tomato & onion")
        phrases = [re.sub(r"\s+", " ", x).strip() for x in re.split(r",|\s\+\s|\+(?=[a-z])", desc)]
        mods, found, total = [], [], 0
        double = None
        for phrase in phrases:
            if phrase.startswith("double "):
                double = PARTS.get(phrase[7:])
                if double in parts:
                    total += 2 * parts[double][0]
                continue
            part = PARTS.get(phrase)
            if part in parts and part not in found:
                found.append(part)
                total += parts[part][0]
        if cat == "BURRITOS":
            total += parts["Tortilla"][0]
            mods.append(option("r", "No Tortilla (as a bowl)", parts["Tortilla"], -1, meal_nut))
        for part in found:
            mods.append(option("r", f"No {SHORT.get(part, part)}", parts[part], -1, meal_nut))
        if double:
            mods.append(option("r", f"Single {SHORT.get(double, double)}", parts[double], -1, meal_nut))
        mine = [p for p in found if p in PROTEINS]
        if len(mine) == 1 and not double:
            for other in PROTEINS:
                if other != mine[0]:
                    mods.append(combine("s", f"Swap to {SHORT.get(other, other)}", parts[other], parts[mine[0]], meal_nut))
        for have, other in (("Warm White Rice", "Warm Brown Rice"), ("Warm Brown Rice", "Warm White Rice")):
            if have in found:
                mods.append(combine("s", f"Swap to {SHORT[other]}", parts[other], parts[have], meal_nut))
        if own:
            mods.append(option("a", f"Add {own} (light, 15 g)", parts[own], 0.5, meal_nut))
            mods.append(option("a", f"Add {own} (heavy, 60 g)", parts[own], 2, meal_nut))
        # Parts that add up to more than the meal mean it's made with smaller portions of them (Muscle Plate), so
        # their panels don't say what taking one off saves.
        if total > row[2] * 1.05:
            report.append(f"{name}: parts {total} kJ are more than the meal's {row[2]} kJ, so no options")
            continue
        report.append(f"{name}: parts {total} of {row[2]} kJ, {len(mods)} options")
        out["greenstreat:" + slug(name)] = mods
    for line in report:
        print("  " + line)
    return out


def build():
    source = json.loads(SOURCE.read_text())
    rows, diet, seen, left = [], {}, {}, []
    names = [title(x["name"]) for x in source["items"]]
    for item, name in zip(source["items"], names):
        cat_src = (item.get("category") or "").strip().upper()
        kj, p, c, f, nut, grams = panel(item)
        if kj is None or p is None:
            continue
        if cat_src in MEALS:
            word = MEALS[cat_src]
            if word.lower() not in name.lower():
                name = f"{name} {word}"
            cat, serve = "main", f"{grams} g, without dressing" if grams else "without dressing"
        elif cat_src == "SMOOTHIES":
            cat, serve = "drink", "1 smoothie"
        elif cat_src in EXTRAS:
            if cat_src == "DRESSINGS" and name == "Lime Wedge":
                continue
            name = EXTRAS[cat_src] + name
            cat, serve = "extra", (f"{grams} g, standard serve" if cat_src == "DRESSINGS" else f"{grams} g") if grams else "one serve"
        elif cat_src in SIDES:
            cat, serve = "side", f"{grams} g" if grams else "one serve"
        else:
            continue
        # Two standards share a name with different panels (CORN, and SHALLOTS, PEANUTS & SESAME SEEDS); which is which
        # isn't said, so both are left out.
        twins = [x for x in source["items"] if title(x["name"]) == title(item["name"]) and x.get("category") == item.get("category")]
        if len(twins) > 1:
            left.append(f"{name} (two different panels under one name)")
            continue
        # A panel whose energy is more than a third away from its macros is a misprint. Under 200 kJ the whole-gram
        # rounding alone can do that, so small parts aren't checked.
        made = 17 * p + 17 * (c or 0) + 37 * (f or 0)
        if max(kj, made) >= 200 and abs(kj - made) / max(kj, made) > 1 / 3:
            left.append(f"{name} ({kj} kJ vs {round(made)} from macros)")
            continue
        if name in seen:
            continue
        seen[name] = True
        rows.append([name, cat, kj, p, c, f, serve, nut])
        fid = "greenstreat:" + re.sub(r"[^a-z0-9]+", "-", name.lower())
        info = {}
        allergens = item.get("allergens") or {}
        if allergens:
            al = sorted({ALLERGENS[k] for k, v in allergens.items() if v == "Contains" and ALLERGENS.get(k)})
            may = sorted({ALLERGENS[k] for k, v in allergens.items() if v == "May Contain" and ALLERGENS.get(k)} - set(al))
            missing = set(allergens) - set(ALLERGENS)
            if missing:
                sys.exit(f"{name}: allergen names not mapped: {missing}")
            info["al"] = al
            if may:
                info["may"] = may
        dietary = item.get("dietary") or {}
        text = f"{item['name']} {(item.get('description') or '').split(chr(10) + '+')[0]}".lower()
        if cat_src in MEALS or cat_src in ("PROTEINS", "PREMIUMS", "SMOOTHIES"):
            info["meat"] = sorted({m for word, m in MEATS if word in text})
        elif cat_src in SIDES:
            info["meat"] = []   # rice, leaves, vegetables, seeds and the tortilla
        if dietary.get("Vegan"):
            info["vg"] = "vegan"
        elif dietary.get("Vegetarian"):
            info["vg"] = "vegetarian"
        if info.get("vg") and info.get("meat"):
            sys.exit(f"{name}: labelled {info['vg']} but lists {info['meat']}")
        if info:
            info["src"] = "name" if cat_src in SIDES else "description" if "meat" in info else "labels"
            diet[fid] = info

    mods = meal_options(source["items"], names, rows)
    MODS.write_text(json.dumps({"fetched": source["fetched"], "modifiers": mods}, indent=1, ensure_ascii=False) + "\n")

    def js(row):
        name, cat, kj, p, c, f, serve, nut = row
        return "    " + json.dumps([name, cat, kj, p, c, f, serve] + ([nut] if nut else []), ensure_ascii=False)
    order = {"main": 0, "drink": 1, "side": 2, "extra": 3}
    rows.sort(key=lambda r: order[r[1]])
    block = "  greenstreat:[\n" + ",\n".join(js(r) for r in rows) + "\n  ],\n"
    text = MENU_SOURCE.read_text()
    if "  greenstreat:[" in text:
        text = re.sub(r"  greenstreat:\[\n.*?\n  \],\n", lambda _: block, text, count=1, flags=re.S)
    else:
        text = re.sub(r"(  thisbowl:\[\n.*?\n  \],\n)", lambda m: m.group(1) + block, text, count=1, flags=re.S)
    MENU_SOURCE.write_text(text)

    data = json.loads(DIET.read_text())
    data["items"] = {k: v for k, v in data["items"].items() if not k.startswith("greenstreat:")} | diet
    DIET.write_text(json.dumps(data, indent=0, ensure_ascii=False))
    print(f"Wrote {len(rows)} Greenstreat items, {sum(len(v) for v in mods.values())} meal options and diet info for {len(diet)}")
    for x in left:
        print("  left out:", x)


if __name__ == "__main__":
    {"fetch": fetch, "build": build}.get(sys.argv[1] if len(sys.argv) > 1 else "", lambda: sys.exit(__doc__))()
