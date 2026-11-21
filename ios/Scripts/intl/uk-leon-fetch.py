#!/usr/bin/env python3
"""LEON (UK): every menu item on leon.co/menu, with the nutrition and allergens LEON's site carries.

The menu page is a Next.js page; its React Server Components payload (self.__next_f.push chunks) holds each
menu item as a Sanity document with nutritionInfo (kcal, protein, carb, fat, satFat, sugar, fibre, salt,
totalPortionWeight), allergens and dietary tags. Writes uk-leon-source.json next to this script.
"""
import datetime
import json
import re
import urllib.request
from pathlib import Path

URL = "https://leon.co/menu/"
OUT = Path(__file__).with_name("uk-leon-source.json")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

ALLERGENS = {
    "milk": ["milk"], "egg": ["egg"], "soya": ["soy"], "soy": ["soy"], "sesame": ["sesame"], "fish": ["fish"],
    "lupin": ["lupin"], "peanuts": ["peanut"], "nuts-peanut": ["peanut"], "sulphur-dioxide": ["sulphites"],
    "sulphites": ["sulphites"], "crustaceans": ["shellfish"], "molluscs": ["shellfish"],
    "gluten-wheat": ["gluten", "wheat"], "gluten-oats": ["gluten"], "gluten-rye": ["gluten"],
    "gluten-barley": ["gluten"], "gluten-spelt": ["gluten", "wheat"], "gluten": ["gluten"],
    "celery": [], "mustard": [],
}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-GB"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def payload(html):
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>', html, re.S)
    return "".join(json.loads('"' + c + '"') for c in chunks)


def menu_items(s):
    dec = json.JSONDecoder()
    items = {}
    for m in re.finditer(r'\{"_id":"', s):
        try:
            o, _ = dec.raw_decode(s, m.start())
        except ValueError:
            continue
        if o.get("type") == "menuItem":
            items[o["_id"]] = o
    return list(items.values())


def allergens(o):
    out = set()
    for a in o.get("allergens") or []:
        slug = a.get("slug", "")
        if slug in ALLERGENS:
            out.update(ALLERGENS[slug])
        elif slug.startswith("nuts-"):
            out.add("treenut")
        else:
            raise SystemExit(f"Unknown LEON allergen {slug!r} on {o['name']}")
    order = ["gluten", "wheat", "milk", "egg", "soy", "sesame", "peanut", "treenut", "fish", "shellfish", "lupin", "sulphites"]
    return [k for k in order if k in out]


def category(menu, sub):
    menu, sub = (menu or "").lower(), (sub or "").lower()
    if menu.startswith(("coffee", "drinks")):
        return "drink"
    if "sauce" in sub:
        return "extra"
    if menu.startswith("breakfast"):
        return "breakfast"
    if "cake" in sub:
        return "sweet"
    if sub.startswith(("sides", "fries", "snacks")):
        return "side"
    return "main"


def name_of(raw):
    n = re.sub(r"[​ ]", " ", raw)
    n = re.sub(r"\s+", " ", n).strip()
    n = re.sub(r"\s+Small$", " (small)", n)
    return n


def num(v):
    if v is None:
        return None
    return int(v) if float(v).is_integer() else float(v)


def main():
    items = menu_items(payload(get(URL)))
    if len(items) < 100:
        raise SystemExit(f"Only {len(items)} LEON items found; the page layout may have changed")
    rows, dropped = [], {"no nutrition": [], "meal": [], "energy": []}
    for o in items:
        n = o.get("nutritionInfo") or {}
        name = name_of(o["name"])
        if n.get("kcal") is None or n.get("protein") is None:
            dropped["no nutrition"].append(name)
            continue
        if "pick and mix" in name.lower():
            dropped["meal"].append(name)
            continue
        kcal, p, c, f = n["kcal"], n["protein"], n.get("carb") or 0, n.get("fat") or 0
        calc = 4 * p + 4 * c + 9 * f
        # Same rule as build-intl-menu.py: over a third out, for items of 60 kcal or more.
        if kcal >= 60 and abs(calc - kcal) / kcal > 1 / 3:
            dropped["energy"].append(name)
            continue
        menu = (o.get("menuType") or {}).get("name")
        sub = (o.get("submenuType") or {}).get("name")
        diet = {d.get("slug") for d in o.get("dietary") or []}
        w = n.get("totalPortionWeight")
        rows.append({
            "name": name,
            "cat": category(menu, sub),
            "serve": f"1 serving ({num(w)} g)" if w and w >= 20 else "1 serving",
            "cal": num(kcal), "kj": None,
            "p": num(p), "c": num(c), "f": num(f),
            "sat": num(n.get("satFat")), "sugar": num(n.get("sugar")), "fibre": num(n.get("fibre")),
            "sodium": None, "salt": num(n.get("salt")),
            "contains": allergens(o),
            "may": None,
            "vg": "vegan" if "vegan" in diet else ("vegetarian" if "vegetarian" in diet else None),
            "meat": None,
        })
    # Same name listed twice (e.g. under two menus): keep the first.
    seen, unique = set(), []
    for r in rows:
        if r["name"].lower() not in seen:
            seen.add(r["name"].lower())
            unique.append(r)
    order = {"breakfast": 0, "main": 1, "side": 2, "extra": 3, "sweet": 4, "drink": 5}
    unique.sort(key=lambda r: (order[r["cat"]], r["name"]))
    left = len(dropped["no nutrition"]) + len(dropped["meal"]) + len(dropped["energy"])
    today = datetime.date.today().isoformat()
    out = {
        "chain": "uk-leon",
        "name": "LEON",
        "how": "Official online menu",
        "url": URL,
        "src": (f"leon.co menu item nutrition and allergens ({today}), per item as served; LEON publishes kcal only. "
                f"Left out {left}: {len(dropped['no nutrition'])} with no nutrition (crisps, snacks, teas, retail coffee), "
                f"the Kids Pick and Mix meal, and {len(dropped['energy'])} of 60 kcal or more whose kcal is over a third away from their macros "
                f"({', '.join(sorted(dropped['energy']))}). LEON gives no may-contain list."),
        "checked": today,
        "energy": "cal",
        "halal": False,
        "items": unique,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(unique)} items, left out {left}")


if __name__ == "__main__":
    main()
