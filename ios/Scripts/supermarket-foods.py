#!/usr/bin/env python3
"""Builds MacroMenu/SupermarketFoods.json: ready meals and snacks sold at Coles and Woolworths, from Open Food Facts.

Source: the Open Food Facts CSV export (https://world.openfoodfacts.org/data), under the Open Database License (ODbL).
The result is a derived database, so it stays under the ODbL and must stay public: it lives in this repo for that reason.
Coles and Woolworths don't allow their own sites to be collected from (Woolworths bars any robot or retrieval tool, and Coles
allows personal, non-commercial use only), so don't swap this for their product pages or APIs.

    curl -sL https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz | gunzip -c \\
        | python3 ios/Scripts/supermarket-foods.py

Most entries name no store, so a product counts as sold somewhere in one of three ways: an entry says so, it's that supermarket's own
brand, or it's from a brand that other entries place on that supermarket's shelves (MIN_STOCKED). The last is an inference about the
brand, not that exact flavour, and the app says ranges vary.

These are volunteers' readings of the pack, so only rows that pass the checks below go in, and the app says where they're from.
Allergens are left out on purpose: a blank field there doesn't mean a product is free of anything, so dietary needs exclude these.
"""
import csv, json, re, sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent / "MacroMenu"
csv.field_size_limit(10_000_000)

# Woolworths is also a South African chain, with its own products.
ELSEWHERE = re.compile(r"south[- ]africa|new[- ]zealand", re.I)
AUSTRALIAN_CODE = ("93", "94")
OLDEST = 2019   # older entries are too likely to be a recipe that has since changed
OWN_BRANDS = {"coles": re.compile(r"^coles\b", re.I), "woolworths": re.compile(r"^(woolworths\b|macro$|macro organic\b|macro wholefoods\b)", re.I)}
OTHER_SHOPS = re.compile(r"^(aldi|iga|costco|kirkland|harris farm|black (&|and) gold|community co|home ?brand)\b", re.I)
MIN_STOCKED = 3   # entries placing a brand at a supermarket before its other products count as sold there

MEAL = re.compile(r"en:(prepared-meals|meals|frozen-ready-made-meals|microwave-meals|ready-meals|meals-with-[a-z-]+|"
                  r"pasta-dishes|rice-dishes|noodle-dishes|fresh-meals|soups|prepared-salads|meat-pies|pies|pizzas|sandwiches|wraps|sushi|dumplings)\b")
MEAL_WORDS = re.compile(r"\b(ready meal|meal kit|lasagne|lasagna|curry|risotto|butter chicken|tikka|korma|massaman|fried rice|"
                        r"carbonara|bolognese|stroganoff|mac (and|&|n) cheese|macaroni|shepherd'?s pie|cottage pie|burrito|"
                        r"quesadilla|protein bowl|poke|ramen|laksa|pho|dumplings?|gyoza|sushi|chicken parm|parmigiana|salad bowl|"
                        r"sandwich|wrap|pizza|soup)\b", re.I)
SNACK = re.compile(r"en:(snacks|sweet-snacks|salty-snacks|crisps|chips|popcorn|nuts|nuts-and-their-products|biscuits-and-cakes|biscuits|"
                   r"crackers|chocolates|chocolate-candies|confectioneries|candies|bars|cereal-bars|protein-bars|energy-bars|"
                   r"muesli-bars|dried-fruits|jerky|rice-cakes|yogurts|puddings|protein-puddings)\b")
SNACK_WORDS = re.compile(r"\b(protein bar|muesli bar|snack|chips|crisps|popcorn|jerky|biltong|rice cakes?|crackers?|"
                         r"trail mix|pretzels?|cookies?|biscuits?|yoghurt pouch|protein yoghurt|protein pudding)\b", re.I)
# Things that share those categories without being a ready meal or a snack.
NOT_FOOD_HERE = re.compile(r"en:(baby-foods|babyfoods|infant|dog|cat|pet|beverages-and-beverages-preparations|alcoholic|"
                           r"dietary-supplements|sports-supplement|protein-powders|sauces|condiments|spreads|cooking-helpers|"
                           r"pasta-sauces|stocks|flours|raw|fresh-meats)", re.I)
NOT_WORDS = re.compile(r"\b(baby|bubs|toddler|infant|dog|cat food|paste|stock|sauce|simmer|seasoning|spice mix|recipe base|powder|"
                       r"gravy|dressing|marinade|dip mix|bread mix|cake mix|baking|slim\w*|shake|meal replacement|supplement|capsules?|"
                       r"tortillas?|flour|slices|bases?|shredded|grated|fillets? with|rub|pub style|\d+ ?oz)\b", re.I)
# Jars and packets for cooking with, which read like ready meals: their brands make little else.
COOKING_BRANDS = re.compile(r"^(passage (to|foods)|masterfoods|patak|chicken tonight|continental|maggi|kan tong|ayam|mae ploy|old el paso|"
                            r"valcom|asian home gourmet|sharwood|leggo|dolmio|barilla|san remo|sunrice|sun rice|pandaroo)\b", re.I)
# Dry goods and sweet things whose names can sound like a meal: Shapes pizza, a Ritz sandwich, sushi rice, lemon meringue pie.
NOT_A_MEAL = re.compile(r"en:(biscuits|crackers|sweet-snacks|salty-snacks|desserts|cakes|sweet-pies|chocolates|dry-pastas|rices|cereals)\b", re.I)
NOT_A_MEAL_WORDS = re.compile(r"\b(shapes|ritz|tuc|biscuits?|choc\w*|meringue|custard|apple|lemon|cherry|rice$|noodles?$|pasta$|bakery|"
                              r"bread|loaf|thins|wraps$)\b", re.I)
# A snack from these shelves that lists less energy than this per 100 g has been typed in wrong.
DRY_SNACK = re.compile(r"en:(biscuits|crackers|crisps|chips|chocolates|confectioneries|candies|protein-bars|cereal-bars|muesli-bars|nuts)\b", re.I)
DRY_SNACK_KJ = 1000
FROZEN = re.compile(r"en:frozen-foods\b")
YOGHURT_KJ, YOGHURT_PROTEIN = 750, 15
PACK_GRAMS = 550      # a bigger pack is a family meal, not one person's
MEAL_GRAMS = 150      # less than this is a side or a packet of something dry, not a meal
MEAL_CAL = 120
# Most energy per 100 g that a meal can really hold. More usually means per-serve figures entered as per 100 g.
SOUP_KJ, MEAL_KJ, BAKED_KJ = 700, 1250, 1500
BAKED = re.compile(r"\b(pizza|pie|pies|roll|rolls|parmigiana|parma|sandwich|wrap|burrito|quesadilla)\b", re.I)


def number(row, key):
    try:
        value = float(row.get(key) or "")
    except ValueError:
        return None
    return value if 0 <= value < 100_000 else None


def tidy(text):
    text = re.sub(r"\s+", " ", (text or "").replace("&amp;", "&").replace("&quot;", '"')).strip(" ,.-")
    # Pack sizes in the name, which volunteers often add and the serving already says.
    text = re.sub(r"\s*\b\d+(\.\d+)?\s*(g|kg|ml|l|pk|pack)$", "", text, flags=re.I)
    text = re.sub(r"\b\d{6,}\b\s*", "", text).strip()   # an item number
    if text.isupper() or text.islower():
        text = re.sub(r"[A-Za-z']+", lambda m: m.group().capitalize() if len(m.group()) > 2 or m.start() == 0 else m.group().lower(), text.lower())
    return text


def name_of(row):
    name = tidy(row.get("product_name"))
    if not name or len(name) < 4 or len(name) > 70 or re.search(r"[^\x00-\x7f’–]", name):
        return None
    brand = tidy((row.get("brands") or "").split(",")[0])
    if brand and len(brand) <= 24 and brand.lower() not in name.lower():
        name = f"{brand} {name}"
    return name


def australian(row):
    countries = (row.get("countries_tags") or "") + " " + (row.get("countries_en") or "")
    if "australia" not in countries.lower():
        return False
    return not ELSEWHERE.search(countries) or (row.get("code") or "").startswith(AUSTRALIAN_CODE)


def brand_of(row):
    return tidy((row.get("brands") or "").split(",")[0]).lower().replace("’", "'")


def tagged(row):
    """The supermarkets an entry names."""
    stores = (row.get("stores") or "").lower()
    found = []
    if re.search(r"\bcoles\b", stores) and "coles express" not in stores:
        found.append("coles")
    if re.search(r"\bwoolworths\b|\bwoolies\b", stores):
        found.append("woolworths")
    return found


def stocked_brands(rows):
    """For each supermarket, the brands enough entries place on its shelves."""
    counts = Counter((shop, brand_of(row)) for row in rows for shop in tagged(row))
    return {shop: {brand for (at, brand), count in counts.items() if at == shop and brand and count >= MIN_STOCKED} for shop in OWN_BRANDS}


def shops(row, stocked):
    brand = brand_of(row)
    own = [shop for shop, pattern in OWN_BRANDS.items() if pattern.search(brand)]
    if own:
        return own
    if OTHER_SHOPS.search(brand):
        return []
    return sorted(set(tagged(row)) | {shop for shop, brands in stocked.items() if brand in brands})


def kind(row, name):
    tags = row.get("categories_tags") or ""
    if NOT_FOOD_HERE.search(tags) or NOT_WORDS.search(name) or COOKING_BRANDS.search(name):
        return None
    if (MEAL.search(tags) or MEAL_WORDS.search(name)) and not (NOT_A_MEAL.search(tags) or NOT_A_MEAL_WORDS.search(name)):
        return "main"
    if (SNACK.search(tags) or SNACK_WORDS.search(name)) and not FROZEN.search(tags):
        return "snack"
    return None


def serving(row, cat):
    """The grams or mL in one serving, and how to say it. A ready meal with no serving listed counts as one pack, up to a meal's size."""
    size = number(row, "serving_quantity")
    text = row.get("serving_size") or ""
    unit = "mL" if re.search(r"\d\s*(ml|l)\b", text + " " + (row.get("quantity") or ""), re.I) else "g"
    if size and 3 <= size <= 1000:
        return size, f"{size:g} {unit}"
    pack = number(row, "product_quantity")
    if cat == "main" and pack and 120 <= pack <= PACK_GRAMS:
        return pack, f"{pack:g} {unit} pack"
    return None


def figures(row):
    """Per 100 g: energy, protein, carbs and fat, or None when any is missing or they don't add up."""
    kj, kcal = number(row, "energy-kj_100g"), number(row, "energy-kcal_100g")
    protein, carbs, fat = number(row, "proteins_100g"), number(row, "carbohydrates_100g"), number(row, "fat_100g")
    if kj is None and kcal is not None:
        kj = kcal * 4.184
    if None in (kj, protein, carbs, fat) or not 40 <= kj <= 3800 or protein + carbs + fat > 101:
        return None
    worked_out = (protein * 17 + carbs * 17 + fat * 37)
    if abs(worked_out - kj) > max(120, kj * 0.2):
        return None
    return kj, protein, carbs, fat


def foods_from(rows, counts):
    seen, out = {}, []
    stocked = stocked_brands(rows)
    for row in rows:
        counts["rows"] += 1
        where = shops(row, stocked)
        if not where:
            continue
        counts["at a supermarket"] += 1
        code = row.get("code") or ""
        name = name_of(row)
        if not re.fullmatch(r"\d{8,14}", code) or not name:
            counts["no usable name or barcode"] += 1
            continue
        try:
            changed = datetime.fromtimestamp(int(row.get("last_modified_t") or 0), timezone.utc).year
        except ValueError:
            changed = 0
        if changed < OLDEST:
            counts["too old"] += 1
            continue
        cat = kind(row, name)
        if not cat:
            counts["not a ready meal or snack"] += 1
            continue
        per100 = figures(row)
        if not per100:
            counts["figures missing or don't add up"] += 1
            continue
        serve = serving(row, cat)
        if not serve:
            counts["no serving size"] += 1
            continue
        grams, words = serve
        share = grams / 100
        if cat == "main" and (grams < MEAL_GRAMS or per100[0] * share / 4.184 < MEAL_CAL):
            counts["too small for a meal"] += 1
            continue
        if cat == "main" and per100[0] > (SOUP_KJ if re.search(r"\bsoup\b", name, re.I) else BAKED_KJ if BAKED.search(name) else MEAL_KJ):
            counts["figures missing or don't add up"] += 1
            continue
        if cat == "snack" and DRY_SNACK.search(row.get("categories_tags") or "") and per100[0] < DRY_SNACK_KJ:
            counts["figures missing or don't add up"] += 1
            continue
        if re.search(r"yogh?urt", name, re.I) and (per100[0] > YOGHURT_KJ or per100[1] > YOGHURT_PROTEIN):
            counts["figures missing or don't add up"] += 1
            continue
        # A snack listed by the 100 g or in mL is a label that gave no real serving, or a drink.
        if cat == "snack" and ("mL" in words or (grams == 100 and not re.search(r"yogh?urt|pudding", name, re.I))):
            counts["no serving size"] += 1
            continue
        kj, protein, carbs, fat = (value * share for value in per100)
        # The app's own check for figures that disagree, so nothing here is flagged once it's in.
        cal = kj / 4.184
        if cal > 40 and abs(protein * 4 + carbs * 4 + fat * 9 - cal) > max(25, cal * 0.15):
            counts["figures missing or don't add up"] += 1
            continue
        nut = {}
        for key, column, scale in (("sat", "saturated-fat_100g", 1), ("sugar", "sugars_100g", 1), ("fibre", "fiber_100g", 1), ("sodium", "sodium_100g", 1000)):
            value = number(row, column)
            if value is not None:
                nut[key] = round(value * share * scale, 1)
        for shop in where:
            duplicate = (shop, name.lower())
            if duplicate in seen:
                counts["same name twice"] += 1
                continue
            seen[duplicate] = True
            food = {"id": f"{shop}:{code}", "chain": shop, "name": name, "cat": cat, "kj": round(kj), "cal": round(kj / 4.184),
                    "p": round(protein, 1), "c": round(carbs, 1), "f": round(fat, 1), "serve": words}
            if nut:
                food["nut"] = nut
            out.append(food)
    return out


def main():
    counts = Counter()
    # A saved file of rows (one JSON object per line) lets the checks be retuned without fetching the export again.
    rows = (json.loads(line) for line in open(sys.argv[1], encoding="utf-8")) if len(sys.argv) > 1 else csv.DictReader(sys.stdin, delimiter="\t", quoting=csv.QUOTE_NONE)
    foods = sorted(foods_from([row for row in rows if australian(row)], counts), key=lambda f: (f["chain"], f["name"].lower()))
    source = ("Label figures from Open Food Facts, entered by volunteers and available under the Open Database License (ODbL). "
              "Includes each supermarket's own brands and other brands seen on its shelves, so a flavour may not be in your store. "
              "Takeawise checks that energy matches the macros, but not every product is listed. Check the pack.")
    chains = [{"id": shop, "name": name, "url": "https://world.openfoodfacts.org/data", "src": source, "how": "Open Food Facts"}
              for shop, name in (("coles", "Coles"), ("woolworths", "Woolworths"))]
    published = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (HERE / "SupermarketFoods.json").write_text(json.dumps({"format": 1, "published": published, "chains": chains, "foods": foods},
                                                           ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    for key, value in counts.most_common():
        print(f"{value:7} {key}")
    print(Counter((f["chain"], f["cat"]) for f in foods))


if __name__ == "__main__":
    main()
