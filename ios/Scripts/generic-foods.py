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
    # More everyday foods, added October 2026
    ("Apricot", "Apricots, raw", "apricot", "food"),
    ("Nectarine", "Nectarines, raw", "medium (2-1/2\" dia)", "food"),
    ("Honeydew melon", "Melons, honeydew, raw", None, "food"),
    ("Papaya", "Papayas, raw", None, "food"),
    ("Passionfruit", "Passion-fruit, (granadilla), purple, raw", "fruit without refuse", "food"),
    ("Grapefruit", "Grapefruit, raw, pink and red, all areas", "fruit (3-3/4\" dia)", "food"),
    ("Lime", "Limes, raw", "fruit (2\" dia)", "food"),
    ("Figs, fresh", "Figs, raw", "medium (2-1/4\" dia)", "food"),
    ("Pomegranate", "Pomegranates, raw", "pomegranate (4\" dia)", "food"),
    ("Blackberries", "Blackberries, raw", None, "food"),
    ("Cranberries, dried", "Cranberries, dried, sweetened", "cup", "food"),
    ("Dried apricots", "Apricots, dried, sulfured, uncooked", None, "food"),
    ("Prunes", "Plums, dried (prunes), uncooked", "prune, pitted", "food"),
    ("Coconut, fresh", "Nuts, coconut meat, raw", None, "food"),
    ("Desiccated coconut", "Nuts, coconut meat, dried (desiccated), not sweetened", None, "food"),
    ("Lychees", "Litchis, raw", "fruit without refuse", "food"),
    ("Fruit salad, canned in juice", "Fruit salad, (peach and pear and apricot and pineapple and cherry), canned, juice pack, solids and liquids", None, "food"),
    ("Peaches, canned in juice", "Peaches, canned, juice pack, solids and liquids", "cup", "food"),
    ("Applesauce, unsweetened", "Applesauce, canned, unsweetened, without added ascorbic acid", None, "food"),
    ("Red cabbage", "Cabbage, red, raw", None, "food"),
    ("Bok choy", "Cabbage, chinese (pak-choi), raw", None, "food"),
    ("Brussels sprouts, boiled", "Brussels sprouts, cooked, boiled, drained, without salt", None, "food"),
    ("Snow peas", "Peas, edible-podded, raw", None, "food"),
    ("Bean sprouts", "Mung beans, mature seeds, sprouted, raw", None, "food"),
    ("Leek", "Leeks, (bulb and lower leaf-portion), raw", None, "food"),
    ("Spring onion", "Onions, spring or scallions (includes tops and bulb), raw", "medium (4-1/8\" long)", "food"),
    ("Rocket", "Arugula, raw", None, "food"),
    ("Green leaf lettuce", "Lettuce, green leaf, raw", None, "food"),
    ("Canned tomatoes", "Tomatoes, red, ripe, canned, packed in tomato juice", None, "food"),
    ("Tomato paste", "Tomato products, canned, paste, without salt added", None, "extra"),
    ("Sweet corn, raw", "Corn, sweet, yellow, raw", None, "food"),
    ("Canned corn", "Corn, sweet, yellow, canned, whole kernel, drained solids", None, "food"),
    ("Pumpkin, raw", "Pumpkin, raw", None, "food"),
    ("Butternut pumpkin, baked", "Squash, winter, butternut, cooked, baked, without salt", None, "food"),
    ("Parsnip, boiled", "Parsnips, cooked, boiled, drained, without salt", None, "food"),
    ("Radish", "Radishes, raw", None, "food"),
    ("Silverbeet, boiled", "Chard, swiss, cooked, boiled, drained, without salt", None, "food"),
    ("Ginger", "Ginger root, raw", None, "extra"),
    ("Red chilli", "Peppers, hot chili, red, raw", None, "extra"),
    ("Potato, boiled", "Potatoes, boiled, cooked without skin, flesh, without salt", "medium (2-1/4\" to 3-1/4\" dia.)", "food"),
    ("Oven chips, baked", "Potatoes, french fried, all types, salt not added in processing, frozen, oven-heated", None, "food"),
    ("Mixed vegetables, boiled", "Vegetables, mixed, frozen, cooked, boiled, drained, without salt", None, "food"),
    ("Olives", "Olives, ripe, canned (small-extra large)", "large", "extra"),
    ("Pickles", "Pickles, cucumber, dill or kosher dill", "spear, small", "extra"),
    ("Sauerkraut", "Sauerkraut, canned, solids and liquids", None, "extra"),
    ("Chicken breast, skin on, roasted", "Chicken, broilers or fryers, breast, meat and skin, cooked, roasted", "breast, bone removed", "food"),
    ("Roast chicken, meat and skin", "Chicken, broilers or fryers, meat and skin, cooked, roasted", None, "food"),
    ("Roast chicken, breast meat only", "Chicken, broilers or fryers, light meat, meat only, cooked, roasted", None, "food"),
    ("Chicken, dark meat, roasted", "Chicken, broilers or fryers, dark meat, meat only, cooked, roasted", None, "food"),
    ("Top sirloin (rump) steak, cooked", "Beef, top sirloin, steak, separable lean only, trimmed to 1/8\" fat, choice, cooked, broiled", None, "food"),
    ("Eye fillet, cooked", "Beef, tenderloin, steak, separable lean only, trimmed to 1/8\" fat, all grades, cooked, broiled", None, "food"),
    ("Corned beef", "Beef, cured, corned beef, brisket, cooked", None, "food"),
    ("Beef jerky", "Snacks, beef jerky, chopped and formed", None, "food"),
    ("Pork chop, cooked", "Pork, fresh, loin, center loin (chops), bone-in, separable lean and fat, cooked, broiled", None, "food"),
    ("Pork mince, cooked", "Pork, ground, 84% lean / 16% fat, cooked, pan-broiled", None, "food"),
    ("Pork belly, raw", "Pork, fresh, belly, raw", None, "food"),
    ("Beef sausage, cooked", "Sausage, beef, fresh, cooked", "serving", "food"),
    ("Frankfurt (hot dog), beef", "Frankfurter, beef, unheated", "hot dog", "food"),
    ("Salami", "Salami, Italian, pork", None, "food"),
    ("Turkey slices (deli)", "Turkey breast, sliced, prepackaged", "slice", "food"),
    ("Chicken slices (deli)", "Chicken breast, deli, rotisserie seasoned, sliced, prepackaged", "slice", "food"),
    ("Sea bass, cooked", "Fish, sea bass, mixed species, cooked, dry heat", "fillet", "food"),
    ("Snapper, cooked", "Fish, snapper, mixed species, cooked, dry heat", "fillet", "food"),
    ("Flounder or sole, cooked", "Fish, flatfish (flounder and sole species), cooked, dry heat", "fillet", "food"),
    ("Tuna steak, cooked", "Fish, tuna, yellowfin, fresh, cooked, dry heat", None, "food"),
    ("Tuna in oil, drained", "Fish, tuna, light, canned in oil, drained solids", "can", "food"),
    ("Salmon, canned", "Fish, salmon, pink, canned, total can contents", None, "food"),
    ("Smoked salmon", "Fish, salmon, chinook, smoked", None, "food"),
    ("Sardines in oil", "Fish, sardine, Atlantic, canned in oil, drained solids with bone", None, "food"),
    ("Prawns, raw", "Crustaceans, shrimp, raw", None, "food"),
    ("Crab, cooked", "Crustaceans, crab, blue, cooked, moist heat", None, "food"),
    ("Mussels, cooked", "Mollusks, mussel, blue, cooked, moist heat", None, "food"),
    ("Calamari, fried", "Mollusks, squid, mixed species, cooked, fried", None, "food"),
    ("Oysters, raw", "Mollusks, oyster, Pacific, raw", "medium", "food"),
    ("Scallops, cooked", "Mollusks, scallop, (bay and sea), cooked, steamed", None, "food"),
    ("Fish fingers, baked", "Fish, fish sticks, frozen, prepared", "stick (4\" x 1\" x 1/2\")", "food"),
    ("Yoghurt, vanilla, low fat", "Yogurt, vanilla, low fat.", "container (6 oz)", "breakfast"),
    ("Yoghurt, fruit, low fat", "Yogurt, fruit, low fat,9 g protein/8 oz", None, "breakfast"),
    ("Ricotta", "Cheese, ricotta, part skim milk", None, "food"),
    ("Brie", "Cheese, brie", None, "food"),
    ("Swiss cheese", "Cheese, swiss", "slice (1 oz)", "food"),
    ("Cheddar, reduced fat", "Cheese, cheddar, reduced fat", "slice", "food"),
    ("Processed cheese slice", "Cheese, pasteurized process, American, fortified with vitamin D", "slice (3/4 oz)", "food"),
    ("Evaporated milk", "Milk, canned, evaporated, with added vitamin A", None, "extra"),
    ("Vanilla pudding", "Puddings, vanilla, ready-to-eat", None, "sweet"),
    ("Egg yolk", "Egg, yolk, raw, fresh", "large", "food"),
    ("Omelette", "Egg, whole, cooked, omelet", None, "food"),
    ("Egg, poached", "Egg, whole, cooked, poached", "large", "food"),
    ("Wild rice, cooked", "Wild rice, cooked", None, "food"),
    ("Rice noodles, cooked", "Rice noodles, cooked", None, "food"),
    ("Wholemeal pasta, cooked", "Pasta, whole-wheat, cooked", None, "food"),
    ("Instant noodles, dry", "Soup, ramen noodle, any flavor, dry", "package without flavor packet", "food"),
    ("Sourdough bread", "Bread, french or vienna (includes sourdough)", None, "food"),
    ("Multigrain bread", "Bread, multi-grain (includes whole-grain)", "slice regular", "food"),
    ("Rye bread", "Bread, rye", "slice, regular", "food"),
    ("Raisin toast", "Bread, raisin, enriched", "slice", "breakfast"),
    ("English muffin", "Muffins, English, plain, enriched, with ca prop (includes sourdough)", "muffin", "breakfast"),
    ("Bread roll", "Rolls, hamburger or hotdog, plain", None, "food"),
    ("Corn tortilla", "Tortillas, ready-to-bake or -fry, corn", "tortilla", "food"),
    ("Naan", "Bread, naan, plain, commercially prepared, refrigerated", "piece", "food"),
    ("Rye crispbread", "Crackers, rye, wafers, plain", "cracker (4-1/2\" x 2-1/2\" x 1/8\")", "food"),
    ("Water crackers", "Crackers, water biscuits", None, "food"),
    ("Bran flakes", "Cereals ready-to-eat, POST Bran Flakes", "cup (1 NLEA serving)", "breakfast"),
    ("Plain flour", "Wheat flour, white, all-purpose, enriched, bleached", None, "extra"),
    ("Waffle", "Waffles, plain, frozen, ready -to-heat, toasted", "waffle, round (4\" dia)", "breakfast"),
    ("French toast", "French toast, prepared from recipe, made with low fat (2%) milk", "slice", "breakfast"),
    ("Red lentils, dry", "Lentils, pink or red, raw", None, "food"),
    ("Cannellini beans", "Beans, white, mature seeds, canned", None, "food"),
    ("Butter beans", "Lima beans, large, mature seeds, canned", None, "food"),
    ("Refried beans", "Refried beans, canned, traditional style", None, "food"),
    ("Tempeh", "Tempeh", None, "food"),
    ("Falafel", "Falafel, home-prepared", "patty (approx 2-1/4\" dia)", "food"),
    ("Pistachios", "Nuts, pistachio nuts, dry roasted, without salt added", None, "food"),
    ("Macadamias", "Nuts, macadamia nuts, raw", None, "food"),
    ("Pecans", "Nuts, pecans", None, "food"),
    ("Hazelnuts", "Nuts, hazelnuts or filberts", None, "food"),
    ("Brazil nuts", "Nuts, brazilnuts, dried, unblanched", None, "food"),
    ("Mixed nuts", "Nuts, mixed nuts, dry roasted, with peanuts, without salt added", None, "food"),
    ("Sunflower seeds", "Seeds, sunflower seed kernels, dried", None, "food"),
    ("Flaxseed (linseed)", "Seeds, flaxseed", None, "food"),
    ("Sesame seeds", "Seeds, sesame seeds, whole, dried", None, "food"),
    ("Tahini", "Seeds, sesame butter, tahini, from roasted and toasted kernels (most common type)", "tbsp", "extra"),
    ("Trail mix", "Snacks, trail mix, regular", None, "food"),
    ("Avocado oil", "Oil, avocado", "tbsp", "extra"),
    ("Barbecue sauce", "Sauce, barbecue", "tbsp", "extra"),
    ("Sriracha", "Sauce, hot chile, sriracha", "tsp", "extra"),
    ("Salsa", "Sauce, salsa, ready-to-serve", "tbsp", "extra"),
    ("Pesto", "Sauce, pesto, ready-to-serve, refrigerated", "cup", "extra"),
    ("Caesar dressing", "Salad dressing, caesar dressing, regular", "serving (2 tbsp)", "extra"),
    ("Ranch dressing", "Salad dressing, ranch dressing, regular", "tablespoon", "extra"),
    ("Balsamic vinegar", "Vinegar, balsamic", "tbsp", "extra"),
    ("Teriyaki sauce", "Sauce, teriyaki, ready-to-serve", "tbsp", "extra"),
    ("Oyster sauce", "Sauce, oyster, ready-to-serve", "tbsp", "extra"),
    ("Chocolate hazelnut spread", "Chocolate-flavored hazelnut spread", None, "extra"),
    ("Brown sugar", "Sugars, brown", "tsp packed", "extra"),
    ("Chocolate fudge sauce", "Syrups, chocolate, fudge-type", "tbsp", "extra"),
    ("Espresso", "Beverages, coffee, brewed, espresso, restaurant-prepared", None, "drink"),
    ("Green tea", "Beverages, tea, green, brewed, regular", "cup", "drink"),
    ("Coconut water", "Nuts, coconut water (liquid from coconuts)", "cup", "drink"),
    ("Lemonade (lemon-lime soft drink)", "Beverages, carbonated, lemon-lime soda, no caffeine", "drink (12 fl oz)", "drink"),
    ("Energy drink", "Beverages, Energy drink, RED BULL", "can 8.4 fl oz", "drink"),
    ("Ginger ale", "Beverages, carbonated, ginger ale", "can or bottle (12 fl oz)", "drink"),
    ("Tomato juice", "Tomato juice, canned, with salt added", "cup", "drink"),
    ("Pineapple juice", "Pineapple juice, canned or bottled, unsweetened, without added ascorbic acid", "cup", "drink"),
    ("Light beer", "Alcoholic beverage, beer, light", "can or bottle (12 fl oz)", "drink"),
    ("Vodka, gin or rum", "Alcoholic beverage, distilled, all (gin, rum, vodka, whiskey) 80 proof", "jigger (1.5 fl oz)", "drink"),
    ("Muesli bar, plain", "Snacks, granola bars, soft, uncoated, plain", "bar (1 oz)", "sweet"),
    ("Corn chips", "Snacks, tortilla chips, plain, white corn, salted", None, "sweet"),
    ("Banana bread", "Bread, banana, prepared from recipe, made with margarine", "slice", "sweet"),
    ("Marie biscuit", "Cookies, Marie biscuit", "cookie", "sweet"),
    ("Chocolate cake", "Cake, chocolate, commercially prepared with chocolate frosting, in-store bakery", "piece (1/12 of a cake)", "sweet"),
    ("Cheesecake", "Cake, cheesecake, commercially prepared", "piece (1/6 of 17 oz cake)", "sweet"),
    ("Doughnut", "Doughnuts, cake-type, plain (includes unsugared, old-fashioned)", "doughnut medium (3-1/4\" dia)", "sweet"),
    ("Brownie", "Cookies, brownies, commercially prepared", "square, large (2-3/4\" sq x 7/8\")", "sweet"),
    ("Apple pie", "Pie, apple, commercially prepared, enriched flour", "piece (1/8 of 9\" dia)", "sweet"),
    ("Jelly lollies (gumdrops)", "Candies, gumdrops, starch jelly pieces", None, "sweet"),
    ("Chocolate ice cream", "Ice creams, chocolate", "cup (4 fl oz)", "sweet"),
    ("White chocolate", "Candies, white chocolate", None, "sweet"),
    ("Jelly, made up", "Gelatin desserts, dry mix, prepared with water", "cup", "sweet"),
    ("Rice pudding", "Puddings, rice, ready-to-eat", None, "sweet"),
    ("Cheese pizza, frozen", "Pizza, cheese topping, regular crust, frozen, cooked", None, "food"),
    ("Vegetable lasagne", "Lasagna, Vegetable, frozen, baked", "serving", "food"),
    ("Beef stew, canned", "Beef stew, canned entree", "cup (1 serving)", "food"),
    ("Macaroni and cheese, canned", "Macaroni and Cheese, canned entree", "serving", "food"),
    ("Beef pot pie", "Beef Pot Pie, frozen entree, prepared", "pie, cooked (average weight)", "food"),
    ("Spring roll (vegetable)", "Egg rolls, vegetable, frozen, prepared", "egg roll", "food"),
    ("Bean and cheese burrito, frozen", "Burrito, bean and cheese, frozen", "burrito", "food"),
    # Third batch (October 2026): fast-food style, restaurant dishes, more produce, seafood and drinks
    ("Cheeseburger, single patty", "Fast foods, cheeseburger; single, regular patty, with condiments", "item", "food"),
    ("Hamburger, single patty", "Fast foods, hamburger; single, regular patty; with condiments", "sandwich", "food"),
    ("Double cheeseburger", "Fast foods, cheeseburger; double, regular patty; with condiments", "sandwich", "food"),
    ("Large hamburger", "Fast foods, hamburger, large, single patty, with condiments", "item", "food"),
    ("French fries, takeaway", "Fast foods, potato, french fried in vegetable oil", "serving medium", "food"),
    ("Onion rings, takeaway", "Fast foods, onion rings, breaded and fried", "package (18 onion rings)", "food"),
    ("Chicken tenders, takeaway", "Fast foods, chicken tenders", "strip", "food"),
    ("Fried chicken wing", "Fast Foods, Fried Chicken, Wing, meat and skin and breading", "wing, with skin", "food"),
    ("Fried chicken thigh", "Fast Foods, Fried Chicken, Thigh, meat and skin and breading", "thigh with skin", "food"),
    ("Soft taco, beef", "Fast foods, taco with beef, cheese and lettuce, soft", "each taco", "food"),
    ("Hard taco, beef", "Fast foods, taco with beef, cheese and lettuce, hard shell", "each taco", "food"),
    ("Nachos with cheese", "Fast foods, nachos, with cheese", "serving", "food"),
    ("Cheese quesadilla", "Restaurant, Mexican, cheese quesadilla", "quesadilla 8-10 inch diameter", "food"),
    ("Bean burrito", "Fast foods, burrito, with beans", None, "food"),
    ("Cheese enchilada", "Restaurant, Mexican, cheese enchilada", "1 enchilada", "food"),
    ("Spanish rice", "Restaurant, Mexican, spanish rice", "cup", "food"),
    ("Pepperoni pizza, frozen", "Pizza, pepperoni topping, regular crust, frozen, cooked", None, "food"),
    ("Meat pizza, frozen", "Pizza, meat topping, thick crust, frozen, cooked", "slice 1/8 of 12\" pizza", "food"),
    ("Pizza slice, takeaway cheese", "Fast Food, Pizza Chain, 14\" pizza, cheese topping, thin crust", "slice", "food"),
    ("Ham sub, white bread", "Fast foods, submarine sandwich, ham on white bread with lettuce and tomato", "6 inch sub", "food"),
    ("Roast beef sandwich", "Fast foods, roast beef sandwich, plain", "sandwich", "food"),
    ("Meatball sub", "Fast foods, submarine sandwich, meatball marinara on white bread", "6 inch sub", "food"),
    ("Potato salad", "Potato salad, home-prepared", "cup", "food"),
    ("Coleslaw", "Fast foods, coleslaw", "cup", "food"),
    ("Tuna salad", "Fish, tuna salad", "cup", "food"),
    ("Minestrone soup", "Soup, minestrone, canned, chunky, ready-to-serve", "cup", "food"),
    ("Vegetable soup, chunky", "Soup, chunky vegetable, canned, ready-to-serve", "cup", "food"),
    ("Wonton soup", "Soup, wonton, Chinese restaurant", "cup", "food"),
    ("Fried rice (no meat)", "Restaurant, Chinese, fried rice, without meat", "cup", "food"),
    ("Chicken chow mein", "Restaurant, Chinese, chicken chow mein", "order", "food"),
    ("Sweet and sour pork", "Restaurant, Chinese, sweet and sour pork", "pieces", "food"),
    ("Orange chicken", "Restaurant, Chinese, orange chicken", "pieces", "food"),
    ("Egg rolls", "Restaurant, Chinese, egg rolls, assorted", "piece", "food"),
    ("Spaghetti with meat sauce", "Restaurant, Italian, spaghetti with meat sauce", "serving", "food"),
    ("Lasagne with meat", "Restaurant, Italian, lasagna with meat", "serving", "food"),
    ("Cheese ravioli with marinara", "Restaurant, Italian, cheese ravioli with marinara sauce", None, "food"),
    ("Chicken parmigiana (no pasta)", "Restaurant, Italian, chicken parmesan without pasta", "serving", "food"),
    ("Spaghetti and meatballs", "Restaurant, family style, spaghetti and meatballs", "serving", "food"),
    ("Hash browns", "Potatoes, hash brown, home-prepared", "cup", "breakfast"),
    ("Pork spare ribs, roasted", "Pork, fresh, spareribs, separable lean and fat, cooked, roasted", None, "food"),
    ("Bratwurst, cooked", "Bratwurst, pork, cooked", "link cooked", "food"),
    ("Pepperoni slices", "Pepperoni, beef and pork, sliced", "1 oz", "extra"),
    ("Italian sausage, sweet", "Sausage, Italian, sweet, links", "link 3 oz", "food"),
    ("Beef liver, pan-fried", "Beef, variety meats and by-products, liver, cooked, pan-fried", None, "food"),
    ("Ham, sliced", "Ham, sliced, regular (approximately 11% fat)", "slice", "food"),
    ("Turkey, roasted, meat and skin", "Turkey, whole, meat and skin, cooked, roasted", None, "food"),
    ("Mackerel, raw", "Fish, mackerel, king, raw", None, "food"),
    ("Trout, raw", "Fish, trout, rainbow, farmed, raw", "fillet", "food"),
    ("Swordfish, cooked", "Fish, swordfish, cooked, dry heat", "piece", "food"),
    ("Anchovies in oil", "Fish, anchovy, european, canned in oil, drained solids", "can (2 oz)", "extra"),
    ("Lobster, cooked", "Crustaceans, lobster, northern, cooked, moist heat", None, "food"),
    ("Octopus, cooked", "Mollusks, octopus, common, cooked, moist heat", None, "food"),
    ("Battered fish fillet", "Restaurant, family style, fish fillet, battered or breaded, fried", "serving", "food"),
    ("Crumbed prawns, fried", "Crustaceans, shrimp, mixed species, cooked, breaded and fried", "large", "food"),
    ("Bulgur, cooked", "Bulgur, cooked", "cup", "food"),
    ("Pearl barley, raw", "Barley, pearled, raw", None, "food"),
    ("Millet, raw", "Millet, raw", None, "food"),
    ("Soybeans, boiled", "Soybeans, mature cooked, boiled, without salt", "cup", "food"),
    ("Pinto beans, cooked", "Beans, pinto, mature seeds, cooked, boiled, without salt", "cup", "food"),
    ("Navy beans, cooked", "Beans, navy, mature seeds, cooked, boiled, without salt", "cup", "food"),
    ("Lima beans, cooked", "Lima beans, large, mature seeds, cooked, boiled, without salt", "cup", "food"),
    ("Pine nuts", "Nuts, pine nuts, dried", "oz (167 kernels)", "food"),
    ("Chestnuts, raw", "Nuts, chestnuts, chinese, raw", "1 oz", "food"),
    ("Hemp seeds", "Seeds, hemp seed, hulled", "tbsp", "food"),
    ("Hoisin sauce", "Sauce, hoisin, ready-to-serve", "tbsp", "extra"),
    ("Worcestershire sauce", "Sauce, worcestershire", "tbsp", "extra"),
    ("Horseradish, prepared", "Horseradish, prepared", "tbsp", "extra"),
    ("Apple cider vinegar", "Vinegar, cider", "tbsp", "extra"),
    ("Italian dressing", "Salad dressing, italian dressing, commercial, regular", "tbsp", "extra"),
    ("Thousand island dressing", "Salad dressing, thousand island, commercial, regular", "serving (2 tbsp)", "extra"),
    ("Sesame oil", "Oil, sesame, salad or cooking", "tablespoon", "extra"),
    ("Sunflower oil", "Oil, sunflower, linoleic, (approx. 65%)", "tbsp", "extra"),
    ("Lard", "Lard", "tbsp", "extra"),
    ("Ghee", "Butter oil, anhydrous", "tbsp", "extra"),
    ("Coconut milk, canned", "Nuts, coconut milk, canned (liquid expressed from grated meat and water)", "cup", "extra"),
    ("Marshmallows", "Candies, marshmallows", "miniatures", "sweet"),
    ("Jelly beans", "Candies, jellybeans", "large (1 oz)", "sweet"),
    ("Orange sherbet", "Sherbet, orange", "cup (4 fl oz)", "sweet"),
    ("Lemon meringue pie", "Pie, lemon meringue, commercially prepared", "piece (1/6 of 8\" pie)", "sweet"),
    ("Pumpkin pie", "Pie, pumpkin, prepared from recipe", "piece (1/8 of 9\" dia)", "sweet"),
    ("Pecan pie", "Pie, pecan, commercially prepared", "slice", "sweet"),
    ("Cinnamon danish", "Danish pastry, cinnamon, enriched", "pastry (4-1/4\" dia)", "sweet"),
    ("Oatmeal raisin cookie", "Cookies, oatmeal, with raisins", "cookie", "sweet"),
    ("Shortbread", "Cookies, shortbread, commercially prepared, plain", "cookie", "sweet"),
    ("Chocolate cream sandwich biscuit", "Cookies, chocolate sandwich, with creme filling, regular", "cookie", "sweet"),
    ("Saltine crackers", "Crackers, saltines (includes oyster, soda, soup)", "crackers", "food"),
    ("Pork crackling", "Snacks, pork skins, plain", "1 oz", "sweet"),
    ("Popcorn, oil-popped, salted", "Snacks, popcorn, oil-popped, white popcorn, salt added", "cup", "sweet"),
    ("Banana chips", "Snacks, banana chips", "1 oz", "sweet"),
    ("Pina colada", "Alcoholic beverage, pina colada, prepared-from-recipe", "cocktail (4.5 fl oz)", "drink"),
    ("Daiquiri", "Alcoholic beverage, daiquiri, prepared-from-recipe", "cocktail (2 fl oz)", "drink"),
    ("Chocolate milkshake", "Milk shakes, thick chocolate", "container (10.6 oz)", "drink"),
    ("Vanilla milkshake", "Milk shakes, thick vanilla", "container (11 oz)", "drink"),
    ("Strawberry banana smoothie", "Fast foods, strawberry banana smoothie made with ice and low-fat yogurt", "fl oz", "drink"),
    ("Water", "Beverages, water, tap, drinking", "serving 8 fl oz", "drink"),
    ("Root beer", "Beverages, carbonated, root beer", "can or bottle (12 fl oz)", "drink"),
    ("Tonic water", "Beverages, carbonated, tonic water", "can or bottle (12 fl oz)", "drink"),
    ("Soda water", "Beverages, carbonated, club soda", "can or bottle (12 fl oz)", "drink"),
    ("Rice milk", "Beverages, rice milk, unsweetened", None, "drink"),
    ("Buttermilk", "Milk, buttermilk, fluid, whole", "cup", "drink"),
    ("Cranberry juice cocktail", "Cranberry juice cocktail, bottled", "cup (8 fl oz)", "drink"),
    ("Goat cheese, soft", "Cheese, goat, soft type", "1 oz", "food"),
    ("Camembert", "Cheese, camembert", "wedge (1.33 oz)", "food"),
    ("Provolone", "Cheese, provolone", "slice (1 oz)", "food"),
    ("Colby cheese", "Cheese, colby", "slice (1 oz)", "food"),
    ("Kohlrabi", "Kohlrabi, raw", "cup", "food"),
    ("Artichoke, raw", "Artichokes, (globe or french), raw", "artichoke, medium", "food"),
    ("Okra, raw", "Okra, raw", "cup", "food"),
    ("Fennel", "Fennel, bulb, raw", "bulb", "food"),
    ("Turnip, raw", "Turnips, raw", "medium", "food"),
    ("Swede, raw", "Rutabagas, raw", "medium", "food"),
    ("Collard greens, raw", "Collards, raw", "cup, chopped", "food"),
    ("Watercress", "Watercress, raw", "cup, chopped", "food"),
    ("Alfalfa sprouts", "Alfalfa seeds, sprouted, raw", "cup", "food"),
    ("Basil, fresh", "Basil, fresh", "tbsp, chopped", "extra"),
    ("Coriander leaves", "Coriander (cilantro) leaves, raw", "sprigs", "extra"),
    ("Parsley, fresh", "Parsley, fresh", "tbsp", "extra"),
    ("Persimmon", "Persimmons, japanese, raw", "fruit (2-1/2\" dia)", "food"),
    ("Starfruit", "Carambola, (starfruit), raw", "medium (3-5/8\" long)", "food"),
    ("Guava", "Guavas, common, raw", "fruit, without refuse", "food"),
    ("Plantain, yellow", "Plantains, yellow, raw", "plantain", "food"),
    ("Blackcurrants", "Currants, european black, raw", "cup", "food"),
    ("Elderberries", "Elderberries, raw", "cup", "food"),
    ("Rhubarb, raw", "Rhubarb, raw", "stalk", "food"),
    ("Beetroot, canned", "Beets, canned, drained solids", "cup, diced", "food"),
    ("Yellow capsicum", "Peppers, sweet, yellow, raw", "pepper, large (3-3/4\" long, 3\" dia)", "food"),
    ("Yoghurt, plain, whole milk", "Yogurt, plain, whole milk", "container (6 oz)", "breakfast"),
    ("Greek yoghurt, vanilla, low fat", "Yogurt, Greek, vanilla, lowfat", None, "breakfast"),
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
                # Two portions can share a modifier ("6 inch sub", "12 inch sub"): the amount then tells them apart.
                match = [p for p in portions.get(fdc, []) if f"{float(p['amount']):g} {p['modifier'].strip()}" == serving]
            if len(match) != 1:
                options = [p["modifier"] for p in portions.get(fdc, [])]
                problems.append(f"{name}: portion {serving!r} not found once; options: {options}")
                continue
            portion = match[0]
            grams = float(portion["gram_weight"])
            amount = float(portion["amount"])
            count = f"{amount:g}" if amount != 0.5 else "½"
            label = re.sub(r"\s*\(.*?\)", "", serving).replace(" without refuse", "").strip().replace("tablespoon", "tbsp")
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
