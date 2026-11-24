#!/usr/bin/env python3
"""US packaged foods by barcode, from USDA FoodData Central's Branded Foods (public domain, CC0).

Branded Foods is what manufacturers send the USDA from their own Nutrition Facts panels, keyed by GTIN/UPC. Leanrrr looks
scans up here (Supabase table public.barcodes, RPC public.barcode) before Open Food Facts when the country is the United
States, and after it elsewhere.

    curl -LO https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_branded_food_json_2026-04-30.zip
    python3 usda-barcodes.py FoodData_Central_branded_food_json_2026-04-30.zip usda-barcodes.jsonl
    python3 usda-barcodes.py --upload usda-barcodes.jsonl

The zip is read as a stream (the JSON inside is 3.3 GB). Rows keep the label's per-serving figures (labelNutrients); a food
without them falls back to the per-100 g values scaled to the serving. One row per barcode, the most recently published.
"""
import json
import re
import sys
import time
import zipfile
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "supabase"))

# FoodData Central nutrient ids, per 100 g or mL, used when a food has no label figures.
NUTRIENTS = {1008: "cal", 1003: "p", 1005: "c", 1004: "f", 1258: "sat", 2000: "sugar", 1079: "fibre", 1093: "sodium"}
LABEL = {"calories": "cal", "protein": "p", "carbohydrates": "c", "fat": "f", "saturatedFat": "sat", "sugars": "sugar",
         "fiber": "fibre", "sodium": "sodium"}
SMALL = {"a", "an", "and", "or", "of", "with", "in", "on", "the", "for", "to", "de", "n"}
KEEP_UPPER = {"bbq", "usa", "us", "xl", "ii", "iii", "pb", "gf", "dha", "mct", "ny", "nyc", "la", "tx", "uht", "kc"}


def title(text):
    """'GRANOLA, CINNAMON, RAISIN' -> 'Granola, Cinnamon, Raisin'; leaves mixed-case text alone."""
    text = re.sub(r"\s+", " ", text or "").strip()
    if not text or any(ch.islower() for ch in text):
        return text
    words = []
    for i, word in enumerate(text.lower().split(" ")):
        bare = re.sub(r"[^a-z]", "", word)
        if bare in KEEP_UPPER:
            words.append(word.upper())
        elif i and bare in SMALL:
            words.append(word)
        else:
            words.append(re.sub(r"(^|[-/(&])([a-z])", lambda m: m.group(1) + m.group(2).upper(), word))
    return " ".join(words)


def tidy_name(description):
    """Drops repeated comma parts ('GRANOLA, CINNAMON, RAISIN, CINNAMON, RAISIN')."""
    parts, seen = [], set()
    for part in (p.strip() for p in (description or "").split(",")):
        if part and part.lower() not in seen:
            seen.add(part.lower())
            parts.append(part)
    return title(", ".join(parts))


def number(value):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return None
    return value if value >= 0 and value == value and value != float("inf") else None


def round_figure(key, value):
    if value is None:
        return None
    if key in ("cal", "sodium"):
        return round(value)
    # Label figures come back from %DV maths as 1.99 or 5.99; a tenth is as fine as a label prints.
    return round(value, 1)


def date(text):
    try:
        return datetime.strptime(text, "%m/%d/%Y").date().isoformat()
    except (TypeError, ValueError):
        return ""


def row(food):
    code = re.sub(r"\D", "", food.get("gtinUpc") or "")
    key = code.lstrip("0")
    if not (6 <= len(key) <= 14) or not (8 <= len(code) <= 14):
        return None
    size, unit = number(food.get("servingSize")), (food.get("servingSizeUnit") or "").strip().lower()
    unit = {"g": "g", "grm": "g", "gm": "g", "ml": "mL", "mlt": "mL"}.get(unit)
    if not size or not unit or size > 2000:
        return None
    figures = {}
    for name, local in LABEL.items():
        value = number((food.get("labelNutrients") or {}).get(name, {}).get("value"))
        if value is not None:
            figures[local] = value
    if "cal" not in figures or "p" not in figures:
        per100 = {}
        for item in food.get("foodNutrients") or []:
            nid = (item.get("nutrient") or {}).get("id")
            unit_name = (item.get("nutrient") or {}).get("unitName")
            if nid in NUTRIENTS and (nid != 1008 or unit_name == "kcal"):
                value = number(item.get("amount"))
                if value is not None:
                    per100[NUTRIENTS[nid]] = value
        if "cal" not in per100 or "p" not in per100:
            return None
        figures = {k: v * size / 100 for k, v in per100.items()}
    cal, p = figures["cal"], figures["p"]
    if cal > 3000 or p > 300 or (cal == 0 and p == 0 and not figures.get("c") and not figures.get("f")):
        return None
    # Protein, carbs and fat can't hold more energy than the label says by much (4/4/9 kcal per g, generous margin).
    if p * 4 + (figures.get("c") or 0) * 4 + (figures.get("f") or 0) * 9 > cal * 1.6 + 25:
        return None
    name = tidy_name(food.get("description"))
    if not name:
        return None
    brand = title(food.get("brandName") or food.get("brandOwner") or "")
    household = re.sub(r"\s+", " ", food.get("householdServingFullText") or "").strip()
    amount = f"{size:g} {unit}"
    household = household.lower() if household.isupper() else household
    if not household or household.lower() == amount.lower():
        serve = amount
    elif re.search(r"\d\s*(g|ml|grams?)\b", household, re.I):
        serve = household  # already says "1 tbsp (7g)"
    else:
        serve = f"{household} ({amount})"
    out = {"code": key, "name": name[:120], "brand": brand[:80] or None, "serve": serve[:80], "amount": round(size, 1), "unit": unit,
           "date": date(food.get("publicationDate")) or date(food.get("availableDate"))}
    for k, v in figures.items():
        out[k] = round_figure(k, v)
    return out


def extract(zip_path, out_path):
    best, seen, kept = {}, 0, 0
    started = time.time()
    with zipfile.ZipFile(zip_path) as archive:
        member = next(n for n in archive.namelist() if n.endswith(".json"))
        with archive.open(member) as stream:
            for raw in stream:
                line = raw.decode("utf-8").strip().rstrip(",")
                if not line.startswith("{\"foodClass\""):
                    continue
                seen += 1
                try:
                    item = row(json.loads(line))
                except (ValueError, KeyError, TypeError):
                    item = None
                if item:
                    kept += 1
                    old = best.get(item["code"])
                    # Latest label wins, but a toddler serving ("age 1-3 years") never beats the adult one.
                    rank = lambda r: ("age " not in r["serve"].lower(), r["date"])
                    if not old or rank(item) >= rank(old):
                        best[item["code"]] = item
                if seen % 100000 == 0:
                    print(f"{seen:,} foods, {len(best):,} barcodes, {time.time() - started:.0f}s", file=sys.stderr)
    with open(out_path, "w") as out:
        for item in best.values():
            out.write(json.dumps({k: v for k, v in item.items() if v is not None}, separators=(",", ":")) + "\n")
    print(f"{seen:,} foods read, {kept:,} usable, {len(best):,} barcodes written to {out_path}", file=sys.stderr)


def upload(path, part=2000):
    """Replaces public.barcodes with the file: stage in parts, then swap in at once (phones never see half a table)."""
    from leanrrr_data import request, upload_key
    key = upload_key()
    rows = [json.loads(line) for line in open(path)]
    started = time.time()
    for start in range(0, len(rows), part):
        for attempt in range(4):
            try:
                request("POST", "/rest/v1/rpc/stage_barcodes", {"key": key, "start": start, "items": rows[start:start + part]})
                break
            except (Exception, SystemExit) as error:  # noqa: BLE001 - retried, then raised
                if attempt == 3:
                    raise
                print(f"retrying part {start}: {error}", file=sys.stderr)
                time.sleep(3 * (attempt + 1))
        if (start // part) % 25 == 0:
            print(f"staged {start + part:,}/{len(rows):,} ({time.time() - started:.0f}s)", file=sys.stderr)
    result = request("POST", "/rest/v1/rpc/commit_barcodes", {"key": key, "source": Path(path).name}, timeout=300)
    print(result)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--upload":
        upload(sys.argv[2])
    elif len(sys.argv) == 3:
        extract(sys.argv[1], sys.argv[2])
    else:
        raise SystemExit(__doc__)
