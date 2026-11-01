#!/usr/bin/env python3
"""Finds items on the restaurants' own menus that Leanr doesn't have yet. It only reports: it never edits the menu.

Each week this lists every chain's current menu from its own website or ordering site, and compares that with the list it
kept last time (menu-watch/seen.json) and with the app's menu (MenuData.json).

- Plain requests: Nando's, Grill'd, Hungry Jack's, Oporto, Red Rooster, Domino's, Spud Bar, Schnitz. No keys are needed:
  Oporto's and Red Rooster's menu files are linked from their public menu pages.
- A real browser: McDonald's, KFC and Subway refuse plain requests, and Crust, Donut King, Michel's, Brumby's and THISBOWL
  build their nutrition pages in the browser. These lists are read there and saved as menu-watch/browser.json
  ({"captured": "YYYY-MM-DD", "mcd": [{"name", "kj"}], "kfc": [...], "guides": {"sub": [urls], "rolld": [urls]}}), then
  read here. A list from another day counts as not read.
- Guide PDFs: Subway, Guzman y Gomez, Zambrero, Boost Juice, Spud Bar, Betty's Burgers, Five Guys, Soul Origin and Roll'd
  publish their figures in PDFs. Each guide is read every week, because some keep the same address when they're replaced.
  A guide that has changed is flagged with its new text lines, since those are where new items show up. Chains checked
  only this way show a new item once a new guide is out. Subway's files refuse plain requests, so a new one is flagged by
  its address alone.

The first time a chain is read, its list is the starting point: nothing counts as new, and what's on its menu but not in
the app goes in menu-watch/reports/<date>-first-read.md instead. Names rarely match the app's exactly there, so that list
is a starting point to read, not a list of gaps.

A source that fails, or returns under 60% of what it had last time, is reported as a failure and its list is left alone, so
a maintenance page can't make everything look new or gone. Nothing here retries a refused request.

Items keep showing under "Waiting" until they're in the app or skipped, so a week's finds don't get lost:

Usage:
    python3 ios/Scripts/menu-watch.py check                  # reads every source and writes menu-watch/reports/<date>.md
    python3 ios/Scripts/menu-watch.py skip kfc "Item name"   # stops reporting an item that won't be added
"""
import html, json, re, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
WATCH = HERE / "menu-watch"
SEEN = WATCH / "seen.json"
BROWSER = WATCH / "browser.json"
REPORTS = WATCH / "reports"
CATALOG = HERE.parent / "MacroMenu" / "MenuData.json"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
TODAY = time.strftime("%Y-%m-%d")
# Meals and packs of things sold on their own. Listed apart, since Leanr mostly carries the parts.
BUNDLE = re.compile(r"\b(combo|box(es)?|feast|bundle|meal|meals|deal|pack|for [2-9]|saver|hunger tamers?)\b", re.I)


def get(url, headers=None, data=None, binary=False):
    args = ["curl", "-sfL", "-A", UA, "-m", "60"]
    for k, v in (headers or {}).items():
        args += ["-H", f"{k}: {v}"]
    if data:
        args += ["--data", data]
    out = subprocess.run(args + [url], capture_output=True, check=True).stdout
    return out if binary else out.decode("utf-8", "replace")


def clean(text):
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", text))).strip()


def norm(name):
    """A name reduced to its words, so "Zinger® Burger", "NEW Zinger Burger" and "Burger, Zinger" all match."""
    name = re.sub(r"[®™©*^~†]|\(i\)|\(v\)", " ", name.lower()).replace("&", " and ")
    words = re.findall(r"[a-z0-9]+", name.replace("'", "").replace("’", ""))
    return " ".join(sorted(w for w in words if w not in ("new", "the", "with", "and", "of", "a")))


def nandos():
    query = """query getMenu($restaurantId: String!, $loadDetails: Boolean, $orderType: OrderType) {
      menu(input: {restaurantId: $restaurantId, loadDetails: $loadDetails, orderType: $orderType}) { categories { name products { name } } } }"""
    body = json.dumps({"operationName": "getMenu", "query": query, "variables": {"restaurantId": "150", "loadDetails": False, "orderType": "PICK_UP"}})
    menu = json.loads(get("https://api.nandos.com.au/public/graphql", {"content-type": "application/json", "origin": "https://www.nandos.com.au"}, body))
    return [{"name": p["name"], "cat": c["name"]} for c in menu["data"]["menu"]["categories"] for p in c["products"]]


def grilld():
    menu = json.loads(get("https://api.digital.grilld.com.au/v1/restaurants/153/menu?orderType=Pickup", {"Accept": "application/json", "platform": "web"}))
    return [{"name": i["title"], "cat": c["title"]} for c in menu["categories"] for i in c["items"]]


def hungry_jacks():
    cats = sorted(set(re.findall(r'href="/menu/([a-z0-9-]+)"', get("https://www.hungryjacks.com.au/menu"))))
    items = []
    for cat in cats:
        page = get(f"https://www.hungryjacks.com.au/menu/{cat}")
        for link, inner in re.findall(r'<a[^>]+href="/menu/[a-z0-9-]+/([a-z0-9-]+)"[^>]*>(.*?)</a>', page, re.S):
            alt = re.search(r'alt="([^"]+)"', inner)
            items.append({"name": html.unescape(alt.group(1)) if alt else link.replace("-", " ").title(), "cat": cat})
        time.sleep(0.3)
    return items


def craveable(site, store):
    """Oporto and Red Rooster: the menu file their public store page links to."""
    page = get(f"https://www.{site}.com.au/locations/{store}/menu/")
    data = json.loads(re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', page, re.S).group(1))
    menus = data["props"]["pageProps"]["data"]["pageDataContent"]["data"]["result"]["metadata"]["menu"]["result"]
    menu = json.loads(get(next(m["menuUrls"] for m in menus if "Pickup" in m["menuName"])))
    # Only what's sold on the menu: the sub-items are a product's options, such as every drink a meal can come with.
    return [{"name": p["name"].strip(), "cat": c["name"], "kj": p.get("kJ")} for c in menu["categories"] if c["name"] != "HIDDEN" for p in c["products"]]


def dominos():
    page = get("https://www.dominos.com.au/menu")
    return [{"name": re.sub(r"-[ps]\d+$", "", slug).replace("-", " ").title(), "cat": cat}
            for cat, slug in sorted(set(re.findall(r'href="/menu-([a-z-]+)/([a-z0-9-]+)"', page)))]


def spud():
    """Bowl names are pictures on the page, so a bowl is known by its description. Each has "Protein 26g • kJ 2684" under it."""
    page = re.sub(r"<(style|script)[^>]*>.*?</\1>", "", get("https://www.spudbar.com.au/menu"), flags=re.S)
    lines = [clean(x) for x in re.sub(r"<[^>]+>", "\n", page).split("\n") if x.strip()]
    items = []
    for before, line in zip(lines, lines[1:]):
        kj = re.search(r"kJ\s*(\d+)", line)
        if kj and "base" in before:
            items.append({"name": before, "kj": int(kj.group(1))})
    return items


def schnitz():
    page = get("https://schnitz.com.au/our-menu/")
    heads = [clean(x) for x in re.findall(r"<h[1-4][^>]*>(.*?)</h[1-4]>", page, re.S)]
    return [{"name": h} for h in heads if h and h != "Nutritional Information"]


def link(page_url, pattern):
    """The guide's current address, read from the official page, so a replaced file is noticed."""
    page = html.unescape(get(page_url))
    found = re.findall(r'(?:href="|")([^"\s]*%s[^"\s]*\.pdf)' % pattern, page, re.I)
    if not found:
        raise RuntimeError(f"no guide link on {page_url}")
    url = found[0].replace("\\u0026", "&")
    return url if url.startswith("http") else re.match(r"https://[^/]+", page_url).group(0) + url


def guide_lines(url):
    """A guide's text lines that could be item names."""
    import pymupdf
    path = Path(tempfile.mkdtemp()) / "guide.pdf"
    path.write_bytes(get(url, binary=True))
    lines = set()
    for page in pymupdf.open(path):
        for line in page.get_text().split("\n"):
            line = re.sub(r"\s+", " ", line).strip()
            if 3 < len(line) < 70 and re.search(r"[A-Za-z]{3}", line):
                lines.add(line)
    return sorted(lines)


LISTS = {"nandos": nandos, "grilld": grilld, "hj": hungry_jacks, "oporto": lambda: craveable("oporto", "melbourne-central"),
         "rr": lambda: craveable("redrooster", "carlton"), "dominos": dominos, "spud": spud, "schnitz": schnitz}
GUIDES = {"gyg": lambda: [link("https://www.guzmanygomez.com.au/nutrition/", r"NUTRITION_ALLERGEN_GUIDE")],
          "zam": lambda: [link("https://www.zambrero.com.au/allergens", r"Zambrero-Nutritional-Information")],
          "boost": lambda: [link("https://www.boostjuice.com.au/", r"Nutritional")],
          "spud": lambda: [link("https://www.spudbar.com.au/menu", r"Product-Information-Guide")],
          "betty": lambda: [link("https://www.bettysburgers.com.au/nutritional-and-allergens", r"nutritional-info")],
          "fiveguys": lambda: [link("https://www.fiveguys.com.au/nutritional-allergy-information/", r"Australia-EN")],
          "soul": lambda: [link("https://www.soulorigin.com.au/", r"Nutritionals")]}
# Read in a real browser and saved to browser.json.
BROWSER_LISTS = ("mcd", "kfc", "sub", "crust", "donutking", "michels", "brumbys", "thisbowl")


def read_lists():
    lists, failed = {}, {}
    for chain, read in LISTS.items():
        try:
            lists[chain] = read()
        except Exception as e:
            failed[chain] = str(e)[:120] or type(e).__name__
    browser = json.loads(BROWSER.read_text()) if BROWSER.exists() else {}
    for chain in BROWSER_LISTS:
        if browser.get("captured") == TODAY and browser.get(chain):
            lists[chain] = browser[chain]
        else:
            failed[chain] = "no browser list from today"
    return lists, failed, browser.get("guides", {}) if browser.get("captured") == TODAY else {}


def read_guides(browser_guides, state):
    """{chain: {url: lines}} for the chains' guides, with the new text of any guide that has changed."""
    guides, new, failed = {}, {}, {}
    urls = dict(browser_guides)
    for chain, find in GUIDES.items():
        try:
            urls[chain] = find()
        except Exception as e:
            failed[f"{chain} guide"] = str(e)[:120] or type(e).__name__
    for chain, found in urls.items():
        old = state.get("guides", {}).get(chain, {})
        guides[chain] = dict(old)
        for url in found:
            try:
                lines = guide_lines(url)
            except Exception as e:
                if chain == "sub" and url in old:
                    continue
                if chain != "sub":
                    failed[f"{chain} guide"] = f"{url}: {str(e)[:100] or type(e).__name__}"
                    continue
                lines = []
            known = {x for u in old for x in old[u]}
            if url in old and set(lines) == set(old[url]):
                continue
            guides[chain][url] = lines
            if old:
                new[url] = {"chain": chain, "lines": [x for x in lines if x not in known]}
            time.sleep(0.3)
    return guides, new, failed


def catalog():
    data = json.loads(CATALOG.read_text())
    names = {}
    for food in data["foods"]:
        names.setdefault(food["chain"], set()).add(norm(food["name"]))
    return names, {c["id"]: c["name"] for c in data["chains"]}


def in_app(name, known):
    return norm(name) in known


def main():
    REPORTS.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    state = json.loads(SEEN.read_text()) if SEEN.exists() else {"items": {}, "guides": {}}
    if args[:1] == ["skip"] and len(args) == 3:
        entry = state["items"].get(args[1], {}).get(norm(args[2]))
        if not entry:
            raise SystemExit(f"Not on the {args[1]} list: {args[2]}")
        entry["skip"] = True
        SEEN.write_text(json.dumps(state, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
        return print(f"Skipped {entry['name']}")
    if args[:1] != ["check"]:
        raise SystemExit(__doc__)

    lists, failed, browser_guides = read_lists()
    guides, new_guides, guide_failed = read_guides(browser_guides, state)
    known, chain_names = catalog()

    lines, counts = [f"# Menu check, {TODAY}", ""], {}
    found, waiting, started = {}, {}, []
    for chain, items in sorted(lists.items()):
        baseline = chain not in state["items"] or any(e["first"] == "baseline" and e.get("on") == TODAY for e in state["items"][chain].values())
        seen = state["items"].setdefault(chain, {})
        now = {}
        for item in items:
            if item.get("name"):
                now.setdefault(norm(item["name"]), item)
        counts[chain] = len(now)
        on_list = [k for k, v in seen.items() if not v.get("gone")]
        if on_list and len(now) < 0.6 * len(on_list):
            failed[chain] = f"only {len(now)} items, was {len(on_list)}"
            continue
        for key, item in now.items():
            if key not in seen:
                seen[key] = {"name": item["name"], "first": "baseline" if baseline else TODAY}
                if baseline:
                    seen[key]["on"] = TODAY
                if item.get("kj"):
                    seen[key]["kj"] = item["kj"]
                if item.get("cat"):
                    seen[key]["cat"] = item["cat"]
            elif seen[key].get("gone"):
                del seen[key]["gone"]
        for key, entry in seen.items():
            if key not in now:
                entry["gone"] = TODAY
        if baseline:
            started.append(chain)
        if any(e["first"] == TODAY for e in seen.values()):
            found[chain] = [e for e in seen.values() if e["first"] == TODAY and not e.get("gone")]
        waiting[chain] = [e for e in seen.values() if e["first"] != "baseline" and not e.get("skip") and not e.get("gone")
                          and e["first"] != TODAY and not in_app(e["name"], known.get(chain, set()))]

    def row(entry):
        energy = f" ({entry['kj']} kJ)" if entry.get("kj") else ""
        where = f" [{entry['cat']}]" if entry.get("cat") else ""
        return f"{entry['name']}{energy}{where}"

    def section(title, entries):
        items = [e for e in entries if not BUNDLE.search(e["name"])]
        bundles = [e for e in entries if BUNDLE.search(e["name"])]
        out = [f"### {title}"] + [f"- {row(e)}" for e in sorted(items, key=lambda e: e["name"])]
        if bundles:
            out.append(f"- Meals and packs ({len(bundles)}): " + "; ".join(sorted(e["name"] for e in bundles)))
        return out + [""]

    lines += ["## New on the menus", ""]
    for chain in sorted(found):
        lines += section(chain_names.get(chain, chain), found[chain])
    if not found:
        lines += ["Nothing new.", ""]
    if new_guides:
        lines += ["## New guide PDFs", ""]
        for url, guide in new_guides.items():
            lines += [f"### {chain_names.get(guide['chain'], guide['chain'])}", url, ""] + [f"- {x}" for x in guide["lines"][:80]]
            if len(guide["lines"]) > 80:
                lines.append(f"- ...and {len(guide['lines']) - 80} more lines")
            lines.append("")
    if any(waiting.values()):
        lines += ["## Waiting to be added", ""]
        for chain in sorted(c for c in waiting if waiting[c]):
            lines += section(chain_names.get(chain, chain), waiting[chain])
    first_read = [f"# First read, {TODAY}: on the menu but not matched to the app", ""]
    for chain in started:
        missing = [e for e in state["items"][chain].values() if not e.get("gone") and not in_app(e["name"], known.get(chain, set()))]
        if missing:
            first_read += section(f"{chain_names.get(chain, chain)} ({len(missing)})", missing)
    if started:
        (REPORTS / f"{TODAY}-first-read.md").write_text("\n".join(first_read))
    failed.update(guide_failed)
    if failed:
        lines += ["## Sources not read", ""] + [f"- {chain_names.get(k, k)}: {v}" for k, v in sorted(failed.items())] + [""]
    lines += ["## Items listed", "", ", ".join(f"{chain_names.get(c, c)} {n}" for c, n in sorted(counts.items())), ""]

    state["guides"] = guides
    state["checked"] = TODAY
    SEEN.write_text(json.dumps(state, indent=1, ensure_ascii=False, sort_keys=True) + "\n")
    report = REPORTS / f"{TODAY}.md"
    # A second run on the same day keeps what was added after the checker's part: the figures and any notes.
    old = report.read_text() if report.exists() else ""
    added = re.search(r"## Items listed\n\n.*\n", old)
    report.write_text("\n".join(lines) + (old[added.end():] if added else ""))
    print(f"{sum(len(v) for v in found.values())} new, {len(new_guides)} new guides, {sum(len(v) for v in waiting.values())} waiting, "
          f"{len(failed)} sources not read. Report: {report}")


if __name__ == "__main__":
    main()
