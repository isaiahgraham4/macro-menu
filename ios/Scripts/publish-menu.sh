#!/bin/sh
# Publishes ios/MacroMenu/MenuData.json to the unlisted gist the app downloads menu updates from (MenuUpdates.url).
# Run `node ios/Scripts/export-menu.cjs` and `sh ios/Tests/run-checks.sh` first. Phones pick the new menu up within about 6 hours;
# the app only switches to it if it's a newer, valid menu, so publishing an older one does nothing.
set -eu
cd "$(dirname "$0")/../.."
gist=7e5dd29511588062da0d233fdc88cbc1
url="https://gist.githubusercontent.com/isaiahgraham4/$gist/raw/MenuData.json"
menu=ios/MacroMenu/MenuData.json
grep -q "$gist" ios/MacroMenu/MenuUpdates.swift || { echo "MenuUpdates.url doesn't point at gist $gist" >&2; exit 1; }
gh gist edit "$gist" -f MenuData.json "$menu"
# GitHub caches the file for up to 5 minutes; wait until the new copy is served.
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if curl -fsS -H "Cache-Control: no-cache" "$url" | cmp -s - "$menu"; then echo "Published: $url"; exit 0; fi
  sleep 30
done
echo "Uploaded, but GitHub is still serving the old copy. Check again in a few minutes." >&2
exit 1
