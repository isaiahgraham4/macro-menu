#!/bin/sh
# Publishes ios/MacroMenu/MenuData.json for menu updates between app versions.
# Run `node ios/Scripts/export-menu.cjs` and `sh ios/Tests/run-checks.sh` first. Phones pick the new menu up within about 6 hours;
# the app only switches to it if it's a newer, valid menu.
# 1. Supabase, which version 1.3 and later read for every dataset (ios/supabase/README.md).
# 2. The old unlisted gist, which versions 1.0-1.2 still read. Drop this step once nobody is on those versions.
set -eu
cd "$(dirname "$0")/../.."
python3 ios/Scripts/supabase/upload.py menu-AU
gist=7e5dd29511588062da0d233fdc88cbc1
url="https://gist.githubusercontent.com/isaiahgraham4/$gist/raw/MenuData.json"
menu=ios/MacroMenu/MenuData.json
gh gist edit "$gist" -f MenuData.json "$menu"
# GitHub caches the file for up to 5 minutes; wait until the new copy is served.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -fsS -H "Cache-Control: no-cache" "$url" | cmp -s - "$menu"; then echo "Published to the gist too: $url"; exit 0; fi
  sleep 30
done
echo "Uploaded, but GitHub is still serving the old copy. Check again in a few minutes." >&2
exit 1
