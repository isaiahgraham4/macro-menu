#!/usr/bin/env python3
"""itsu (UK): every product page linked from itsu.com/menu, with the nutrition and allergens itsu publishes.

itsu.com is a Nuxt 2 site. Each product page carries its data in window.__NUXT__ = (function(a, b, ...){return {...}}
(arg, arg, ...)): calories, fat, fat_saturated, protein, carbs, sugars, fibre, salt, allergens and may_contain.
That payload is read with a small JavaScript-literal parser (no JavaScript is run). Writes uk-itsu-source.json.
"""
import datetime
import json
import re
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

BASE = "https://www.itsu.com"
MENU = BASE + "/menu/"
OUT = Path(__file__).with_name("uk-itsu-source.json")
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"

ALLERGENS = {
    "milk": ["milk"], "gluten": ["gluten"], "wheat": ["gluten", "wheat"], "eggs": ["egg"], "egg": ["egg"],
    "soya": ["soy"], "soy": ["soy"], "sesame": ["sesame"], "fish": ["fish"], "crustaceans": ["shellfish"],
    "molluscs": ["shellfish"], "peanuts": ["peanut"], "peanut": ["peanut"], "nuts": ["treenut"], "tree nuts": ["treenut"],
    "lupin": ["lupin"], "sulphites": ["sulphites"], "sulphur dioxide": ["sulphites"],
    "sulphur dioxide and sulphites": ["sulphites"], "celery": [], "mustard": [],
}
ORDER = ["gluten", "wheat", "milk", "egg", "soy", "sesame", "peanut", "treenut", "fish", "shellfish", "lupin", "sulphites"]
CATS = {"breakfast": "breakfast", "hot-iced-drinks": "drink", "cold-drinks": "drink", "desserts-and-snacks": "sweet"}


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "en-GB"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read().decode("utf-8")
        except Exception:
            if attempt == 2:
                raise
            time.sleep(2)


# ---- a minimal JavaScript literal parser for the Nuxt payload ----------------------------------------------------

class Ident(str):
    pass


class JS:
    def __init__(self, s, i=0):
        self.s, self.i = s, i

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in " \t\r\n":
            self.i += 1

    def value(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.obj()
        if c == "[":
            return self.arr()
        if c in "\"'":
            return self.string()
        m = re.compile(r"-?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?").match(self.s, self.i)
        if m and m.group(0) not in ("-",):
            self.i = m.end()
            t = m.group(0)
            return float(t) if any(ch in t for ch in ".eE") else int(t)
        m = re.compile(r"[A-Za-z_$][\w$]*").match(self.s, self.i)
        if m:
            self.i = m.end()
            w = m.group(0)
            if w == "true":
                return True
            if w == "false":
                return False
            if w == "null":
                return None
            if w == "void":
                self.value()
                return None
            if w == "Array" and self.s[self.i] == "(":
                self.i += 1
                n = self.value()
                self.ws()
                self.i += 1
                return [None] * n
            return Ident(w)
        raise ValueError(f"Unexpected {self.s[self.i:self.i + 40]!r}")

    def string(self):
        q = self.s[self.i]
        j = self.i + 1
        out = []
        while self.s[j] != q:
            if self.s[j] == "\\":
                n = self.s[j + 1]
                if n == "u":
                    out.append(chr(int(self.s[j + 2:j + 6], 16)))
                    j += 6
                    continue
                if n == "x":
                    out.append(chr(int(self.s[j + 2:j + 4], 16)))
                    j += 4
                    continue
                out.append({"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0"}.get(n, n))
                j += 2
                continue
            out.append(self.s[j])
            j += 1
        self.i = j + 1
        return "".join(out)

    def obj(self):
        self.i += 1
        out = {}
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                return out
            if self.s[self.i] in "\"'":
                k = self.string()
            else:
                m = re.compile(r"[\w$]+").match(self.s, self.i)
                k = m.group(0)
                self.i = m.end()
            self.ws()
            assert self.s[self.i] == ":", self.s[self.i:self.i + 40]
            self.i += 1
            out[k] = self.value()
            self.ws()
            if self.s[self.i] == ",":
                self.i += 1

    def arr(self):
        self.i += 1
        out = []
        while True:
            self.ws()
            if self.s[self.i] == "]":
                self.i += 1
                return out
            out.append(self.value())
            self.ws()
            if self.s[self.i] == ",":
                self.i += 1


def resolve(v, env):
    if isinstance(v, Ident):
        return env.get(v)
    if isinstance(v, dict):
        return {k: resolve(x, env) for k, x in v.items()}
    if isinstance(v, list):
        return [resolve(x, env) for x in v]
    return v


def nuxt(html):
    m = re.search(r"window\.__NUXT__=\(function\(([^)]*)\)\{return ", html)
    if not m:
        raise ValueError("no __NUXT__ payload")
    params = m.group(1).split(",")
    p = JS(html, m.end())
    body = p.value()
    p.ws()
    assert html[p.i] == "}", html[p.i:p.i + 20]
    p.i += 1
    p.ws()
    assert html[p.i] == "(", html[p.i:p.i + 20]
    p.i += 1
    args = []
    while True:
        p.ws()
        if html[p.i] == ")":
            break
        args.append(p.value())
        p.ws()
        if html[p.i] == ",":
            p.i += 1
    return resolve(body, dict(zip(params, args)))


def find_product(data):
    stack = [data]
    while stack:
        v = stack.pop()
        if isinstance(v, dict):
            if "calories" in v and "marketing_title" in v:
                return v
            stack.extend(v.values())
        elif isinstance(v, list):
            stack.extend(v)
    return None


# ---- products -----------------------------------------------------------------------------------------------------

def number(v):
    if v in (None, ""):
        return None
    try:
        x = float(str(v).replace("g", "").replace("<", "").strip())
    except ValueError:
        return None
    return int(x) if x.is_integer() else round(x, 2)


def allergens(lst, name):
    out = set()
    for a in lst or []:
        n = (a.get("name") or "").strip().lower()
        if n not in ALLERGENS:
            raise SystemExit(f"Unknown itsu allergen {n!r} on {name}")
        out.update(ALLERGENS[n])
    return out


def name_of(raw):
    n = re.sub(r"\s+", " ", raw.replace("’", "'")).strip()
    # itsu writes names in lower case; capitalise each word, leaving short joining words alone.
    small = {"and", "&", "with", "of", "in", "a", "on", "or"}
    words = n.split(" ")
    out = []
    for i, w in enumerate(words):
        if i and w in small:
            out.append(w)
        else:
            out.append(w[:1].upper() + w[1:])
    n = " ".join(out)
    return n.replace("Itsu", "itsu").replace("'n'", "'n'")


def main():
    menu = get(MENU)
    links = sorted(set(re.findall(r'href="(/menu/[^/"]+/[^/"]+/)"', menu)))
    links = [l for l in links if not l.startswith("/menu/menu/")]
    if len(links) < 80:
        raise SystemExit(f"Only {len(links)} itsu product links; the menu page may have changed")
    items, dropped = [], {"alcohol": [], "no nutrition": [], "milk left out": [], "energy": [], "failed": []}
    seen = set()

    def fetch(link):
        try:
            return find_product(nuxt(get(BASE + link)))
        except Exception as e:
            return e

    wanted = [l for l in links if "alcohol" not in l]
    dropped["alcohol"] = [l for l in links if "alcohol" in l]
    with ThreadPoolExecutor(max_workers=4) as pool:
        pages = list(pool.map(fetch, wanted))
    for link, prod in zip(wanted, pages):
        cat_slug = link.split("/")[2]
        if isinstance(prod, Exception):
            dropped["failed"].append(f"{link} ({prod})")
            continue
        if not prod:
            dropped["failed"].append(link)
            continue
        name = name_of(prod.get("marketing_title") or "")
        kcal, p, c, f = (number(prod.get(k)) for k in ("calories", "protein", "carbs", "fat"))
        if kcal is None or p is None or c is None or f is None:
            dropped["no nutrition"].append(name)
            continue
        # itsu's milk coffees and matcha lattes are listed without the milk (a latte at 1 kcal): left out.
        if re.search(r"latte|cappuc+ino|flat white", name, re.I):
            dropped["milk left out"].append(name)
            continue
        est = 4 * p + 4 * c + 9 * f
        if kcal >= 60 and abs(est - kcal) / kcal > 1 / 3:
            dropped["energy"].append(f"{name} ({kcal} kcal, macros {round(est)})")
            continue
        if name.lower() in seen:
            continue
        seen.add(name.lower())
        contains = allergens(prod.get("allergens"), name)
        # itsu's list says "Gluten"; the ingredients (allergens in **bold**) say which cereal.
        if "gluten" in contains and re.search(r"\*\*[^*]*wheat", prod.get("ingredients") or "", re.I):
            contains.add("wheat")
        may = allergens(prod.get("may_contain"), name) - contains
        cat = CATS.get(cat_slug, "main")
        if cat_slug == "desserts-and-snacks" and re.search(r"edamame|crackers|crisps|seaweed|thins|almonds|cashews|pistachios|nori", name, re.I):
            cat = "side"
        if re.search(r"kombucha|shot|juice|water", name, re.I):
            cat = "drink"
        if cat_slug == "sushi-and-salads" and re.search(r"edamame|side|soy sauce", name, re.I):
            cat = "side"
        items.append({
            "name": name, "cat": cat, "serve": "1 serving",
            "cal": kcal, "kj": None, "p": p, "c": c, "f": f,
            "sat": number(prod.get("fat_saturated")), "sugar": number(prod.get("sugars")), "fibre": number(prod.get("fibre")),
            "sodium": None, "salt": number(prod.get("salt")),
            "contains": [a for a in ORDER if a in contains],
            "may": [a for a in ORDER if a in may],
            "vg": None, "meat": None,
        })
    if dropped["failed"]:
        print("Could not read:", dropped["failed"])
    order = {"breakfast": 0, "main": 1, "side": 2, "extra": 3, "sweet": 4, "drink": 5}
    items.sort(key=lambda r: (order[r["cat"]], r["name"]))
    today = datetime.date.today().isoformat()
    left = sum(len(v) for v in dropped.values())
    out = {
        "chain": "uk-itsu",
        "name": "itsu",
        "how": "Official product pages",
        "url": MENU,
        "src": (f"itsu.com product pages, UK menu ({today}), per item as sold; itsu publishes kcal only. Sushi figures leave "
                f"out the bottle of soy sauce, as itsu says. Left out {left}: {len(dropped['alcohol'])} alcoholic drinks, "
                f"{len(dropped['no nutrition'])} with no figures"
                + (f" ({', '.join(dropped['no nutrition'])})" if dropped["no nutrition"] else "")
                + f", {len(dropped['milk left out'])} milk coffees and matcha lattes that itsu lists without the milk"
                + f", {len(dropped['energy'])} of 60 kcal or more whose kcal is over a third away from their macros"
                + (f" ({'; '.join(dropped['energy'])})" if dropped["energy"] else "")
                + (f", {len(dropped['failed'])} pages that could not be read" if dropped["failed"] else "")
                + ". Allergens and may-contain are itsu's own lists."),
        "checked": today,
        "energy": "cal",
        "halal": False,
        "items": items,
    }
    OUT.write_text(json.dumps(out, indent=1, ensure_ascii=False) + "\n")
    print(f"{OUT.name}: {len(items)} items, left out {left}")


if __name__ == "__main__":
    main()
