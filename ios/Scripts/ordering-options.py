#!/usr/bin/env python3
"""Customisations for Hungry Jack's and Oporto, from their own online ordering menus.

Both ordering menus give the energy of everything that can be added to a burger, wrap or bowl, the figure shown when it's
added in their apps. Hungry Jack's also gives the energy of an extra serve of each ingredient that comes on the item.
Neither gives protein, carbs or fat for these, so:

- Energy is always the restaurant's own figure.
- A sauce the restaurant also sells as a dipping sauce takes that dip's make-up, scaled to the energy. Anything else has
  protein, carbs and fat estimated from the kind of ingredient, and is marked est.
- Taking something off uses the energy of one serve of it: Hungry Jack's extra serve of that ingredient, or Oporto's
  figure for adding it. How much is on each item isn't published, so every removal is marked est.

Usage:
    python3 ios/Scripts/ordering-options.py fetch   # downloads both menus into ordering-options-source.json
    python3 ios/Scripts/ordering-options.py build   # writes hj-mods.json and oporto-mods.json
"""
import os
import json, re, sys, time, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "ordering-options-source.json"
CATALOG = HERE.parent / "MacroMenu" / "MenuData.json"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
# The keys the ordering websites themselves send. They aren't kept in this repository: copy each from the x-api-key
# header in your browser's network tab on that site and export it before running this script
# (HJ_API_KEY for Hungry Jack's, CRAVEABLE_API_KEY for Oporto).
HJ = {"url": "https://web-api.hungryjacks.com.au/api/v1/menu/5390",   # Elizabeth Street, Melbourne
      "headers": {"x-api-key": os.environ.get("HJ_API_KEY", ""), "origin": "https://order.hungryjacks.com.au"}}
OPORTO = {"url": "https://api.oporto.com.au/mobile-services/content/menu/melbourne-central",
          "headers": {"x-api-key": os.environ.get("CRAVEABLE_API_KEY", ""), "x-brand-code": "opo"}}


def get(url, headers=None):
    args = ["curl", "-sf", "-A", UA, "-m", "60", "-H", "Accept: application/json"]
    for k, v in (headers or {}).items():
        args += ["-H", f"{k}: {v}"]
    return json.loads(subprocess.run(args + [url], capture_output=True, check=True).stdout)


def fetch_hj():
    menu = get(HJ["url"], HJ["headers"])
    mods, groups = menu["modifiers"], {g["modifier_group_id"]: g for g in menu["modifier_groups"]}
    items = {}
    for item in menu["sales_items"]:
        if not item.get("modifier_groups") or item["name"] in items:
            continue
        options = []
        for gid in item["modifier_groups"]:
            group = groups[gid]
            for mid in group["modifiers"]:
                mod = mods[str(mid)]
                link = next((x for x in mod["item_modifiers"] if x["sales_item_pos_item_id"] == item["pos_item_id"] and x["modifier_group_id"] == gid), None)
                if not link:
                    continue
                actions = link["actions"]
                more = mods.get(actions.get("1", ""))
                options.append({"name": mod["name"].strip(), "group": group["name"], "included": link["default_quantity"] > 0,
                                "kj": more and more["energy_kj"] or None, "removable": "2" in actions})
        items[item["name"]] = {"kj": item.get("energy_kj"), "options": options}
    return items


def fetch_oporto():
    listing = get(OPORTO["url"], OPORTO["headers"])["result"]
    menu = get(next(r["menuUrls"] for r in listing if "Pickup" in r["menuName"]))
    items = {}

    def walk(node):
        groups = [g for g in node.get("subItems") or [] if g.get("productType") == 3 and g["name"].startswith("Customise")]
        if groups and node["name"].strip() not in items:
            items[node["name"].strip()] = {"kj": node.get("kJ"), "options": [
                {"name": o["name"].strip(), "group": g["name"], "kj": o.get("kJ")} for g in groups for o in g.get("subItems") or []]}
        for sub in node.get("subItems") or []:
            walk(sub)
    for category in menu["categories"]:
        if category["name"] != "HIDDEN":
            for product in category["products"]:
                walk(product)
    return items


def fetch():
    SOURCE.write_text(json.dumps({"fetched": time.strftime("%Y-%m-%d"), "hj": fetch_hj(), "oporto": fetch_oporto()},
                                 indent=1, ensure_ascii=False) + "\n")
    print("Saved Hungry Jack's and Oporto ordering options")


# Shares of an ingredient's energy as [protein, carbs, fat], by kind. First match wins.
SPLITS = [
    (r"ketchup|bbq|barbecue|sweet|relish|honey|plum|napoletana|tomato sauce|jam", (0.02, 0.95, 0.03)),
    (r"mustard", (0.20, 0.45, 0.35)),
    (r"mayo|aioli|sauce|ranch|chipotle|garlic|peri|prego|lemon & herb|extremo|chilli|butter", (0.02, 0.10, 0.88)),
    (r"halloumi", (0.27, 0.03, 0.70)),
    (r"cheese", (0.26, 0.04, 0.70)),
    (r"bacon", (0.30, 0.01, 0.69)),
    (r"ham\b", (0.60, 0.10, 0.30)),
    (r"sausage", (0.23, 0.02, 0.75)),
    (r"egg", (0.35, 0.02, 0.63)),
    (r"plant|veggie", (0.20, 0.35, 0.45)),
    (r"beef|angus|patty", (0.38, 0.01, 0.61)),
    (r"grilled chicken|fillet|chicken", (0.70, 0.05, 0.25)),
    (r"avocado", (0.04, 0.06, 0.90)),
    (r"hash brown|onion ring|angry onion|crispy onion", (0.04, 0.44, 0.52)),
    (r"pineapple|lettuce|tomato|onion|pickle|jalape|slaw|beetroot", (0.12, 0.83, 0.05)),
]
FILLING = re.compile(r"patty|fillet|chicken|halloumi", re.I)
SKIP = re.compile(r"syrup|milk|sugar|sweetener|equal|cream|bursties|topping|drizzle|dusting|oreo|flake|biscoff|caramel|vanilla|hazelnut|ice", re.I)


def slug(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def r1(x):
    return round(x, 1) + 0.0  # never -0.0


def norm(name):
    name = re.sub(r"[®™]", "", name).lower()
    name = re.sub(r"\bwith\b|\bburger\b|\bsingle\b", " ", name)
    return re.sub(r"[^a-z0-9]", "", name)


def label(name):
    name = re.sub(r"^((add|remove|no|extra)\s+)+", "", name.strip(), flags=re.I)
    name = re.sub(r"\s*\((?:1|2) (?:piece|slice|slices|pieces)\)$", "", name)
    return name[:1].upper() + name[1:]


def same(name):
    """One name for an ingredient however it's written: Mayonnaise and Mayo, Cheese Slice and Cheese."""
    name = name.lower().replace("mayonnaise", "mayo")
    return re.sub(r"\s+(slice|sauce)s?$", "", name)


def amounts(name, kj, dips):
    """Protein, carbs and fat for `kj` of an ingredient: from the same sauce sold as a dip, or estimated."""
    words = set(re.findall(r"[a-z]+", label(name).lower())) - {"sauce", "dipping", "the", "and"}
    dip = next((d for d in dips if words and words <= set(re.findall(r"[a-z]+", d["name"].lower()))), None)
    if dip and dip["kj"]:
        k = kj / dip["kj"]
        nut = {key: r1(v * k) for key, v in (dip.get("nut") or {}).items()}
        return {"p": r1(dip["p"] * k), "c": r1((dip.get("c") or 0) * k), "f": r1((dip.get("f") or 0) * k), "nut": nut}, False
    split = next((s for pattern, s in SPLITS if re.search(pattern, name, re.I)), (0.10, 0.45, 0.45))
    kcal = kj / 4.184
    return {"p": r1(kcal * split[0] / 4), "c": r1(kcal * split[1] / 4), "f": r1(kcal * split[2] / 9)}, True


def option(kind, name, kj, dips, remove=False):
    values, est = amounts(name, kj, dips)
    sign = -1 if remove else 1
    values = {k: (v if k == "nut" else r1(sign * v)) for k, v in values.items()}
    if values.get("nut"):
        values["nut"] = {k: r1(sign * v) for k, v in values["nut"].items()}
    out = {"key": f"{'r' if remove else kind}:{slug(name)}", "id": f"{'no' if remove else 'extra'}-{slug(name)}", "kind": "r" if remove else kind,
           "name": f"No {name}" if remove else name, "kj": sign * round(kj), "p": values["p"], "c": values["c"], "f": values["f"]}
    if values.get("nut"):
        out["nut"] = values["nut"]
    if est or remove:
        out["est"] = True
    return out


# Leanr items whose ordering-menu name is different.
ALIASES = {
    "hj": {"Whopper Junior": "Whopper Jr", "Whopper Junior with Cheese": "Whopper Junior Cheese", "Grilled Chicken Burger": "Grilled Chicken",
           "Spicy Grilled Chicken Burger": "Spicy Grilled Chicken", "Grilled Chicken with Bacon & Cheese": "Grilled Chicken Bacon & Cheese",
           "Grill Masters Angus Bacon & Cheese": "Grill Masters Bacon & Cheese Angus", "Grill Masters Double Angus Bacon & Cheese": "Grill Masters Double Bacon & Cheese Angus",
           "Veggie Whopper with Cheese": "Veggie Whopper Cheese", "Plant-Based Whopper with Cheese": "Plant Based Whopper Cheese",
           "Plant-Based Whopper": "Plant Based Whopper", "Plant-Based Angry Whopper": "Angry Plant Based Whopper",
           "Sausage & Egg Turkish Brekky Roll": "Sausage & Egg on Turkish", "Bacon & Egg Turkish Brekky Roll": "Bacon & Egg on Turkish"},
    "oporto": {},
}


def build():
    source = json.loads(SOURCE.read_text())
    catalog = json.loads(CATALOG.read_text())["foods"]
    for chain in ("hj", "oporto"):
        menu = source[chain]
        by_name = {norm(name): item for name, item in menu.items()}
        foods = [f for f in catalog if f["chain"] == chain and f["cat"] in ("main", "breakfast")]
        dips = [f for f in catalog if f["chain"] == chain and f["cat"] == "extra"]
        mods, matched = {}, 0
        for food in foods:
            alias = ALIASES[chain].get(food["name"])
            # Oporto lists its burgers as Single, Double and Triple; Leanr's are the singles.
            item = by_name.get(norm(alias or food["name"]))
            if not item:
                continue
            matched += 1
            options, add_kj = [], {}
            for o in item["options"]:
                if o.get("kj") and not o["name"].lower().startswith("remove"):
                    add_kj.setdefault(label(o["name"]).lower(), o["kj"])
            for o in item["options"]:
                name = label(o["name"])
                if SKIP.search(name):
                    continue
                kj = o.get("kj")
                if chain == "hj":
                    # An add-on for something already on the item is the same as its extra serve, which is listed too.
                    if not o["included"] and same(name) in {same(label(x["name"])) for x in item["options"] if x["included"]}:
                        continue
                    if o["included"]:
                        if kj:
                            options.append(option("a", f"Extra {name}", kj, dips))
                        if o["removable"] and (kj or add_kj.get(name.lower())):
                            options.append(option("a", name, kj or add_kj[name.lower()], dips, remove=True))
                    elif kj:
                        options.append(option("f" if FILLING.search(name) else "a", f"Add {name}", kj, dips))
                elif o["name"].lower().startswith("remove"):
                    found = add_kj.get(name.lower()) or next((v for k, v in add_kj.items() if name.lower().rstrip("s") in k or k in name.lower()), None)
                    if found:
                        options.append(option("a", name, found, dips, remove=True))
                elif kj:
                    options.append(option("f" if FILLING.search(name) else "a", f"Add {name}", kj, dips))
            keys = set()
            options = [o for o in options if not (o["key"] in keys or keys.add(o["key"]))]
            if options:
                mods[food["id"]] = options
        (HERE / f"{chain}-mods.json").write_text(json.dumps({"fetched": source["fetched"], "modifiers": mods}, indent=1, ensure_ascii=False) + "\n")
        print(f"{chain}: {matched} of {len(foods)} items matched, {sum(len(v) for v in mods.values())} options")


if __name__ == "__main__":
    {"fetch": fetch, "build": build}[sys.argv[1] if len(sys.argv) > 1 else "build"]()
