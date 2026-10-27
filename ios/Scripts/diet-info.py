#!/usr/bin/env python3
"""Which meats and allergens each restaurant item has, for Leanr's dietary filters (vegetarian, no beef, no pork, allergens).

Every item gets diet info only from the restaurant's own words, and only where those words cover the whole item:

- Ingredient lists: Grill'd's ordering app (each burger's full ingredient list and its "Contains" statement), McDonald's item
  components (mcd-ingredients.json), Subway's sub builds (subway-ingredients.json) and the ingredients Hungry Jack's ordering
  menu lists as coming on each item.
- Descriptions: the item descriptions in Hungry Jack's, Oporto's and Red Rooster's ordering menus and on Domino's product pages.
- Names: Guzman y Gomez and Zambrero name every item by its filling, and KFC's are all chicken unless the name says otherwise
  (bacon is named). Names that don't say what's inside (a Stacker, a combo, anything with gravy) stay unknown.
- KFC's ordering catalogue (kfc-descriptions.json, read once in a normal browser): each item's description and its Recipe list
  of what comes on it, so a combo that lists its parts ("Burger & 1 Regular Pepsi Max") is known. Every KFC main is chicken,
  with bacon named; chips (their seasoning), gravy and a drink that isn't named keep an item unknown.
- Labels and allergens: Nando's, Hungry Jack's and Grill'd publish allergens per item, and Nando's and Grill'd label vegetarian
  and vegan items. "May contain" is kept apart from "contains".
- Allergen guides (allergen-guides.py, run before this): Domino's, Boost Juice, Oporto, Red Rooster, Spud Bar, Schnitz, Zambrero,
  Guzman y Gomez, Hungry Jack's, Subway, and McDonald's and KFC from their own pages. Spud Bar's and Hungry Jack's ingredient lists and Schnitz's descriptions also say what meat
  is in an item.

Anything else stays unknown, and the filters leave unknown items out rather than guess.

Usage:
    python3 ios/Scripts/diet-info.py fetch   # the descriptions and Hungry Jack's allergens into diet-source.json (about 50 requests)
    python3 ios/Scripts/diet-info.py build   # writes diet.json from the sources and the exported menu (run export-menu.cjs after)
"""
import os
import html, json, re, subprocess, sys, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "diet-source.json"
OUT = HERE / "diet.json"
GUIDES = HERE / "allergen-items.json"
CATALOG = HERE.parent / "MacroMenu" / "MenuData.json"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
# The keys the restaurants' own ordering websites send. They aren't kept in this repository: copy each from the
# x-api-key header in your browser's network tab on that site, and export it before running this script.
CRAVEABLE_KEY = os.environ.get("CRAVEABLE_API_KEY", "")   # Oporto's and Red Rooster's websites
HJ_KEY = os.environ.get("HJ_API_KEY", "")                 # Hungry Jack's ordering website


def get(url, headers=None, raw=False):
    args = ["curl", "-sf", "-A", UA, "-m", "60"]
    for k, v in (headers or {}).items():
        args += ["-H", f"{k}: {v}"]
    out = subprocess.run(args + [url], capture_output=True, check=True).stdout
    return out.decode("utf-8", "replace") if raw else json.loads(out)


def fetch_hj():
    menu = get("https://web-api.hungryjacks.com.au/api/v1/menu/5390", {"x-api-key": HJ_KEY, "origin": "https://order.hungryjacks.com.au",
                                                                        "Accept": "application/json"})
    mods, groups = menu["modifiers"], {g["modifier_group_id"]: g for g in menu["modifier_groups"]}
    items = {}
    for item in menu["sales_items"]:
        if item["name"] in items and items[item["name"]]["included"]:
            continue
        included = []
        for gid in item.get("modifier_groups") or []:
            for mid in groups[gid]["modifiers"]:
                mod = mods[str(mid)]
                link = next((x for x in mod["item_modifiers"] if x["sales_item_pos_item_id"] == item["pos_item_id"] and x["modifier_group_id"] == gid), None)
                if link and link["default_quantity"] > 0:
                    included.append(mod["name"].strip())
        items[item["name"]] = {"allergens": item.get("allergens"), "description": item.get("description") or "", "included": included}
    return items


def fetch_craveable(brand, store):
    listing = get(f"https://api.oporto.com.au/mobile-services/content/menu/{store}", {"x-api-key": CRAVEABLE_KEY, "x-brand-code": brand})["result"]
    menu = get(next(r["menuUrls"] for r in listing if "Pickup" in r["menuName"]))
    items = {}

    def walk(node):
        if node.get("productType") == 1 and node.get("description") and node["name"].strip() not in items:
            items[node["name"].strip()] = node["description"].strip()
        for sub in node.get("subItems") or []:
            walk(sub)
    for category in menu["categories"]:
        if category["name"] != "HIDDEN":
            for product in category["products"]:
                walk(product)
    return items


def fetch_dominos():
    page = get("https://www.dominos.com.au/menu", raw=True)
    items = {}
    for path in sorted(set(re.findall(r'href="(/menu-[a-z-]+/[a-z0-9-]+)"', page))):
        text = get("https://www.dominos.com.au" + path, raw=True)
        title = re.search(r"<title>\s*(.*?)\s*(?:-|\|)\s*Domino", text, re.S)
        desc = re.search(r'<meta\s+name="description"\s+content="([^"]*)"', text) or re.search(r'property="og:description"\s+content="([^"]*)"', text)
        if title and desc:
            items[html.unescape(title.group(1)).strip()] = html.unescape(desc.group(1)).strip()
        time.sleep(0.3)
    return items


def fetch():
    SOURCE.write_text(json.dumps({"fetched": time.strftime("%Y-%m-%d"), "hj": fetch_hj(), "oporto": fetch_craveable("opo", "melbourne-central"),
                                  "rr": fetch_craveable("rr", "carlton"), "dominos": fetch_dominos()}, indent=1, ensure_ascii=False) + "\n")
    print("Saved Hungry Jack's, Oporto, Red Rooster and Domino's descriptions")


# Meats, found in ingredient lists, descriptions or names. Pepperoni and salami are taken as both pork and beef, since either
# can be in them; gelatine is noted because it's made from pork or beef.
MEATS = {
    "beef": r"\bbeef\b|wagyu|\bangus\b|brisket|\bmince\b|bolognese|\bsteak\b|cheesesteak|barbacoa|meatball|\bveal\b|pastrami|tallow|pepperoni|salami",
    "pork": r"\bpork\b|bacon|\bham\b|prosciutto|salami|pepperoni|(?<!chicken )chorizo|pancetta|carnitas|\blard\b|hawaiian",
    "chicken": r"chicken|nugget|\btenders\b|(crispy|grilled|habanero|southern[- ]style|saucy) tender|\bwings?\b|drumstick|\bdrums?\b|zinger|rippa|bolas|poultry|mcwings",
    "lamb": r"\blamb\b|mutton",
    "fish": r"\bfish\b|filet-o-fish|\btuna\b|salmon|anchov|barramundi|worcestershire",
    "seafood": r"prawn|shrimp|calamari|squid|\bcrab\b|lobster|seafood|oyster|mussel|scallop|crustacea",
    "gelatine": r"gelatine?\b",
    "other": r"turkey|\bduck\b|venison|kangaroo|\bgoat\b",
}
# Words that mean meat of some kind but not which, so the item can't be placed.
UNSURE = r"\bsausage\b(?![^,;]*\b(beef|pork)\b)|\bmeats?\b|meatlover|meat lover|carnivore|\bribs?\b|\bstock\b|\bbroth\b|gravy|chicken salt|\bfillet\b|(?<!chicken )schnitzel|\bschnitz\b"
# Phrases that look like meat but aren't.
NOT_MEAT = r"plant[- ]based|meat[- ]free|meatless|\bvegan\b[^,;]*|beyond|great pretender|veggie patty|garden patty|vegetarian|no meat|chicken-style|mock"


# Chains whose descriptions or names list everything on an item, so naming no meat means it has none.
COMPLETE = {"dominos", "oporto", "hj", "gyg", "zam"}
VEG_CUE = r"veggie|vegetarian|vegan|plant[- ]based|falafel|mushroom|margherita|cheese toastie|halloumi"
GELATINE_RISK = r"cheesecake|mousse|jelly|marshmallow|panna cotta|gumm|lolly|trifle"


def meats(text):
    """The meats named in `text`, and whether some meat is named that can't be placed."""
    lower = re.sub(NOT_MEAT, " ", text.lower())
    found = {meat for meat, pattern in MEATS.items() if re.search(pattern, lower)}
    unsure = bool(re.search(UNSURE, lower))
    # A stock or gravy named for its meat is that meat.
    for meat in ("chicken", "beef"):
        if re.search(rf"{meat} (stock|broth|gravy)", lower):
            found.add(meat)
    if "chicken salt" in lower or "gravy" in lower:
        unsure = True
    if re.search(r"\bfillets?\b", lower) and ({"chicken", "fish"} & found):
        unsure = bool(re.search(UNSURE.replace(r"|\bfillet\b", ""), lower))
    return found, unsure


ALLERGENS = {"gluten": r"gluten|wheat|barley|\brye\b|\boats?\b", "wheat": r"wheat|spelt", "milk": r"\bmilk", "egg": r"\beggs?\b", "soy": r"\bsoy",
             "sesame": r"sesame", "peanut": r"peanut", "treenut": r"tree ?nuts?|almond|cashew|hazelnut|walnut|pecan|pistachio|macadamia",
             "fish": r"\bfish\b", "shellfish": r"shellfish|crustacea|mollusc", "lupin": r"lupin", "sulphites": r"sulphite|sulfite"}


def allergens_in(text):
    return sorted(a for a, pattern in ALLERGENS.items() if re.search(pattern, text.lower()))


def norm(name):
    name = re.sub(r"[®™]", "", name).lower().replace("&", "and")
    name = re.sub(r"\((?:\d+ slice|1 piece|regular|original|medium|large|small)\)|\bwith\b|\bburgers?\b|\bsingle\b", " ", name)
    return re.sub(r"[^a-z0-9]", "", name)


def entry(meat, src, al=None, may=None, vg=None, unk=None):
    out = {"meat": sorted(meat) if meat is not None else None, "src": src}
    if al is not None:
        out["al"] = sorted(set(al))
        if may:
            out["may"] = sorted(set(may) - set(al))
        # Allergens the restaurant doesn't say either way for this item, like wheat when it only says "gluten".
        unk = sorted(set(unk or []) - set(al) - set(may or []))
        if unk:
            out["unk"] = unk
    if vg:
        out["vg"] = vg
    elif meat is not None and not meat:
        out["vg"] = "vegetarian"
    return out


def from_text(text, src):
    found, unsure = meats(text)
    return {"meat": None, "src": src} if unsure else entry(found, src)


def build():
    catalog = json.loads(CATALOG.read_text())["foods"]
    source = json.loads(SOURCE.read_text())
    nandos = json.loads((HERE / "nandos-source.json").read_text())
    nandos_rows = json.loads((HERE / "nandos-mods.json").read_text())["rows"]
    grilld = json.loads((HERE / "grilld-source.json").read_text())["products"]
    grilld_rows = json.loads((HERE / "grilld-mods.json").read_text())["rows"]
    mcd = json.loads((HERE / "mcd-ingredients.json").read_text())["items"]
    subway = json.loads((HERE / "subway-ingredients.json").read_text())
    lookups = {chain: {norm(name): value for name, value in source[chain].items()} for chain in ("hj", "oporto", "rr", "dominos")}
    guides = json.loads(GUIDES.read_text())["items"] if GUIDES.exists() else {}
    kfc_said = json.loads((HERE / "kfc-descriptions.json").read_text())["items"] if (HERE / "kfc-descriptions.json").exists() else {}
    out = {}

    def subway_parts(name):
        for pattern in (r'^6" (.+)$', r'^Footlong (.+)$', r'^(.+) 6"$', r'^(.+) Wrap$', r'^(.+) Salad \(regular\)$'):
            m = re.match(pattern, name)
            if m:
                key = m.group(1)
                return subway["subs"].get(key) or subway["subs"].get(key.replace(" Brekkie", "")) or subway["subs"].get(key + " on Rye")
        return None

    for food in catalog:
        chain, name, fid = food["chain"], food["name"], food["id"]
        info = None
        if chain in ("mine", "generic"):
            continue
        if food["cat"] == "drink" and not meats(name)[0]:
            # Drinks: juices, coffees, shakes and soft drinks. None has meat in it.
            info = entry(set(), "name")
        elif chain == "nandos" and fid in nandos_rows:
            panel = nandos["nutrition"].get(nandos_rows[fid], {})
            labels = panel.get("suitability", {})
            contains = panel.get("contains")
            # Nando's lists wheat and gluten apart, so "Gluten" alone is another cereal.
            names = {"Wheat": ["gluten", "wheat"], "Gluten": ["gluten"], "Milk": ["milk"], "Egg": ["egg"], "Soy": ["soy"], "Sesame": ["sesame"],
                     "Peanuts": ["peanut"], "Tree Nuts": ["treenut"], "Fish": ["fish"], "Shellfish": ["shellfish"], "Lupin": ["lupin"],
                     "Sulphites": ["sulphites"]}
            al = [a for k, v in (contains or {}).items() if v >= 1 for a in names.get(k, [])] if contains is not None else None
            may = [a for k, v in (contains or {}).items() if 0 < v < 1 for a in names.get(k, [])]
            vg = "vegan" if labels.get("Vegan") else "vegetarian" if labels.get("Vegetarian") else None
            if vg:
                info = entry(set(), "labels", al, may, vg)
            else:
                found, unsure = meats(f"{name} {food.get('serve', '')}")
                info = entry(found if found and not unsure else None, "name", al, may)
        elif chain == "grilld":
            product = grilld.get(grilld_rows.get(fid, ""), {}).get("product")
            if product and product.get("ingredients") and not name.endswith("Slider"):
                text = html.unescape(re.sub(r"<[^>]+>", " ", product["ingredients"])).replace("\xa0", " ")
                # The allergen statements follow the ingredient list: "… Spanish Onion.  Contains Egg, Gluten (Wheat), Milk.  May contain Sesame."
                statement = list(re.finditer(r"\.\s+Contains:?\s+(.+?)\.(?=\s|$)", text))
                statement = statement[-1] if statement else None
                may = re.search(r"\.\s+May contain:?\s+(.+?)\.(?=\s|$)", text)
                body = text[:statement.start() + 1] if statement else text
                found, unsure = meats(body)
                attrs = set(product.get("attributes") or [])
                vg = "vegan" if "VE" in attrs else "vegetarian" if "V" in attrs else None
                # "Gluten (during burger prep)" doesn't say which cereal, so wheat isn't known either way.
                said = " ".join(m.group(1) for m in (statement, may) if m)
                unk = ["wheat"] if "gluten" in allergens_in(said) and not re.search(r"wheat|barley|\brye\b|\boats?\b|spelt", said, re.I) else []
                info = entry(set() if vg else (found if not unsure else None), "ingredients",
                             allergens_in(statement.group(1)) if statement else None, allergens_in(may.group(1)) if may else None, vg, unk)
        elif chain == "mcd" and fid in mcd:
            parts = " , ".join(p[0] for p in mcd[fid][2])
            info = from_text(f"{name} , {parts}", "ingredients")
        elif chain == "mcd" and re.search(r"McNuggets|McWings", name):
            info = from_text(name, "name")
        elif chain == "sub":
            parts = subway_parts(name)
            if parts:
                info = from_text(f"{name} , {', '.join(parts)}", "ingredients")
        elif chain == "hj":
            nuggets = re.match(r"(\d+) Nuggets$", name)
            item = lookups["hj"].get(norm(f"Chicken Nuggets {nuggets.group(1)} Pack" if nuggets else name))
            if item and (item["included"] or item["description"]):
                found, unsure = meats(f"{name} , {', '.join(item['included'])} , {item['description']}")
                raw = item.get("allergens") or {}
                al = [a for k, v in raw.items() if v for a in {"gluten": ["gluten"], "eggs": ["egg"], "milk_and_milk_products": ["milk"], "soy": ["soy"],
                      "fish_and_crustacea": ["fish", "shellfish"], "peanuts": ["peanut"], "tree_nuts": ["treenut"], "sesame": ["sesame"],
                      "sulphites": ["sulphites"], "lupin": ["lupin"]}.get(k, [])] if raw else None
                # Hungry Jack's guide has no lupin column, and its gluten doesn't say which cereal.
                unk = ["lupin"] + (["wheat"] if raw.get("gluten") else [])
                info = entry(None if unsure else found, "ingredients" if item["included"] else "description", al, unk=unk)
        elif chain in ("oporto", "rr", "dominos"):
            key = norm(name)
            text = lookups[chain].get(key) or lookups[chain].get(norm(re.sub(r"^(Single|Double|Triple|New Yorker) ", "", name)))
            if text and chain == "dominos":
                # Domino's descriptions list every topping, so a name like "Meatlovers" doesn't leave it unknown.
                found, unsure = meats(text)
                info = {"meat": None, "src": "description"} if unsure else entry(found | meats(name)[0], "description")
            elif text:
                info = from_text(f"{name} , {text}", "description")
            elif chain == "dominos" and re.match(r"(Saucy )?Chicken (Wings|Tenders)", name):
                info = from_text(name, "name")
        elif chain in ("gyg", "zam"):
            info = from_text(name, "name")
        elif chain == "kfc" and name in kfc_said:
            said = kfc_said[name]
            # "Chicken breast meat" names the meat, so it doesn't count as some meat that can't be placed.
            text = re.sub(r"breast meat", "breast", f"{name} , {said['text']} , {', '.join(said.get('recipe', []))}")
            found, unsure = meats(text)
            # The chips' seasoning, gravy or a drink that isn't named could hold anything.
            hidden = re.search(r"(?<!corn )\bchips\b|gravy|season|\bstock\b|\bdrink\b", text, re.I)
            if not unsure and not hidden:
                info = entry(found | {"chicken"} if food["cat"] == "main" else found, "description")
        elif chain == "kfc":
            # Everything named for its chicken, with bacon named; combos, packs and Stackers don't say all that's in them.
            if not re.search(r"stacker|combo|pack|box|bucket|feast|meal|bowl|gravy", name, re.I):
                found, unsure = meats(name)
                if found and not unsure:
                    info = entry(found, "name")
        elif chain == "boost":
            info = entry(set(), "name")
        guide = guides.get(fid)
        if guide and (info is None or info["meat"] is None) and guide.get("text"):
            # Spud Bar's full ingredient lists and Schnitz's descriptions say what's in the item.
            info = from_text(f"{name} , {guide['text']}", "ingredients" if chain == "spud" else "description")
        if info is None:
            info = {"meat": None, "src": None}
        elif info["meat"] == [] and info.get("vg") == "vegetarian" and (info["src"] in ("name", "description") or chain == "mcd"):
            said = (lookups.get(chain) or {}).get(norm(name), "")
            if isinstance(said, dict):
                said = f"{said['description']} {', '.join(said['included'])}"
            parts = " ".join(p[0] for p in mcd.get(fid, [0, 0, []])[2]) if chain == "mcd" else ""
            text = f"{name} {said} {parts}"
            # No meat named isn't the same as none in it. A main only counts when its words list everything that's on it
            # (Domino's, Oporto and Hungry Jack's descriptions, GYG's and Zambrero's fillings) or say it's vegetarian;
            # and desserts that often set with gelatine stay unknown.
            complete = chain in COMPLETE or re.search(VEG_CUE, text, re.I)
            # An unnamed seasoning, stock or gravy could be chicken salt or meat stock.
            hidden = re.search(r"season|stock|gravy|broth", text, re.I)
            if food["cat"] in ("main", "breakfast") and not complete or food["cat"] == "sweet" and re.search(GELATINE_RISK, text, re.I) or hidden:
                info = {"meat": None, "src": info["src"]}
        if guide and ("al" not in info or chain == "hj"):
            # The restaurant's allergen guide (allergen-guides.py). Hungry Jack's reports also say what may be present, and
            # cover lupin, which its ordering menu leaves out.
            info.pop("unk", None); info.pop("may", None)
            info["al"] = guide["al"]
            if guide["may"]:
                info["may"] = guide["may"]
            if guide.get("unk"):
                info["unk"] = guide["unk"]
            if guide.get("vg") and info["meat"] is None or guide.get("vg") == "vegan" and info["meat"] == []:
                info.update(meat=[], vg=guide["vg"], src="labels")
        out[fid] = info

    OUT.write_text(json.dumps({"fetched": source["fetched"], "items": out}, indent=1, ensure_ascii=False) + "\n")
    known = sum(1 for v in out.values() if v["meat"] is not None)
    with_al = sum(1 for v in out.values() if "al" in v)
    print(f"{known} of {len(out)} items with known meat, {with_al} with allergens")
    for chain in sorted({fid.split(":")[0] for fid in out}):
        items = [v for fid, v in out.items() if fid.startswith(chain + ":")]
        print(f"  {chain}: meat known {sum(v['meat'] is not None for v in items)}/{len(items)}, allergens {sum('al' in v for v in items)}")

if __name__ == "__main__":
    {"fetch": fetch, "build": build}[sys.argv[1] if len(sys.argv) > 1 else "build"]()
