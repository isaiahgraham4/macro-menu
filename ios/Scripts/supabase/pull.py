#!/usr/bin/env python3
"""Writes Supabase's food data back into the app's bundled files, so the next build ships what phones are being served.

    python3 ios/Scripts/supabase/pull.py            # every dataset
    python3 ios/Scripts/supabase/pull.py menu-AU    # just these
    python3 ios/Scripts/supabase/pull.py --check    # say what differs, change nothing (exit 1 if anything does)

Run it before building when foods were edited in the Supabase dashboard. A file is only rewritten when its foods or
chains differ; keys keep the order they had in the file, so the git diff shows just the edits.
Then run the usual steps after a menu change (allergen-guides.py, diet-info.py, the checks) if menu items were added.
"""
import json
import sys

from leanrrr_data import APP, DATASETS, LISTS, SIDECAR, read_bundled, read_food_lists, remote_dataset, write_food_lists

CORE = ["id", "chain", "name", "cat", "kj", "cal", "p", "c", "f", "serve"]


def strip_nulls(value):
    """Supabase drops nulls; the app reads a missing value and a null the same way."""
    if isinstance(value, dict):
        return {k: strip_nulls(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [strip_nulls(v) for v in value]
    return value


def ordered(new, old):
    """`new` with its keys in `old`'s order (recursively), new keys after; core food keys first for brand-new items."""
    if isinstance(new, dict):
        template = old if isinstance(old, dict) else {}
        keys = [k for k in template if k in new]
        keys += [k for k in CORE if k in new and k not in keys] + [k for k in new if k not in keys and k not in CORE]
        return {k: ordered(new[k], template.get(k)) for k in keys}
    if isinstance(new, list):
        old_list = old if isinstance(old, list) else []
        by_id = {o.get("id"): o for o in old_list if isinstance(o, dict) and "id" in o}
        return [ordered(n, by_id.get(n.get("id")) if isinstance(n, dict) and "id" in n else (old_list[i] if i < len(old_list) else None))
                for i, n in enumerate(new)]
    return new


def main(args):
    if "-h" in args or "--help" in args:
        print(__doc__.strip())
        return
    check = "--check" in args
    names = [a for a in args if not a.startswith("--")] or list(DATASETS)
    lists = read_food_lists()
    changed = []
    for name in names:
        local, newline = read_bundled(name)
        remote = remote_dataset(name)
        if remote is None:
            print(f"{name}: not on Supabase")
            continue
        same = (strip_nulls(local.get("chains", [])) == remote["chains"] and strip_nulls(local["foods"]) == remote["foods"])
        if name in SIDECAR and not check:
            lists[name] = {"revision": remote["revision"], "published": remote["published"]}
        if same:
            print(f"{name}: same as Supabase")
            continue
        old_ids = {f["id"] for f in local["foods"]}
        new_ids = {f["id"] for f in remote["foods"]}
        old_by_id = {f["id"]: strip_nulls(f) for f in local["foods"]}
        edited = sum(1 for f in remote["foods"] if f["id"] in old_by_id and old_by_id[f["id"]] != f)
        print(f"{name}: {len(new_ids - old_ids)} added, {len(old_ids - new_ids)} removed, {edited} edited on Supabase")
        changed.append(name)
        if check:
            continue
        chains = ordered(remote["chains"], local.get("chains", []))
        foods = ordered(remote["foods"], local["foods"])
        if name in LISTS:
            out = foods
        elif name == "supermarket":
            out = {"format": remote.get("format", 1), "published": remote["published"], "chains": chains, "foods": foods}
        else:
            out = {"format": remote.get("format", 1), **({"country": remote["country"]} if remote.get("country") else {}),
                   "revision": remote["revision"], "published": remote["published"], "chains": chains, "foods": foods}
        text = json.dumps(out, ensure_ascii=False, separators=(",", ":")) + ("\n" if newline else "")
        (APP / DATASETS[name]).write_text(text, encoding="utf-8")
    if not check:
        write_food_lists(lists)
    if check and changed:
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
