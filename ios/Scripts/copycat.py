#!/usr/bin/env python3
"""Builds MacroMenu/CopycatKitchen.json: home versions of takeaway items, for Copycat Kitchen on the Find tab.

Recipes live in copycat_recipes.py. Ingredient values are USDA's, scaled to 100 g from GenericFoods.json and
SurveyFoods.json, plus the few entries the app's food lists don't carry (FDC in copycat_recipes.py).
Shop figures aren't copied here: the app reads them from the menu, so a menu update reaches the comparison by itself.

    python3 ios/Scripts/copycat.py
"""
import json, re, sys
from pathlib import Path

from copycat_recipes import RECIPES, LOCAL, FDC

APP = Path(__file__).resolve().parent.parent / "MacroMenu"


def grams_in(serve):
    match = re.search(r"\(([\d.]+)\s*g\)", serve or "") or re.fullmatch(r"([\d.]+)\s*g", serve or "")
    return float(match.group(1)) if match else None


def ingredients():
    foods = {f["id"]: f for name in ("GenericFoods.json", "SurveyFoods.json") for f in json.load(open(APP / name))}
    table = {}
    for key, food_id in LOCAL.items():
        food = foods[food_id]
        grams = grams_in(food["serve"])
        if not grams:
            sys.exit(f"{key}: no grams in serve {food['serve']!r}")
        scale = 100 / grams
        table[key] = {
            "kj": food["kj"] * scale, "p": food["p"] * scale, "c": food["c"] * scale, "f": food["f"] * scale,
            "nut": {k: v * scale for k, v in food.get("nut", {}).items() if v is not None},
        }
    for key, (_, kcal, p, c, f, sat, sugar, fibre, sodium) in FDC.items():
        table[key] = {"kj": kcal * 4.184, "p": p, "c": c, "f": f, "nut": {"sat": sat, "sugar": sugar, "fibre": fibre, "sodium": sodium}}
    return {k: {**{n: round(row[n], 3) for n in ("kj", "p", "c", "f")}, "nut": {n: round(v, 3) for n, v in row["nut"].items()}} for k, row in table.items()}


def main():
    menu = {f["id"] for f in json.load(open(APP / "MenuData.json"))["foods"]}
    table = ingredients()
    recipes = []
    for r in RECIPES:
        if r["real"] not in menu:
            sys.exit(f"{r['id']}: {r['real']} isn't on the menu")
        for row in r["rows"]:
            if row[1] not in table:
                sys.exit(f"{r['id']}: no ingredient {row[1]}")
        recipes.append({
            "id": r["id"], "name": r["name"], "shop": r["real"], "quantity": r["qty"], "unit": r["unit"], "serves": r["serves"],
            "time": r["time"], "hook": r["hook"], "verdict": r["verdict"], "method": r["method"],
            "rows": [{"slot": s, "key": k, "g": g, "label": label, "measure": measure} for s, k, g, label, measure in r["rows"]],
            "swaps": [{"id": i, "label": label, "why": why, "changes": [
                {k: v for k, v in zip(("slot", "key", "g", "label", "measure"), change) if v is not None} for change in changes
            ]} for i, label, why, changes in r["swaps"]],
        })
    (APP / "CopycatKitchen.json").write_text(json.dumps({"ingredients": table, "recipes": recipes}, ensure_ascii=False, separators=(",", ":")))
    print(f"{len(recipes)} recipes, {len(table)} ingredients")


if __name__ == "__main__":
    main()
