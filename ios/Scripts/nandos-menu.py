#!/usr/bin/env python3
"""Builds Nando's for Leanr from Nando's own ordering data.

Nando's online ordering (api.nandos.com.au, the same data the Nando's app and website show) publishes a nutrition panel for
every item, every option and every protein and style of each burger, wrap, pita, salad and paella. So everything here is
Nando's own figures:

- Burgers, wraps and pitas: one item each, on its default protein and style. Swapping the style (roll, pita, wrap, garlic
  bread) or the protein is the difference between the published panels for that burger.
- Salads, bowls and paella with a protein: the same, for the protein.
- Removals and extras: Nando's panel for that option. Removals are published with only the energy and weight negative, so
  the amounts are taken as positive and taken off.

Meals and bundles that need a side or drink chosen are left out; their parts are all on the menu on their own.

Usage:
    python3 ios/Scripts/nandos-menu.py fetch   # downloads the menu into ios/Scripts/nandos-source.json (one request)
    python3 ios/Scripts/nandos-menu.py build   # writes the menu rows into menu-source.js and the options into nandos-mods.json
"""
import json, re, sys, time, subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "nandos-source.json"
MODS = HERE / "nandos-mods.json"
MENU_SOURCE = HERE / "menu-source.js"
API = "https://api.nandos.com.au/public/graphql"
STORE = "16"           # Nando's Elizabeth St, Melbourne; the menu and its nutrition are national
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
QUERY = """query getMenu($restaurantId: String!, $loadDetails: Boolean, $orderType: OrderType) {
  menu(input: {restaurantId: $restaurantId, loadDetails: $loadDetails, orderType: $orderType}) {
    categories { name products { id name choices { name type minimumOptionLimit defaultSelectedOptions options { plu name } } } }
    nutrition
  }
}"""
NUTRIENTS = {"Energy (kJ)": "kj", "Protein (g)": "p", "Total Carb (g)": "c", "Total Fat (g)": "f", "Saturated Fat (g)": "sat",
             "Sugar (g)": "sugar", "Sodium (mg)": "sodium", "Weight (g)": "g"}


def fetch():
    body = json.dumps({"operationName": "getMenu", "query": QUERY,
                       "variables": {"restaurantId": STORE, "loadDetails": True, "orderType": "PICK_UP"}})
    out = subprocess.run(["curl", "-sf", "-A", UA, "-H", "content-type: application/json", "-H", "origin: https://www.nandos.com.au",
                          "-m", "60", "--data", body, API], capture_output=True, check=True).stdout
    menu = json.loads(out)["data"]["menu"]
    # Only the figures the build reads, per serve.
    nutrition = {plu: {NUTRIENTS[k]: v for k, v in entry["nutrition"].items() if k in NUTRIENTS}
                 for plu, entry in menu["nutrition"].items() if entry.get("nutrition")}
    categories = [{"name": c["name"], "products": [{**p, "plu": p["id"].split("-")[-1]} for p in c["products"]]} for c in menu["categories"]]
    for c in categories:
        for p in c["products"]:
            del p["id"]
            for choice in p["choices"]:
                choice["defaultSelectedOptions"] = [d.split("-")[-1] for d in choice["defaultSelectedOptions"]]
    SOURCE.write_text(json.dumps({"fetched": time.strftime("%Y-%m-%d"), "store": STORE, "categories": categories,
                                  "nutrition": dict(sorted(nutrition.items()))}, indent=1, ensure_ascii=False) + "\n")
    print(f"Saved {sum(len(c['products']) for c in categories)} Nando's products and {len(nutrition)} panels")


# Work Lunch only repeats items from elsewhere on the menu.
SKIP_CATEGORIES = {"Drinks", "Nando's sauces", "Do Good, Feel Good", "Secret Menu", "Kids'", "Work Lunch under $15"}
CATEGORY = {"Sides": "side", "Desserts": "sweet"}
DIPS = {"PERinaise Chip Dip", "Mayo Chip Dip"}
# Earlier names in Leanr, kept so foods people have pinned or saved keep their IDs.
NAMES = {"4 PERi-PERi Tenders": "4 PERi-PERi Grilled Tenders", "4 BBQ Ribs": "BBQ Chicken Ribs (4)",
         "Mediterranean Salad with Protein": "Mediterranean Salad with Chicken", "Paella": "Paella with Chicken",
         "PERi-Harvest Bowl with Protein": "PERi-Harvest Bowl with Chicken", "Avo Parmesan Crunch with Protein": "Avo Parmesan Crunch with Chicken"}
LABELS = {"Chicken Leg Fillets": "Chicken Leg Fillets", "Chicken Breast": "Chicken Breast", "PERi-PERi Tenders": "PERi-PERi Tenders",
          "Superfood Veggie Patty": "Veggie Patty", "Great Pretender Protein": "Great Pretender", "Grilled Halloumi": "Halloumi"}
# Extras that are more of the main filling.
FILLINGS = re.compile(r"Chicken|Tenders|Patty|Pretender|Halloumi Cheese|BBQ Rib|Thigh|Breast", re.I)


def slug(name):
    # The same as menu-source.js uses for item IDs.
    return re.sub(r"[^a-z0-9]+", "-", name.lower())


def tidy(name):
    return re.sub(r"\s+", " ", name).strip()


def r1(x):
    return None if x is None else round(x, 1)


def diff(a, b):
    """b − a, nutrient by nutrient."""
    return {k: round(b[k] - a[k], 1) for k in ("kj", "p", "c", "f", "sat", "sugar", "sodium") if a.get(k) is not None and b.get(k) is not None}


def modifier(key, kind, name, amounts, est=False):
    nut = {k: r1(amounts[k]) for k in ("sat", "sugar", "sodium") if k in amounts}
    out = {"key": key, "id": slug(name).strip("-"), "kind": kind, "name": name, "kj": round(amounts["kj"]),
           "p": r1(amounts["p"]), "c": r1(amounts["c"]), "f": r1(amounts["f"]), "nut": nut, "price": 0}
    if est:
        out["est"] = True
    return out


def build():
    source = json.loads(SOURCE.read_text())
    panels = source["nutrition"]

    def panel(*plus):
        found = panels.get(":".join(p for p in plus if p))
        return found if found and found.get("kj") and found.get("p") is not None else None

    rows, mods, seen = [], {}, set()
    for category in source["categories"]:
        if category["name"] in SKIP_CATEGORIES:
            continue
        for product in category["products"]:
            name = tidy(product["name"])
            if product["plu"] in seen or re.search(r"\bmeal$", name, re.I):
                continue
            choices = product["choices"]
            protein = next((c for c in choices if "protein" in c["name"].lower()), None)
            style = next((c for c in choices if "style" in c["name"].lower()), None)
            # A side, drink, size or dip that has to be picked means the panel doesn't cover what's ordered.
            needed = [c for c in choices if c["minimumOptionLimit"] >= 1 and c["type"] != "basting" and c not in (protein, style)]
            if needed:
                continue
            default = lambda c: c and (c["defaultSelectedOptions"] or [c["options"][0]["plu"]])[0]
            p_plu, s_plu = default(protein), default(style)
            base = panel(product["plu"], p_plu, s_plu) if protein else panel(product["plu"])
            if not base:
                continue
            seen.add(product["plu"])
            name = NAMES.get(name, name)
            # The same item listed twice under different names (4 Mini Drums) or in two places (Perfect Pair).
            same = (base["kj"], base["p"], base.get("sodium"), base.get("g"))
            if name in {r[0] for r in rows} or same in {(r[2]["kj"], r[2]["p"], r[2].get("sodium"), r[2].get("g")) for r in rows}:
                continue
            option = {o["plu"]: o["name"] for c in choices for o in c["options"]}
            parts = [option[p] for p in (p_plu, s_plu) if p]
            serve = " · ".join(parts + [f"{round(base['g'])} g"])
            cat = "extra" if name in DIPS else CATEGORY.get(category["name"], "main")
            rows.append([name, cat, base, serve])
            options = []

            # Style swaps, on the default protein if that's published, otherwise on the first protein that has both.
            if style:
                for o in style["options"]:
                    if o["plu"] == s_plu:
                        continue
                    est, pair = False, None
                    for prot in [p_plu] + [x["plu"] for x in protein["options"] if x["plu"] != p_plu]:
                        a, b = panel(product["plu"], prot, s_plu), panel(product["plu"], prot, o["plu"])
                        if a and b:
                            pair = (a, b)
                            break
                        est = True
                    if pair:
                        options.append(modifier(f"s:bun-{slug(o['name']).strip('-')}", "s", f"Swap to {o['name']}", diff(*pair), est))
            if protein:
                for o in protein["options"]:
                    if o["plu"] == p_plu:
                        continue
                    est, pair = False, None
                    for sty in [s_plu] + ([x["plu"] for x in style["options"] if x["plu"] != s_plu] if style else []):
                        a, b = panel(product["plu"], p_plu, sty), panel(product["plu"], o["plu"], sty)
                        if a and b:
                            pair = (a, b)
                            break
                        est = True
                    if pair:
                        label = LABELS.get(o["name"], o["name"])
                        options.append(modifier(f"s:patty-{slug(label).strip('-')}", "s", f"Swap to {label}", diff(*pair), est))
            for c in choices:
                title = c["name"].lower()
                if c["type"] != "checkbox" or "share" in title:
                    continue
                for o in c["options"]:
                    found = panel(o["plu"])
                    if not found:
                        continue
                    amounts = {k: abs(v) for k, v in found.items() if k != "g"}
                    label = tidy(o["name"])
                    if "remove" in title:
                        if amounts["kj"] < 1:
                            continue
                        what = re.sub(r"^No ", "", label)
                        options.append(modifier(f"r:{slug(what).strip('-')}", "r", f"No {what}", {k: -v for k, v in amounts.items()}))
                    else:
                        what = re.sub(r"^(Extra|Add) ", "", label)
                        kind = "f" if FILLINGS.search(what) else "a"
                        options.append(modifier(f"{kind}:{slug(what).strip('-')}", kind, label if label.startswith(("Extra", "1 Extra")) else f"Add {what}", amounts))
            keys = set()
            options = [o for o in options if not (o["key"] in keys or keys.add(o["key"]))]
            if options:
                mods[f"nandos:{slug(name)}"] = options

    MODS.write_text(json.dumps({"fetched": source["fetched"], "modifiers": mods}, indent=1, ensure_ascii=False) + "\n")

    def js(row):
        name, cat, s, serve = row
        nut = {k: r1(s[k]) for k in ("sat", "sugar", "sodium") if s.get(k) is not None}
        nums = [round(s["kj"]), r1(s["p"]), r1(s.get("c")), r1(s.get("f"))]
        nums = [int(x) if isinstance(x, float) and x.is_integer() else x for x in nums]
        nut = {k: int(v) if float(v).is_integer() else v for k, v in nut.items()}
        return "    " + json.dumps([name, cat, *nums, serve, nut], ensure_ascii=False)
    block = "  nandos:[\n" + ",\n".join(js(r) for r in rows) + "\n  ],\n"
    text = MENU_SOURCE.read_text()
    text = re.sub(r"  nandos:\[\n.*?\n  \],\n", lambda _: block, text, count=1, flags=re.S)
    MENU_SOURCE.write_text(text)
    print(f"Wrote {len(rows)} Nando's items and {sum(len(v) for v in mods.values())} options")


if __name__ == "__main__":
    {"fetch": fetch, "build": build}[sys.argv[1] if len(sys.argv) > 1 else "build"]()
