#!/usr/bin/env python3
"""Builds MacroMenu/SurveyFoods.json: thousands of foods as people eat them, from USDA's survey foods (FNDDS).

Source: USDA FoodData Central, Survey (FNDDS), which is public domain (CC0 1.0). Download "Survey (FNDDS), CSV"
from https://fdc.nal.usda.gov/download-datasets and unzip it, then:

    python3 ios/Scripts/survey-foods.py path/to/FoodData_Central_survey_food_csv_2024-10-31

These widen search and photo matching. They are not suggested (Left today and Plan ahead use the curated
GenericFoods.json only), and their meats and allergens are unknown, so dietary needs leave them out.
Foods already in GenericFoods.json (same USDA entry or same name) are skipped, as are baby foods and formula.
"""
import csv, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent / "MacroMenu"
# Nutrient numbers this export uses, to the keys the app uses. 208 energy (kcal), 203 protein, 205 carbs, 204 fat.
NUMBERS = {"208": "cal", "203": "p", "205": "c", "204": "f", "606": "sat", "269": "sugar", "291": "fibre", "307": "sodium"}
LEFT_OUT = re.compile(r"\b(baby ?food|infant formula|human milk|toddler formula|formula, )", re.I)


def rows(folder, name):
    with open(folder / name, newline="", encoding="utf-8") as handle:
        yield from csv.DictReader(handle)


def unit_rank(description):
    text = description.strip().lower()
    if text.startswith("guideline"):
        return 3
    if re.match(r"1 (fl oz|oz|ounce|tablespoon|teaspoon|tbsp|tsp)\b", text):
        return 2
    return 1 if text.startswith("1 cup") else 0


def tidy(description):
    """USDA's name, minus "NFS" (not further specified), which means nothing to someone logging."""
    return re.sub(r",? NFS\b", "", description).strip()


def main(folder):
    curated = json.loads((HERE / "GenericFoods.json").read_text(encoding="utf-8"))
    taken_ids = {f["id"] for f in curated}
    taken_names = {f["name"].lower() for f in curated}

    foods = {r["fdc_id"]: r["description"] for r in rows(folder, "food.csv") if not LEFT_OUT.search(r["description"])}
    figures = {}
    for row in rows(folder, "food_nutrient.csv"):
        key = NUMBERS.get(row["nutrient_id"])
        if key and row["fdc_id"] in foods:
            figures.setdefault(row["fdc_id"], {})[key] = float(row["amount"])
    portions = {}
    for row in rows(folder, "food_portion.csv"):
        if row["fdc_id"] in foods and row["portion_description"].strip() != "Quantity not specified" and float(row["gram_weight"] or 0) > 0:
            portions.setdefault(row["fdc_id"], []).append(row)

    out, names = [], set()
    for fdc, description in foods.items():
        name = tidy(description)
        per100 = figures.get(fdc, {})
        if f"usda-{fdc}" in taken_ids or name.lower() in taken_names or name.lower() in names:
            continue
        if "cal" not in per100 or "p" not in per100:
            continue
        # A natural serving first (a drumstick, a slice, a mug), then a cup, then fluid ounces and spoons; 100 g when there's none.
        listed = sorted(portions.get(fdc, []), key=lambda p: (unit_rank(p["portion_description"]), int(p["seq_num"] or 0)))
        if listed:
            grams = float(listed[0]["gram_weight"])
            label = tidy(re.sub(r",? any size", "", listed[0]["portion_description"].strip()))
            serve = f"{label} ({grams:g} g)"
        else:
            grams, serve = 100.0, "100 g"
        scale = grams / 100

        def scaled(key):
            return None if key not in per100 else round(per100[key] * scale, 1)

        cal = scaled("cal")
        food = {"id": f"usda-{fdc}", "chain": "generic", "name": name, "cat": "food", "kj": round(cal * 4.184, 1),
                "cal": cal, "p": scaled("p"), "c": scaled("c"), "f": scaled("f"), "serve": serve,
                "diet": {"src": "usda"}}
        extras = {k: scaled(k) for k in ("sat", "sugar", "fibre", "sodium") if scaled(k) is not None}
        if extras:
            food["nut"] = extras
        out.append(food)
        names.add(name.lower())

    out.sort(key=lambda f: f["name"].lower())
    target = HERE / "SurveyFoods.json"
    target.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {len(out)} survey foods to {target} ({target.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
