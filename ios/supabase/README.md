# Leanrrr food data on Supabase

All the food data the app ships lives in the Supabase project **leanrrr** (ref `dmfmrqvmwvabzkqgdbdw`, Sydney,
free plan, in isaiahgraham4's org). The app still bundles a copy of everything, and only switches to Supabase's
copy when it's newer and passes the same checks (`MenuUpdates.swift`). So the app works offline, on first launch,
and if the project is paused.

| Dataset | Bundled file | Built by |
| --- | --- | --- |
| `menu-AU` | `MenuData.json` | `Scripts/export-menu.cjs` |
| `menu-US` | `MenuData-US.json` | `Scripts/us/build-us-menu.py` |
| `menu-NZ`, `-CA`, `-GB`, `-ZA`, `-IN` | `MenuData-XX.json` | `Scripts/intl/build-intl-menu.py` |
| `generic` | `GenericFoods.json` | `Scripts/generic-foods.py` |
| `survey` | `SurveyFoods.json` | `Scripts/survey-foods.py` |
| `supermarket` | `SupermarketFoods.json` | `Scripts/supermarket-foods.py` |

## Tables

- `public.datasets`: one row per dataset with its `revision` and `published` date. Phones only take a dataset whose date is later than the one they have.
- `public.foods`: one row per food. `kj`, `cal`, `p`, `c`, `f`, `name`, `cat` and `serve` are columns you can edit; everything else (nutrients, diet, modifiers) is in `extra`.
- `public.chains`: each dataset's chains, as JSON.
- `private.bodies`: the finished JSON for each dataset, which is what phones download (`/rest/v1/rpc/dataset?id=menu-AU`). It's rebuilt automatically after any change.

Anyone can read; nobody can write through the API without the upload key. Editing a food or chain in the
dashboard (Table Editor) gives its dataset a new revision and publish time, so phones pick the change up within
about 6 hours. Run `pull.py` before the next build so the app ships the edit, and so the next upload doesn't overwrite it.
Menus are generated from source scripts (`menu-source.js`, the `*-source.json` files), so treat a dashboard edit to a
menu as a quick fix: make the same change in the source too, or the next export puts the old figure back.

## Scripts

```sh
python3 ios/Scripts/supabase/upload.py            # upload every bundled file that changed
python3 ios/Scripts/supabase/upload.py menu-AU    # just one (publish-menu.sh does this, plus the old gist for 1.0-1.1)
python3 ios/Scripts/supabase/pull.py --check      # what's been edited on Supabase
python3 ios/Scripts/supabase/pull.py              # write those edits into the bundled files
```

Usual order after rebuilding a menu: the build steps, `sh ios/Tests/run-checks.sh`, then `upload.py`. An
upload replaces the whole dataset, so pull first if anyone has edited in the dashboard. Both scripts keep
`MacroMenu/FoodLists.json` up to date. That file holds the revisions and dates of the bundled files that don't carry
their own (generic, survey, supermarket), so commit it with them.

The upload key is in the Mac's keychain (service `Leanrrr Supabase upload`, account `leanrrr`); the project stores
only its SHA-256 in `private.upload_keys`. To replace it, make a new key, store it with
`security add-generic-password -U -a leanrrr -s "Leanrrr Supabase upload" -w <key>`, and swap the hash in
`private.upload_keys` (SQL editor).

## Schema

`migrations/` holds the SQL applied to the project, in order. The free plan pauses a project after a week
with no requests; phones checking for updates keep it awake, and a paused project only means phones keep their
current data until it's restored from the dashboard.
