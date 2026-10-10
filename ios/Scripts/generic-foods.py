#!/usr/bin/env python3
"""Builds MacroMenu/GenericFoods.json: everyday foods (bananas, chicken breast, rice...) from USDA FoodData Central.

Source: USDA FoodData Central, SR Legacy (April 2018), which is public domain (CC0 1.0).
Download "SR Legacy, CSV" from https://fdc.nal.usda.gov/download-datasets and unzip it, then:

    python3 ios/Scripts/generic-foods.py path/to/FoodData_Central_sr_legacy_food_csv_2018-04

Each food below names one USDA entry exactly, so the build fails rather than guessing if an entry
is missing or ambiguous. Figures are scaled from USDA's per-100 g values to the serving shown.
"""
import csv, json, re, sys
from pathlib import Path

SUFFIX = " (Includes foods for USDA's Food Distribution Program)"

# (name in the app, USDA description, serving: a USDA portion to use or None for 100 g, category)
FOODS = [
    # Fruit
    ("Banana", "Bananas, raw", "medium (7\" to 7-7/8\" long)", "food"),
    ("Apple", "Apples, raw, with skin", "medium (3\" dia)", "food"),
    ("Orange", "Oranges, raw, all commercial varieties", "fruit (2-5/8\" dia)", "food"),
    ("Mandarin", "Tangerines, (mandarin oranges), raw", "medium (2-1/2\" dia)", "food"),
    ("Pear", "Pears, raw", "medium", "food"),
    ("Strawberries", "Strawberries, raw", None, "food"),
    ("Blueberries", "Blueberries, raw", None, "food"),
    ("Raspberries", "Raspberries, raw", None, "food"),
    ("Grapes", "Grapes, red or green (European type, such as Thompson seedless), raw", None, "food"),
    ("Watermelon", "Watermelon, raw", None, "food"),
    ("Rockmelon", "Melons, cantaloupe, raw", None, "food"),
    ("Pineapple", "Pineapple, raw, all varieties", None, "food"),
    ("Mango", "Mangos, raw", None, "food"),
    ("Avocado", "Avocados, raw, all commercial varieties", None, "food"),
    ("Kiwifruit", "Kiwifruit, green, raw", "fruit (2\" dia)", "food"),
    ("Peach", "Peaches, yellow, raw", "medium (2-2/3\" dia)", "food"),
    ("Plum", "Plums, raw", "fruit (2-1/8\" dia)", "food"),
    ("Cherries", "Cherries, sweet, raw", None, "food"),
    ("Lemon", "Lemons, raw, without peel", "fruit (2-1/8\" dia)", "food"),
    ("Medjool dates", "Dates, medjool", "date, pitted", "food"),
    ("Sultanas", "Raisins, golden, seedless", None, "food"),

    # Vegetables
    ("Broccoli, raw", "Broccoli, raw", None, "food"),
    ("Broccoli, boiled", "Broccoli, cooked, boiled, drained, without salt", None, "food"),
    ("Carrot, raw", "Carrots, raw", "medium", "food"),
    ("Carrot, boiled", "Carrots, cooked, boiled, drained, without salt", None, "food"),
    ("Spinach, raw", "Spinach, raw", None, "food"),
    ("Spinach, boiled", "Spinach, cooked, boiled, drained, without salt", None, "food"),
    ("Cos lettuce", "Lettuce, cos or romaine, raw", None, "food"),
    ("Iceberg lettuce", "Lettuce, iceberg (includes crisphead types), raw", None, "food"),
    ("Tomato", "Tomatoes, red, ripe, raw, year round average", "medium whole (2-3/5\" dia)", "food"),
    ("Cucumber", "Cucumber, with peel, raw", None, "food"),
    ("Onion", "Onions, raw", "medium (2-1/2\" dia)", "food"),
    ("Red capsicum", "Peppers, sweet, red, raw", "medium (approx 2-3/4\" long, 2-1/2 dia.)", "food"),
    ("Green capsicum", "Peppers, sweet, green, raw", "medium (approx 2-3/4\" long, 2-1/2\" dia)", "food"),
    ("Mushrooms", "Mushrooms, white, raw", None, "food"),
    ("Corn, cooked", "Corn, sweet, yellow, cooked, boiled, drained, without salt", None, "food"),
    ("Peas, cooked", "Peas, green, frozen, cooked, boiled, drained, without salt", None, "food"),
    ("Green beans, raw", "Beans, snap, green, raw", None, "food"),
    ("Green beans, boiled", "Beans, snap, green, cooked, boiled, drained, without salt", None, "food"),
    ("Cauliflower, raw", "Cauliflower, raw", None, "food"),
    ("Cauliflower, boiled", "Cauliflower, cooked, boiled, drained, without salt", None, "food"),
    ("Zucchini", "Squash, summer, zucchini, includes skin, raw", None, "food"),
    ("Cabbage", "Cabbage, raw", None, "food"),
    ("Pumpkin, boiled", "Pumpkin, cooked, boiled, drained, without salt", None, "food"),
    ("Asparagus", "Asparagus, raw", None, "food"),
    ("Kale", "Kale, raw", None, "food"),
    ("Celery", "Celery, raw", None, "food"),
    ("Beetroot", "Beets, raw", None, "food"),
    ("Eggplant", "Eggplant, raw", None, "food"),
    ("Garlic", "Garlic, raw", "clove", "food"),
    ("Potato, raw", "Potatoes, flesh and skin, raw", None, "food"),
    ("Potato, baked", "Potatoes, baked, flesh and skin, without salt", None, "food"),
    ("Mashed potato", "Potatoes, mashed, home-prepared, whole milk and butter added", None, "food"),
    ("Sweet potato, raw", "Sweet potato, raw, unprepared", None, "food"),
    ("Sweet potato, baked", "Sweet potato, cooked, baked in skin, flesh, without salt", None, "food"),

    # Meat, chicken and seafood
    ("Chicken breast, raw", "Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw", None, "food"),
    ("Chicken breast, cooked", "Chicken, broilers or fryers, breast, meat only, cooked, roasted", None, "food"),
    ("Chicken thigh, raw", "Chicken, broilers or fryers, dark meat, thigh, meat only, raw", None, "food"),
    ("Chicken thigh, cooked", "Chicken, broilers or fryers, thigh, meat only, cooked, roasted", None, "food"),
    ("Chicken drumstick, cooked", "Chicken, broilers or fryers, dark meat, drumstick, meat only, cooked, roasted", None, "food"),
    ("Chicken wings, cooked", "Chicken, broilers or fryers, wing, meat and skin, cooked, roasted", None, "food"),
    ("Chicken mince, raw", "Chicken, ground, raw", None, "food"),
    ("Turkey breast, cooked", "Turkey, whole, breast, meat only, cooked, roasted", None, "food"),
    ("Turkey mince, raw", "Turkey, Ground, raw", None, "food"),
    ("Beef mince, 5% fat, raw", "Beef, ground, 95% lean meat / 5% fat, raw", None, "food"),
    ("Beef mince, 10% fat, raw", "Beef, ground, 90% lean meat / 10% fat, raw", None, "food"),
    ("Beef mince, 15% fat, raw", "Beef, ground, 85% lean meat / 15% fat, raw", None, "food"),
    ("Beef mince, 10% fat, cooked", "Beef, ground, 90% lean meat / 10% fat, crumbles, cooked, pan-browned", None, "food"),
    ("Beef patty, 15% fat, cooked", "Beef, ground, 85% lean meat / 15% fat, patty, cooked, broiled", None, "food"),
    ("Sirloin steak, lean, raw", "Beef, top sirloin, steak, separable lean only, trimmed to 1/8\" fat, all grades, raw", None, "food"),
    ("Sirloin steak, lean, cooked", "Beef, top sirloin, steak, separable lean only, trimmed to 1/8\" fat, all grades, cooked, broiled", None, "food"),
    ("Pork tenderloin, raw", "Pork, fresh, loin, tenderloin, separable lean only, raw", None, "food"),
    ("Pork tenderloin, cooked", "Pork, fresh, loin, tenderloin, separable lean only, cooked, roasted", None, "food"),
    ("Bacon, cooked", "Pork, cured, bacon, cooked, baked", "slice cooked", "food"),
    ("Ham, lean", "Pork, cured, ham, boneless, extra lean (approximately 5% fat), roasted", None, "food"),
    ("Lamb loin, lean, cooked", "Lamb, loin, separable lean only, trimmed to 1/4\" fat, choice, cooked, broiled", None, "food"),
    ("Lamb mince, raw", "Lamb, ground, raw", None, "food"),
    ("Salmon, raw", "Fish, salmon, Atlantic, farmed, raw", None, "food"),
    ("Salmon, cooked", "Fish, salmon, Atlantic, farmed, cooked, dry heat", None, "food"),
    ("Tuna in springwater, drained", "Fish, tuna, light, canned in water, drained solids", None, "food"),
    ("White fish (cod), cooked", "Fish, cod, Atlantic, cooked, dry heat", None, "food"),
    ("Tilapia, cooked", "Fish, tilapia, cooked, dry heat", None, "food"),
    ("Prawns, cooked", "Crustaceans, shrimp, cooked", None, "food"),

    # Eggs, dairy and alternatives
    ("Egg", "Egg, whole, raw, fresh", "large", "food"),
    ("Egg, boiled", "Egg, whole, cooked, hard-boiled", "large", "food"),
    ("Egg, scrambled", "Egg, whole, cooked, scrambled", "large", "food"),
    ("Egg, fried", "Egg, whole, cooked, fried", "large", "food"),
    ("Egg white", "Egg, white, raw, fresh", "large", "food"),
    ("Milk, full cream", "Milk, whole, 3.25% milkfat, with added vitamin D", "cup", "drink"),
    ("Milk, reduced fat", "Milk, reduced fat, fluid, 2% milkfat, with added vitamin A and vitamin D", "cup", "drink"),
    ("Milk, skim", "Milk, nonfat, fluid, with added vitamin A and vitamin D (fat free or skim)", "cup", "drink"),
    ("Soy milk", "Soymilk, original and vanilla, with added calcium, vitamins A and D", "cup", "drink"),
    ("Almond milk, unsweetened", "Beverages, almond milk, unsweetened, shelf stable", "cup", "drink"),
    ("Greek yoghurt, plain, no fat", "Yogurt, Greek, plain, nonfat", None, "food"),
    ("Greek yoghurt, plain", "Yogurt, Greek, plain, whole milk", None, "food"),
    ("Yoghurt, plain, low fat", "Yogurt, plain, low fat", None, "food"),
    ("Cheddar cheese", "Cheese, cheddar", "slice (1 oz)", "food"),
    ("Mozzarella", "Cheese, mozzarella, part skim milk", None, "food"),
    ("Cottage cheese, low fat", "Cheese, cottage, lowfat, 2% milkfat", None, "food"),
    ("Feta", "Cheese, feta", None, "food"),
    ("Parmesan, grated", "Cheese, parmesan, grated", "tbsp", "food"),
    ("Cream cheese", "Cheese, cream", "tbsp", "food"),
    ("Butter", "Butter, salted", "tbsp", "food"),
    ("Cream", "Cream, fluid, heavy whipping", "tbsp", "food"),
    ("Sour cream", "Cream, sour, cultured", "tbsp", "food"),
    ("Tofu, firm", "Tofu, raw, firm, prepared with calcium sulfate", None, "food"),
    ("Vanilla ice cream", "Ice creams, vanilla", None, "sweet"),

    # Grains, bread and pasta
    ("White rice, cooked", "Rice, white, long-grain, regular, enriched, cooked", None, "food"),
    ("White rice, uncooked", "Rice, white, long-grain, regular, raw, enriched", None, "food"),
    ("Brown rice, cooked", "Rice, brown, long-grain, cooked", None, "food"),
    ("Brown rice, uncooked", "Rice, brown, long-grain, raw", None, "food"),
    ("Pasta, cooked", "Pasta, cooked, enriched, without added salt", None, "food"),
    ("Pasta, dry", "Pasta, dry, enriched", None, "food"),
    ("Egg noodles, cooked", "Noodles, egg, cooked, enriched, with added salt", None, "food"),
    ("Soba noodles, cooked", "Noodles, japanese, soba, cooked", None, "food"),
    ("Quinoa, cooked", "Quinoa, cooked", None, "food"),
    ("Couscous, cooked", "Couscous, cooked", None, "food"),
    ("Rolled oats", "Cereals, oats, regular and quick, not fortified, dry", None, "breakfast"),
    ("Porridge, made with water", "Cereals, oats, regular and quick, unenriched, cooked with water (includes boiling and microwaving), without salt", None, "breakfast"),
    ("Granola", "Cereals ready-to-eat, granola, homemade", None, "breakfast"),
    ("White bread", "Bread, white, commercially prepared (includes soft bread crumbs)", "slice, large", "food"),
    ("Wholemeal bread", "Bread, whole-wheat, commercially prepared", "slice", "food"),
    ("Pita bread", "Bread, pita, white, enriched", "pita, large (6-1/2\" dia)", "food"),
    ("Wrap, flour tortilla", "Tortillas, ready-to-bake or -fry, flour, shelf stable", "tortilla", "food"),
    ("Bagel, plain", "Bagels, plain, enriched, with calcium propionate (includes onion, poppy, sesame)", "medium bagel (3-1/2\" to 4\" dia)", "breakfast"),
    ("Croissant", "Croissants, butter", "croissant, medium", "breakfast"),
    ("Pancakes", "Pancakes, plain, prepared from recipe", "pancake (6\" dia)", "breakfast"),

    # Beans, nuts and seeds
    ("Black beans, cooked", "Beans, black, mature seeds, cooked, boiled, without salt", None, "food"),
    ("Kidney beans, canned", "Beans, kidney, red, mature seeds, canned, drained solids", None, "food"),
    ("Chickpeas, canned", "Chickpeas (garbanzo beans, bengal gram), mature seeds, canned, drained solids", None, "food"),
    ("Lentils, cooked", "Lentils, mature seeds, cooked, boiled, without salt", None, "food"),
    ("Baked beans", "Beans, baked, canned, plain or vegetarian", None, "food"),
    ("Edamame", "Edamame, frozen, prepared", None, "food"),
    ("Hummus", "Hummus, commercial", "tbsp", "food"),
    ("Almonds", "Nuts, almonds", "oz (23 whole kernels)", "food"),
    ("Cashews", "Nuts, cashew nuts, raw", "oz", "food"),
    ("Walnuts", "Nuts, walnuts, english", "oz (14 halves)", "food"),
    ("Peanuts, roasted", "Peanuts, all types, dry-roasted, without salt", "oz", "food"),
    ("Peanut butter", "Peanut butter, smooth style, without salt", "tbsp", "food"),
    ("Almond butter", "Nuts, almond butter, plain, without salt added", "tbsp", "food"),
    ("Chia seeds", "Seeds, chia seeds, dried", None, "food"),
    ("Pumpkin seeds", "Seeds, pumpkin and squash seed kernels, dried", None, "food"),

    # Oils, spreads and sauces
    ("Olive oil", "Oil, olive, salad or cooking", "tablespoon", "extra"),
    ("Canola oil", "Oil, canola", "tbsp", "extra"),
    ("Coconut oil", "Oil, coconut", "tbsp", "extra"),
    ("Mayonnaise", "Salad dressing, mayonnaise, regular", "tbsp", "extra"),
    ("Honey", "Honey", "tbsp", "extra"),
    ("Sugar", "Sugars, granulated", "tsp", "extra"),
    ("Jam", "Jams and preserves", "tbsp", "extra"),
    ("Maple syrup", "Syrups, maple", "tbsp", "extra"),
    ("Tomato sauce (ketchup)", "Catsup", "tbsp", "extra"),
    ("Pasta sauce", "Sauce, pasta, spaghetti/marinara, ready-to-serve", None, "extra"),
    ("Soy sauce", "Soy sauce made from soy and wheat (shoyu)", "tbsp", "extra"),
    ("Mustard", "Mustard, prepared, yellow", "tsp or 1 packet", "extra"),
    ("Yeast extract spread", "Yeast extract spread", "tsp", "extra"),

    # Drinks
    ("Orange juice", "Orange juice, raw", "cup", "drink"),
    ("Apple juice", "Apple juice, canned or bottled, unsweetened, without added ascorbic acid", "cup", "drink"),
    ("Black coffee", "Beverages, coffee, brewed, prepared with tap water", "cup (8 fl oz)", "drink"),
    ("Black tea", "Beverages, tea, black, brewed, prepared with tap water", "cup (8 fl oz)", "drink"),
    ("Cola", "Beverages, carbonated, cola, regular", None, "drink"),
    ("Beer", "Alcoholic beverage, beer, regular, all", None, "drink"),
    ("Red wine", "Alcoholic beverage, wine, table, red", None, "drink"),
    ("White wine", "Alcoholic beverage, wine, table, white", None, "drink"),
    ("Whey protein powder", "Beverages, Protein powder whey based", None, "drink"),

    # Snacks and sweets
    ("Popcorn, air-popped", "Snacks, popcorn, air-popped", "cup", "sweet"),
    ("Potato chips", "Snacks, potato chips, plain, salted", None, "sweet"),
    ("Pretzels", "Snacks, pretzels, hard, plain, salted", "oz", "sweet"),
    ("Milk chocolate", "Candies, milk chocolate", None, "sweet"),
    ("Dark chocolate, 70-85%", "Chocolate, dark, 70-85% cacao solids", None, "sweet"),
    ("Chocolate chip cookie", "Cookies, chocolate chip, commercially prepared, regular, higher fat, enriched", "cookie, medium (2-1/4\" dia)", "sweet"),
    ("Blueberry muffin", "Muffins, blueberry, commercially prepared (Includes mini-muffins)", "medium", "sweet"),
]

# USDA nutrient ids.
ENERGY_KCAL, ENERGY_KJ, PROTEIN, FAT, CARBS = "1008", "1062", "1003", "1004", "1005"
EXTRAS = {"sat": "1258", "sugar": "2000", "fibre": "1079", "sodium": "1093"}


def rows(folder, name):
    with open(folder / name, newline="", encoding="utf-8") as handle:
        yield from csv.DictReader(handle)


def number(value):
    return float(value) if value not in ("", None) else None


def main(folder):
    by_description = {}
    for food in rows(folder, "food.csv"):
        key = food["description"].removesuffix(SUFFIX)
        by_description.setdefault(key, []).append(food["fdc_id"])
    picked, problems = {}, []
    for name, description, _, _ in FOODS:
        ids = by_description.get(description, [])
        if len(ids) != 1:
            near = [d for d in by_description if d.lower().startswith(description.lower()[:20])][:5]
            problems.append(f"{name}: {len(ids)} matches for {description!r}; near: {near}")
        else:
            picked[ids[0]] = name
    if problems:
        sys.exit("\n".join(problems))

    nutrients = {}
    for row in rows(folder, "food_nutrient.csv"):
        if row["fdc_id"] in picked:
            nutrients.setdefault(row["fdc_id"], {})[row["nutrient_id"]] = float(row["amount"])
    portions = {}
    for row in rows(folder, "food_portion.csv"):
        if row["fdc_id"] in picked:
            portions.setdefault(row["fdc_id"], []).append(row)

    foods, problems = [], []
    for name, description, serving, category in FOODS:
        fdc = by_description[description][0]
        per100 = nutrients.get(fdc, {})
        kcal, protein = per100.get(ENERGY_KCAL), per100.get(PROTEIN)
        if kcal is None or protein is None:
            problems.append(f"{name}: no energy or protein")
            continue
        grams, serve = 100.0, "100 g"
        if serving:
            match = [p for p in portions.get(fdc, []) if p["modifier"].strip() == serving]
            if len(match) != 1:
                options = [p["modifier"] for p in portions.get(fdc, [])]
                problems.append(f"{name}: portion {serving!r} not found once; options: {options}")
                continue
            portion = match[0]
            grams = float(portion["gram_weight"])
            amount = float(portion["amount"])
            count = f"{amount:g}" if amount != 0.5 else "½"
            label = re.sub(r"\s*\(.*?\)", "", serving).strip().replace("tablespoon", "tbsp")
            serve = f"{count} {label} ({grams:g} g)"
        scale = grams / 100

        def scaled(key):
            value = per100.get(key)
            return None if value is None else round(value * scale, 1)

        cal = round(kcal * scale, 1)
        kj = round(per100[ENERGY_KJ] * scale, 1) if ENERGY_KJ in per100 else round(cal * 4.184, 1)
        food = {
            "id": f"usda-{fdc}", "chain": "generic", "name": name, "cat": category,
            "kj": kj, "cal": cal, "p": scaled(PROTEIN), "c": scaled(CARBS), "f": scaled(FAT), "serve": serve,
        }
        extras = {key: scaled(nid) for key, nid in EXTRAS.items() if scaled(nid) is not None}
        if extras:
            food["nut"] = extras
        foods.append(food)
    if problems:
        sys.exit("\n".join(problems))
    names = [f["name"] for f in foods]
    assert len(set(names)) == len(names), "duplicate names"

    out = Path(__file__).resolve().parent.parent / "MacroMenu" / "GenericFoods.json"
    out.write_text(json.dumps(foods, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Wrote {len(foods)} foods to {out}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
