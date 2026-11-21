#!/usr/bin/env python3
"""Builds MacroMenu/SupermarketFoods.json (Australia: Coles and Woolworths) and SupermarketFoods-XX.json for the other countries in
SHOPS below: ready meals and snacks sold at each country's big supermarkets, from Open Food Facts.

Source: the Open Food Facts CSV export (https://world.openfoodfacts.org/data), under the Open Database License (ODbL).
The result is a derived database, so it stays under the ODbL and must stay public: it lives in this repo for that reason.
Coles and Woolworths don't allow their own sites to be collected from (Woolworths bars any robot or retrieval tool, and Coles
allows personal, non-commercial use only), so don't swap this for their product pages or APIs.

    curl -sL https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz | gunzip -c \\
        | python3 ios/Scripts/supermarket-foods.py [COUNTRY]

COUNTRY is AU (the default), NZ, US, CA, GB, ZA, IN or SG. With a saved file of rows (one JSON object per line) in place of the
export: `python3 ios/Scripts/supermarket-foods.py rows.jsonl GB`. Countries with more products than CAP keep the most-scanned.

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

OLDEST = 2019   # older entries are too likely to be a recipe that has since changed


def shop(id, name, brands, stores):
    """A supermarket: its own brands (matched at the start of the brand) and how entries name the store."""
    return {"id": id, "name": name, "own": re.compile(rf"^({brands})", re.I), "tag": re.compile(rf"\b({stores})", re.I)}


# Per country: the Open Food Facts country tag; countries whose products share a store or brand name, so their entries only
# count with this country's barcode prefix; the supermarkets; brands that belong to shops not listed; and the most rows kept.
SHOPS = {
    "AU": {"tag": "australia", "elsewhere": r"south[- ]africa|new[- ]zealand", "prefix": ("93", "94"), "file": "SupermarketFoods.json", "cap": None,
           # Woolworths is also a South African chain, with its own products.
           "shops": [shop("coles", "Coles", r"coles\b", r"coles\b(?! express)"),
                     shop("woolworths", "Woolworths", r"woolworths\b|macro$|macro organic\b|macro wholefoods\b", r"woolworths\b|woolies\b")],
           "other": r"aldi|iga|costco|kirkland|harris farm|black (&|and) gold|community co|home ?brand"},
    # Woolworths NZ (Countdown until 2023) shares its name and Macro brand with Australia's Woolworths.
    "NZ": {"tag": "new-zealand", "elsewhere": r"australia", "prefix": ("94",), "file": "SupermarketFoods-NZ.json", "cap": None,
           "shops": [shop("nz-woolworths", "Woolworths", r"countdown\b|woolworths\b|essentials\b|macro\b", r"woolworths\b|countdown\b"),
                     shop("nz-newworld", "New World", r"pams\b|value\b", r"new world\b"),
                     shop("nz-paknsave", "PAK'nSAVE", r"pams\b|value\b", r"pak ?'?n'? ?'?save\b|pak n save\b")],
           "other": r"coles|aldi|iga|four square|fresh ?choice|the warehouse"},
    "US": {"tag": "united-states", "elsewhere": None, "prefix": (), "file": "SupermarketFoods-US.json", "cap": 5000,
           "shops": [shop("us-walmart", "Walmart", r"great value\b|marketside\b|freshness guaranteed\b|sam'?s choice\b|bettergoods\b", r"walmart\b|wal-mart\b"),
                     shop("us-target", "Target", r"good (&|and) gather\b|market pantry\b|favorite day\b", r"target\b"),
                     shop("us-kroger", "Kroger", r"kroger\b|private selection\b|simple truth\b|home chef\b|heritage farm\b", r"kroger\b|ralphs\b|fred meyer\b|king soopers\b|smith'?s\b|fry'?s\b|harris teeter\b"),
                     shop("us-costco", "Costco", r"kirkland\b", r"costco\b"),
                     shop("us-traderjoes", "Trader Joe's", r"trader joe'?s\b", r"trader joe'?s\b"),
                     shop("us-wholefoods", "Whole Foods Market", r"365\b|whole foods\b", r"whole foods\b"),
                     shop("us-aldi", "Aldi", r"clancy'?s\b|simply nature\b|millville\b|specially selected\b|mama cozzi'?s\b|happy farms\b|l'?oven fresh\b|fit (&|and) active\b|savoritz\b|southern grove\b|appleton farms\b|season'?s choice\b|park street deli\b|earth grown\b|bremer\b|kirkwood\b", r"aldi\b"),
                     shop("us-meijer", "Meijer", r"meijer\b|true goodness\b|frederik'?s\b", r"meijer\b"),
                     shop("us-heb", "H-E-B", r"h-?e-?b\b|hill country fare\b|central market\b|meal simple\b", r"h-?e-?b\b|central market\b")],
           "other": r"wegmans|giant eagle|safeway|signature (select|cafe)|o organics|publix|food lion|hy-?vee|winco|shoprite|bowl & basket|market basket"},
    "CA": {"tag": "canada", "elsewhere": None, "prefix": (), "file": "SupermarketFoods-CA.json", "cap": 4000,
           "shops": [shop("ca-loblaws", "Loblaws", r"president'?s choice\b|pc\b|no name\b", r"loblaws\b|real canadian superstore\b|superstore\b|no frills\b|zehrs\b|maxi\b|provigo\b|fortinos\b|independent\b|valu-mart\b"),
                     shop("ca-sobeys", "Sobeys", r"compliments\b", r"sobeys\b|safeway\b|iga\b|foodland\b|freshco\b|thrifty foods\b|urban fare\b"),
                     shop("ca-metro", "Metro", r"irresistibles?\b|selection\b", r"m[ée]tro\b|food basics\b|super c\b"),
                     shop("ca-walmart", "Walmart", r"great value\b|our finest\b|equate\b", r"walmart\b"),
                     shop("ca-costco", "Costco", r"kirkland\b", r"costco\b")],
           "other": r"western family|save-on|choices|co-op gold|our compliments|dollarama"},
    "GB": {"tag": "united-kingdom", "elsewhere": None, "prefix": (), "file": "SupermarketFoods-GB.json", "cap": 5000,
           "shops": [shop("uk-tesco", "Tesco", r"tesco\b|stockwell\b|hearty food co\b|ms molly'?s\b|grower'?s harvest\b|eastman'?s\b|woodside farms\b|creamfields\b|redmere farms\b|plant chef\b|wicked kitchen\b", r"tesco\b"),
                     shop("uk-sainsburys", "Sainsbury's", r"(by )?sainsbury'?s\b|taste the difference\b|hubbub\b|stamford street\b|j\.? james\b", r"sainsbury'?s\b|sainsburys\b|sainsbury’s\b"),
                     shop("uk-asda", "Asda", r"asda\b|extra special\b|just essentials\b|smart price\b|good (&|and) balanced\b", r"asda\b"),
                     shop("uk-morrisons", "Morrisons", r"morrisons\b|the best\b|nutmeg\b", r"morrisons\b"),
                     shop("uk-waitrose", "Waitrose", r"(essential )?waitrose\b|duchy\b|no\.? ?1 waitrose\b", r"waitrose\b"),
                     shop("uk-ms", "M&S", r"marks (&|and) spencer\b|m ?& ?s\b|count on us\b|percy pig\b|eat well\b", r"marks (&|and) spencer\b|m ?& ?s\b"),
                     shop("uk-aldi", "Aldi", r"aldi\b|specially selected\b|snackrite\b|harvest morn\b|dairyfine\b|everyday essentials\b|village bakery\b|cowbelle\b|holly lane\b|the fishmonger\b|ashfield farm\b|brooklea\b|moser roth\b|choceur\b|bramwells\b|crestwood\b|inspired cuisine\b|the deli\b|worldwide foods\b|grandessa\b|nature'?s pick\b|mamia\b|dairy ?fine\b|oaklands\b", r"aldi\b"),
                     shop("uk-lidl", "Lidl", r"lidl\b|deluxe\b|snaktastic\b|crownfield\b|milbona\b|chef select\b|combino\b|fin carr[ée]\b|freeway\b|harvest basket\b|vitasia\b|alesto\b|batts\b|birchwood\b|dulano\b|mcennedy\b|solevita\b|trattoria alfredo\b|ocean sea\b|vemondo\b|crusti croc\b|snack ?day\b|rowan hill\b|italiamo\b|eridanous\b|sondey\b|baresa\b|pilos\b", r"lidl\b"),
                     shop("uk-coop", "Co-op", r"co-?op\b|the co-operative\b", r"co-?op\b|co-operative\b")],
           "other": r"iceland|ocado|booths|spar|dunnes|costco|kirkland|amazon|heron|farmfoods|b ?& ?m|home bargains"},
    # Woolworths South Africa shares its name with the Australian and New Zealand chains, so its own brand needs a South African barcode.
    "ZA": {"tag": "south-africa", "elsewhere": r"australia|new-zealand|united-kingdom", "prefix": ("60",), "file": "SupermarketFoods-ZA.json", "cap": None,
           "shops": [shop("za-woolworths", "Woolworths", r"woolworths\b|ww\b", r"woolworths\b"),
                     shop("za-pnp", "Pick n Pay", r"pick ?n ?pay\b|pnp\b", r"pick ?n ?pay\b|pnp\b"),
                     shop("za-checkers", "Checkers", r"checkers\b|housebrand\b|ritebrand\b|simple truth\b|forage (&|and) feast\b", r"checkers\b|shoprite\b"),
                     shop("za-spar", "Spar", r"spar\b|freshline\b", r"spar\b")],
           "other": r"makro|clicks|dis-?chem|game\b"},
}
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


# Brands that tidy() would recase wrongly.
CASING = {"M&s": "M&S", "M & s": "M&S", "H-e-b": "H-E-B", "Heb": "H-E-B", "Pnp": "PnP", "Ww": "WW", "Pc": "PC"}


def name_of(row):
    name = tidy(row.get("product_name"))
    if not name or len(name) < 4 or len(name) > 70 or re.search(r"[^\x00-\x7f’–]", name):
        return None
    brand = tidy((row.get("brands") or "").split(",")[0])
    if brand and name.lower() == brand.lower():   # just the brand ("Lindt"): not enough to know the product
        return None
    if brand and len(brand) <= 24 and brand.lower() not in name.lower():
        name = f"{brand} {name}"
    for wrong, right in CASING.items():
        name = re.sub(rf"(?<![\w&]){re.escape(wrong)}(?![\w&])", right, name)
    return name


def sold_in(row, country):
    countries = (row.get("countries_tags") or "") + " " + (row.get("countries_en") or "")
    if country["tag"] not in countries.lower():
        return False
    return not country["elsewhere"] or not re.search(country["elsewhere"], countries, re.I) or (row.get("code") or "").startswith(country["prefix"])


def brand_of(row):
    return tidy((row.get("brands") or "").split(",")[0]).lower().replace("’", "'")


def tagged(row, country):
    """The supermarkets an entry names."""
    stores = (row.get("stores") or "").lower()
    return [s["id"] for s in country["shops"] if s["tag"].search(stores)]


def stocked_brands(rows, country):
    """For each supermarket, the brands enough entries place on its shelves."""
    counts = Counter((shop, brand_of(row)) for row in rows for shop in tagged(row, country))
    return {s["id"]: {brand for (at, brand), count in counts.items() if at == s["id"] and brand and count >= MIN_STOCKED} for s in country["shops"]}


def shops(row, stocked, country):
    brand = brand_of(row)
    own = [s["id"] for s in country["shops"] if s["own"].search(brand)]
    if own:
        return own
    if country["other"] and re.search(rf"^({country['other']})\b", brand, re.I):
        return []
    return sorted(set(tagged(row, country)) | {shop for shop, brands in stocked.items() if brand in brands})


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


def popularity(row):
    try:
        return int(float(row.get("unique_scans_n") or 0))
    except ValueError:
        return 0


def foods_from(rows, counts, country):
    seen, out = {}, []
    stocked = stocked_brands(rows, country)
    # Most-scanned first, so a cap keeps the products people buy, and of two entries with one name the better known wins.
    rows = sorted(rows, key=popularity, reverse=True) if country["cap"] else rows
    for row in rows:
        counts["rows"] += 1
        where = shops(row, stocked, country)
        if not where:
            continue
        counts["at a supermarket"] += 1
        code = row.get("code") or ""
        name = name_of(row)
        # Codes starting with 2 are a shop's own in-store numbers, not a product barcode.
        if not re.fullmatch(r"\d{8,14}", code) or not name or (len(code) == 13 and code.startswith("2")):
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
    if country["cap"] and len(out) > country["cap"]:
        counts["left out past the cap (least scanned)"] += len(out) - country["cap"]
        out = out[:country["cap"]]
    return out


def main():
    counts = Counter()
    args = sys.argv[1:]
    code = args.pop() if args and args[-1].upper() in SHOPS else "AU"
    country = SHOPS[code.upper()]
    # A saved file of rows (one JSON object per line) lets the checks be retuned without fetching the export again.
    rows = (json.loads(line) for line in open(args[0], encoding="utf-8")) if args else csv.DictReader(sys.stdin, delimiter="\t", quoting=csv.QUOTE_NONE)
    foods = sorted(foods_from([row for row in rows if sold_in(row, country)], counts, country), key=lambda f: (f["chain"], f["name"].lower()))
    source = ("Label figures from Open Food Facts, entered by volunteers and available under the Open Database License (ODbL). "
              "Includes each supermarket's own brands and other brands seen on its shelves, so a flavour may not be in your store. "
              "Leanrrr checks that energy matches the macros, but not every product is listed. Check the pack.")
    chains = [{"id": s["id"], "name": s["name"], "url": "https://world.openfoodfacts.org/data", "src": source, "how": "Open Food Facts"}
              for s in country["shops"] if any(f["chain"] == s["id"] for f in foods)]
    published = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (HERE / country["file"]).write_text(json.dumps({"format": 1, "published": published, "chains": chains, "foods": foods},
                                                           ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    for key, value in counts.most_common():
        print(f"{value:7} {key}")
    print(Counter((f["chain"], f["cat"]) for f in foods))


if __name__ == "__main__":
    main()
