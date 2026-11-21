"""Shared bits for upload.py and pull.py: which bundled file each Supabase dataset mirrors, and how to talk to the project.

Reads go through the publishable key (the same one the app uses). Writes need the upload key from the macOS keychain
(service "Leanrrr Supabase upload"); only its SHA-256 is stored in the project (private.upload_keys).
"""
import hashlib
import json
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

URL = "https://dmfmrqvmwvabzkqgdbdw.supabase.co"
PUBLISHABLE_KEY = "sb_publishable_rV4qINsqDY5CRsh88QzcGQ_2KFiIuJE"
APP = Path(__file__).resolve().parent.parent.parent / "MacroMenu"
# Revisions and publish times for the bundled files that don't carry their own (the app reads this too).
FOOD_LISTS = APP / "FoodLists.json"
COUNTRIES = ["AU", "NZ", "US", "CA", "GB", "ZA", "IN", "SG"]
# Countries with a supermarket shelf file (MenuRegion.supermarketIDs); Australia's dataset keeps the id "supermarket".
SHOP_COUNTRIES = ["NZ", "US", "CA", "GB", "ZA"]

# dataset id -> bundled file name
DATASETS = {**{f"menu-{c}": ("MenuData.json" if c == "AU" else f"MenuData-{c}.json") for c in COUNTRIES},
            "generic": "GenericFoods.json", "survey": "SurveyFoods.json", "supermarket": "SupermarketFoods.json",
            **{f"supermarket-{c}": f"SupermarketFoods-{c}.json" for c in SHOP_COUNTRIES}}
# Datasets whose bundled file is a bare list of foods, or has no revision of its own.
LISTS = {"generic", "survey"}
SIDECAR = {"generic", "survey", "supermarket", *(f"supermarket-{c}" for c in SHOP_COUNTRIES)}


def fingerprint(chains, foods):
    return hashlib.sha256(json.dumps({"chains": chains, "foods": foods}, sort_keys=True, ensure_ascii=False).encode()).hexdigest()[:16]


def read_bundled(dataset):
    """The bundled file as {format, country?, revision?, published?, chains, foods}, plus whether it ended with a newline."""
    path = APP / DATASETS[dataset]
    text = path.read_text(encoding="utf-8")
    data = json.loads(text)
    if isinstance(data, list):
        data = {"format": 1, "chains": [], "foods": data}
    return data, text.endswith("\n")


def read_food_lists():
    try:
        return json.loads(FOOD_LISTS.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def write_food_lists(entries):
    FOOD_LISTS.write_text(json.dumps(entries, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def upload_key():
    try:
        return subprocess.run(["security", "find-generic-password", "-a", "leanrrr", "-s", "Leanrrr Supabase upload", "-w"],
                              check=True, capture_output=True, text=True).stdout.strip()
    except subprocess.CalledProcessError:
        raise SystemExit("No upload key in the keychain (service \"Leanrrr Supabase upload\"). See ios/supabase/README.md.")


def request(method, path, body=None, timeout=60):
    data = None if body is None else json.dumps(body, ensure_ascii=False).encode()
    req = urllib.request.Request(URL + path, data=data, method=method, headers={
        "apikey": PUBLISHABLE_KEY, "Content-Type": "application/json", "Accept": "application/json",
        "Cache-Control": "no-cache"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read()
    except urllib.error.HTTPError as error:
        raise SystemExit(f"{method} {path.split('?')[0]} failed: {error.code} {error.read().decode(errors='replace')[:400]}")
    return json.loads(raw) if raw else None


def remote_header(dataset):
    rows = request("GET", f"/rest/v1/datasets?id=eq.{dataset}&select=id,revision,published,updated_at")
    return rows[0] if rows else None


def remote_dataset(dataset):
    return request("GET", f"/rest/v1/rpc/dataset?id={dataset}", timeout=120)
