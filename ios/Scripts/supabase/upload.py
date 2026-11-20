#!/usr/bin/env python3
"""Uploads the bundled food files to Supabase, where the app checks for newer data a few times a day.

    python3 ios/Scripts/supabase/upload.py              # every dataset that changed
    python3 ios/Scripts/supabase/upload.py menu-AU      # just these (menu-AU, menu-US ... generic, survey, supermarket)
    python3 ios/Scripts/supabase/upload.py --force ...  # even if Supabase already has this revision

Run it after rebuilding a file (export-menu.cjs, build-intl-menu.py, generic-foods.py ...) and running the checks.
An upload replaces the whole dataset, so edits made in the Supabase dashboard since the last `pull.py` are lost:
pull first if anyone has edited there. Phones only switch to a dataset that is newer than the one they have and passes
the same checks as a bundled one.
"""
import sys
from datetime import datetime, timezone

from leanrrr_data import (APP, DATASETS, SIDECAR, fingerprint, read_bundled, read_food_lists, remote_header, request,
                          upload_key, write_food_lists)

PART = 400  # rows per request: well inside the 3-second limit on each call


def now_iso():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def parse(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00"))


def set_bundled_published(name, old, new):
    """Changes only the menu file's own date, leaving the rest of it byte for byte."""
    path = APP / DATASETS[name]
    text = path.read_text(encoding="utf-8")
    path.write_text(text.replace(f'"published":"{old}"', f'"published":"{new}"', 1), encoding="utf-8")


def main(args):
    if "-h" in args or "--help" in args:
        print(__doc__.strip())
        return
    force = "--force" in args
    names = [a for a in args if not a.startswith("--")] or list(DATASETS)
    unknown = [n for n in names if n not in DATASETS]
    if unknown:
        raise SystemExit(f"Unknown dataset {', '.join(unknown)}. Choose from: {', '.join(DATASETS)}")
    key = upload_key()
    lists = read_food_lists()
    for name in names:
        data, _ = read_bundled(name)
        chains, foods = data.get("chains", []), data["foods"]
        remote = remote_header(name)
        if name in SIDECAR:
            revision = fingerprint(chains, foods)
            # Same contents keep their date, so a re-upload isn't "newer" on phones.
            known = lists.get(name, {})
            published = (remote["published"] if remote and remote["revision"] == revision
                         else known["published"] if known.get("revision") == revision
                         else data.get("published") or now_iso())
        else:
            revision, published = data.get("revision"), data.get("published")
            if not revision or not published:
                raise SystemExit(f"{DATASETS[name]} has no revision or published date; rebuild it first.")
        # Phones only take a newer dataset. After a dashboard edit Supabase's date can be later than the file's.
        if remote and remote["revision"] != revision and parse(published) <= parse(remote["published"]):
            published = now_iso()
            if name not in SIDECAR:
                set_bundled_published(name, data["published"], published)
            print(f"{name}: dated {published} so phones see it as newer than Supabase's copy")
        if remote and remote["revision"] == revision and not force:
            print(f"{name}: already up to date ({revision})")
            if name in SIDECAR:
                lists[name] = {"revision": revision, "published": remote["published"]}
            continue
        request("POST", "/rest/v1/rpc/stage_upload", {"key": key, "dataset": name, "kind": "chain", "start": 0, "items": chains})
        for start in range(0, len(foods), PART):
            request("POST", "/rest/v1/rpc/stage_upload",
                    {"key": key, "dataset": name, "kind": "food", "start": start, "items": foods[start:start + PART]})
        result = request("POST", "/rest/v1/rpc/commit_upload", {
            "key": key, "dataset": name, "file": DATASETS[name], "format": data.get("format", 1),
            "country": data.get("country"), "revision": revision, "published": published})
        print(f"{name}: uploaded {result['foods']} foods, {result['chains']} chains ({revision}, {published})")
        if name in SIDECAR:
            lists[name] = {"revision": revision, "published": published}
    write_food_lists(lists)


if __name__ == "__main__":
    main(sys.argv[1:])
