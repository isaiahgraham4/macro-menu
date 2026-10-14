#!/usr/bin/env python3
"""Builds Grill'd for Leanr from Grill'd's own ordering app data.

Grill'd's ordering app (api.digital.grilld.com.au, the same data the Grill'd app shows) has a full nutrition panel for every
burger on every bun, and for its salads, tenders, chips, dips and kids' meals. It doesn't change the figures when a burger is
customised, and it lists no figures for single ingredients, so the only customisations here are ones Grill'd's published
panels give exactly:

- Bun swaps: the same burger on another bun, or with no bun, is published, so the difference is exact for that burger.
- Patty swaps: burgers published with the same toppings on different patties (the Dynamic beef, chicken and veggie burgers,
  Mustard & Pickled! on beef and Beyond, Garden Goodness on its own patty and Beyond).
- Bacon & cheese, egg & beetroot, and lettuce, carrot & egg mayo: the differences between Simply Grill'd, Crispy Bacon &
  Cheese and the Mighty Melbourne, and between the Beef Dynamic and the Dynamic Beef Cheeseburger.

One kind is an estimate, marked est: taking off herbed mayo, sweet chilli mayo, chipotle mayo or tomato relish. Grill'd sells
those as dips with full per-100 g figures, but doesn't say how much goes on a burger, so SAUCE_GRAMS of it is assumed.

Usage:
    python3 ios/Scripts/grilld-menu.py fetch   # downloads the menu into ios/Scripts/grilld-source.json (about 85 requests)
    python3 ios/Scripts/grilld-menu.py build   # writes the menu rows into menu-source.js and the options into grilld-mods.json
"""
import json, re, sys, time, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "grilld-source.json"
MODS = HERE / "grilld-mods.json"
MENU_SOURCE = HERE / "menu-source.js"
API = "https://api.digital.grilld.com.au/v1"
STORE = 153            # Grill'd Melbourne Emporium; the menu and its nutrition are national
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"


def get(path):
    out = subprocess.run(["curl", "-sf", "-A", UA, "-H", "Accept: application/json", "-H", "platform: web", "-m", "30", API + path],
                         capture_output=True, check=True).stdout
    return json.loads(out)


def trim(product):
    """Only what the build reads: names, nutrition panels, bun choices and what can be taken off."""
    def item(x):
        return {"id": x["id"], "title": x["title"], "nutrition": {"tableRows": x["nutrition"]["tableRows"]}}
    # The ingredient list as sold (the default bun's, when it has buns), for Leanr's dietary filters (diet-info.py).
    texts = [x["nutrition"].get("ingredients") for x in [product] + [i for c in product.get("choices", []) for i in c["items"]]]
    return {**item(product), "choices": [{"title": c["title"], "items": [item(i) for i in c["items"]]} for c in product.get("choices", [])],
            "subtractions": [{"title": s["title"]} for s in product.get("subtractions", [])],
            "ingredients": next((t for t in texts if t), None), "attributes": product.get("attributes") or []}


def fetch():
    menu = get(f"/restaurants/{STORE}/menu?orderType=Pickup")
    products = {}
    for category in menu["categories"]:
        if category["title"] == "Drinks":
            continue
        for item in category["items"]:
            if item["id"] in products:
                continue
            products[item["id"]] = {"category": category["title"], "product": trim(get(f"/restaurants/{STORE}/menu/{item['id']}?orderType=Pickup"))}
            time.sleep(0.4)
    SOURCE.write_text(json.dumps({"fetched": time.strftime("%Y-%m-%d"), "store": STORE, "products": products}, indent=1))
    print(f"Saved {len(products)} Grill'd products")


ROWS = {"Energy": "kj", "Protein": "p", "Total fat": "f", "Saturated fat": "sat", "Carbohydrate": "c", "Sugars": "sugar",
        "Dietary fibre": "fibre", "Sodium": "sodium"}


def number(text):
    match = re.match(r"\s*([\d.]+)", (text or "").replace(",", ""))
    return float(match.group(1)) if match else None


def panel(item):
    """Per serve, and the serving weight worked out from the per-100 g column."""
    rows = item["nutrition"]["tableRows"]
    if not rows:
        return None
    serve, per100 = {}, {}
    for row in rows[1:]:
        key = ROWS.get(row[0].strip().lstrip("-– ").strip())
        if key:
            serve[key], per100[key] = number(row[1]), number(row[3])
    if not serve.get("kj") or serve.get("p") is None:
        return None
    grams = round(serve["kj"] / per100["kj"] * 100) if per100.get("kj") else None
    return serve, grams


def per_gram(item):
    """A panel's per-100 g column, per gram."""
    rows = item["nutrition"]["tableRows"]
    out = {}
    for row in rows[1:]:
        key = ROWS.get(row[0].strip().lstrip("-– ").strip())
        if key and number(row[3]) is not None:
            out[key] = number(row[3]) / 100
    return out


def clean_name(title):
    name = title.strip().strip("'").replace("‘", "").replace("’", "'")
    name = re.sub(r"^New ", "", name).replace(" with Water", "")
    return name.replace("'Simon Says'", "Simon Says").replace("'Baa Baa'", "Baa Baa")


def slug(name):
    # The same as menu-source.js uses for item IDs.
    return re.sub(r"[^a-z0-9]+", "-", name.lower())


def r1(x):
    return None if x is None else round(x, 1)


def diff(a, b):
    """b − a, nutrient by nutrient."""
    return {k: round(b[k] - a[k], 1) for k in ("kj", "p", "c", "f", "sat", "sugar", "fibre", "sodium") if a.get(k) is not None and b.get(k) is not None}


def modifier(key, kind, name, amounts):
    nut = {k: amounts[k] for k in ("sat", "sugar", "fibre", "sodium") if k in amounts}
    return {"key": key, "id": slug(name).strip("-"), "kind": kind, "name": name, "kj": round(amounts["kj"]),
            "p": amounts["p"], "c": amounts["c"], "f": amounts["f"], "nut": nut, "price": 0}


def negate(amounts):
    return {k: -v for k, v in amounts.items()}


CATEGORY = {"Chips & Onion Rings": "side", "Dips": "extra"}
SKIP_CATEGORIES = {"Build Your Own", "Drinks"}
# How much of one sauce is taken to be on a burger, for the estimated sauce removals. A Grill'd dip pot is 35 g.
SAUCE_GRAMS = 15

BUNS = {"Panini": "Panini bun", "Traditional": "Traditional bun", "Charcoal Bun": "Charcoal bun", "SuperBun": "SuperBun",
        "Gluten Free": "Gluten free bun", "No Bun": "No bun", "Mini Bun": "Mini bun"}


def build():
    source = json.loads(SOURCE.read_text())
    rows, mods, burgers, others, product_of = [], {}, {}, {}, {}
    for pid, entry in source["products"].items():
        category, product = entry["category"], entry["product"]
        title = product["title"]
        # Meal packs come with chips, a dip and a drink that their panel doesn't cover; the burger is there on its own.
        if category in SKIP_CATEGORIES or re.search(r"(Chicken|Wagyu) Pack$", title) or "with Juice" in title:
            continue
        cat = CATEGORY.get(category, "main")
        buns = [item for choice in product.get("choices", []) for item in choice["items"] if item["title"] in BUNS and panel(item)]
        if category == "Sliders":
            for item in product["choices"][0]["items"]:
                found = panel(item)
                if found and f"{item['title']} Slider" not in {r[0] for r in rows}:
                    serve, grams = found
                    rows.append([f"{item['title']} Slider", "main", serve, f"1 slider{f' · {grams} g' if grams else ''}"])
            continue
        if buns:
            default = buns[0]
            serve, grams = panel(default)
            name = clean_name(title)
            # A kids' pack weighs in its drink too, so only the bun is shown.
            weight = f" · {grams} g" if grams and "Mini Me" not in name else ""
            rows.append([name, cat, serve, f"{BUNS[default['title']]}{weight}"])
            product_of[f"grilld:{slug(name)}"] = pid
            subs = [s["title"][3:] for s in product.get("subtractions", [])]
            by_bun = {item["title"]: panel(item)[0] for item in buns}
            burgers[name] = {"subs": subs, "buns": by_bun, "default": default["title"]}
            options = []
            for bun, values in by_bun.items():
                if bun == default["title"]:
                    continue
                label = "No Bun" if bun == "No Bun" else f"{BUNS[bun].replace(' bun', '').title()} Bun" if bun != "SuperBun" else "SuperBun"
                options.append(modifier(f"s:bun-{slug(bun).strip('-')}", "s", label if bun == "No Bun" else f"Swap to {label}", diff(serve, values)))
            mods[f"grilld:{slug(name)}"] = options
        else:
            found = panel(product)
            if not found:
                continue
            serve, grams = found
            rows.append([clean_name(title), cat, serve, f"{grams} g" if grams else "1 serving"])
            product_of[f"grilld:{slug(clean_name(title))}"] = pid
            if product.get("subtractions"):
                others[clean_name(title)] = [s["title"][3:] for s in product["subtractions"]]

    # Exact differences between burgers published with the same toppings, measured without the bun.
    def no_bun(name):
        return burgers[name]["buns"]["No Bun"]
    patty_of = {"Beef Patty": "Beef", "Chicken Breast": "Chicken Breast", "Garden Patty": "Garden Goodness Patty", "Beyond Patty": "Beyond Patty"}
    patty = {  # each patty relative to beef
        "Beef Patty": {k: 0.0 for k in no_bun("Beef Dynamic")},
        "Chicken Breast": diff(no_bun("Beef Dynamic"), no_bun("Chicken Dynamic")),
        "Garden Patty": diff(no_bun("Beef Dynamic"), no_bun("Veggie Dynamic")),
        "Beyond Patty": diff(no_bun("Mustard & Pickled!"), no_bun("Beyond Mustard & Pickled!")),
    }
    # Garden Goodness and Beyond Garden Goodness check the two routes to the Beyond patty agree.
    check = diff(no_bun("Garden Goodness"), no_bun("Beyond Garden Goodness"))
    via_beef = {k: round(patty["Beyond Patty"][k] - patty["Garden Patty"][k], 1) for k in check}
    if abs(check["kj"] - via_beef["kj"]) > 150:
        raise SystemExit(f"Patty differences disagree: {check['kj']} vs {via_beef['kj']} kJ")
    bacon_cheese = diff(no_bun("Simply Grill'd"), no_bun("Crispy Bacon & Cheese"))
    egg_beetroot = diff(no_bun("Crispy Bacon & Cheese"), no_bun("Mighty Melbourne"))
    salad_mayo = diff(no_bun("Dynamic Beef Cheeseburger"), no_bun("Beef Dynamic"))
    for amounts in (bacon_cheese, egg_beetroot, salad_mayo):
        if amounts["kj"] <= 0 or amounts["p"] < 0 or amounts["f"] < 0:
            raise SystemExit(f"A published difference doesn't add up: {amounts}")

    for name, burger in burgers.items():
        options = mods[f"grilld:{slug(name)}"]
        subs = set(burger["subs"])
        own = next((p for p in patty if p in subs), None)
        if own:
            for other, label in patty_of.items():
                if other == own or name.startswith("Vegan") and other in ("Beef Patty", "Chicken Breast"):
                    continue
                amounts = {k: round(patty[other][k] - patty[own][k], 1) for k in patty[own] if k in patty[other]}
                options.append(modifier(f"s:patty-{slug(other).strip('-')}", "s", f"Swap to {label}", amounts))
        if {"Crispy Bacon", "Tasty Cheese"} <= subs:
            options.append(modifier("r:bacon-cheese", "r", "No Bacon & Cheese", negate(bacon_cheese)))
        elif not subs & {"Crispy Bacon", "Tasty Cheese", "Aged Cheddar", "Brie Cheese", "Goats Cheese", "Vegan Cheese"} and not name.startswith(("Vegan", "Beyond", "Garden")):
            options.append(modifier("a:bacon-cheese", "a", "Add Bacon & Cheese", bacon_cheese))
        if {"Free Range Egg", "Beetroot"} <= subs:
            options.append(modifier("r:egg-beetroot", "r", "No Egg & Beetroot", negate(egg_beetroot)))
        elif name in ("Simply Grill'd", "Crispy Bacon & Cheese"):
            options.append(modifier("a:egg-beetroot", "a", "Add Egg & Beetroot", egg_beetroot))
        if {"Cos Lettuce", "Carrot", "Egg Mayo"} <= subs and "Dynamic" in name:
            options.append(modifier("r:salad-mayo", "r", "No Lettuce, Carrot & Egg Mayo", negate(salad_mayo)))

    # Estimated: taking off one sauce. Grill'd sells these sauces as dips with full per-100 g figures, but doesn't publish how
    # much goes on a burger, so SAUCE_GRAMS is an assumption, kept on the low side so a removal never takes off more than is there.
    dips = {entry["product"]["title"]: per_gram(entry["product"]) for entry in source["products"].values() if entry["category"] == "Dips"}
    sauce_dip = {"Herbed Mayo": "Herbed Mayo Dip", "Sweet Chilli Mayo": "Sweet Chilli Mayo Dip", "Chipotle Mayo": "Chipotle Mayo Dip",
                 "Relish": "Tomato Relish Dip"}
    for name, subs in [(n, b["subs"]) for n, b in burgers.items()] + list(others.items()):
        options = mods.setdefault(f"grilld:{slug(name)}", [])
        for sauce, dip in sauce_dip.items():
            if sauce not in subs or dip not in dips:
                continue
            amounts = {k: round(-v * SAUCE_GRAMS, 1) for k, v in dips[dip].items()}
            label = "Tomato Relish" if sauce == "Relish" else sauce
            option = modifier(f"r:{slug(label).strip('-')}", "r", f"No {label}", amounts)
            option["est"] = True
            options.append(option)
    mods = {k: v for k, v in mods.items() if v}

    # rows: the product each item is, so diet-info.py can read its ingredients and allergens. Sliders go by their patty's name.
    MODS.write_text(json.dumps({"fetched": source["fetched"], "modifiers": mods, "rows": product_of}, indent=1) + "\n")
    def js(row):
        name, cat, s, serve = row
        nut = {k: r1(s[k]) for k in ("sat", "sugar", "fibre", "sodium") if s.get(k) is not None}
        nums = [round(s["kj"]), r1(s["p"]), r1(s.get("c")), r1(s.get("f"))]
        nums = [int(x) if isinstance(x, float) and x.is_integer() else x for x in nums]
        nut = {k: int(v) if float(v).is_integer() else v for k, v in nut.items()}
        return "    " + json.dumps([name, cat, *nums, serve, nut], ensure_ascii=False)
    block = "  grilld:[\n" + ",\n".join(js(r) for r in rows) + "\n  ],\n"
    text = MENU_SOURCE.read_text()
    if "  grilld:[" in text:
        text = re.sub(r"  grilld:\[\n.*?\n  \],\n", lambda _: block, text, count=1, flags=re.S)
    else:
        text = text.replace("  schnitz:[", block + "  schnitz:[", 1)
    MENU_SOURCE.write_text(text)
    print(f"Wrote {len(rows)} Grill'd items and {sum(len(v) for v in mods.values())} options")


if __name__ == "__main__":
    {"fetch": fetch, "build": build}[sys.argv[1] if len(sys.argv) > 1 else "build"]()
