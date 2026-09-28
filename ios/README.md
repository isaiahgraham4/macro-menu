# Native Macro Menu

Open `MacroMenu.xcodeproj` and run the MacroMenu scheme on iOS 18 or later.
The app uses SwiftUI and requires no third-party packages or API keys.

## Features

- Find: combinations of up to three items from one restaurant, ranked by fit,
  calories, protein, price or protein per dollar; optional budget and macro caps.
- Best: search all 1,026 bundled menu foods, filter by restaurant/category and
  compare nutrition, prices and protein density. Source links are in the toolbar.
- Meal: fractional servings, gram/mL portions when a serving weight is known,
  restaurant adjustments, personal adjustments, saved meals, logging to a chosen
  day, text copying/sharing and shareable meal images.
- My foods: foods per serving or per 100 g/mL, optional and custom nutrients,
  recipes with ingredient portions and a serving yield, and saved custom orders.
  Swipe a saved food right to edit or left to delete.
- Photo labels: Apple Vision reads text on-device. Select the numeric column and
  tap Fill recognised numbers for review. Only explicitly labelled numeric rows
  are suggested; review units, serving basis and all values before saving.
  Complex layouts, menu-board descriptions and unlabelled numbers may require
  manual entry. No Claude service or cloud image processing is used.
- Today: dated meal logs, editable quantities, copying meals to today, day sharing,
  logged-day averages, target sets, optional nutrient goals and an adult
  Mifflin–St Jeor target calculator. "Log again" logs yesterday's meal for the
  chosen meal time, or one of your most-logged meals, in one tap.
- Weight: weigh-ins, a smoothed trend (each day moves the trend 10% of the way to
  the scale), weekly change, and measured maintenance (average logged intake less
  trend change × 7,700 Cal/kg over four weeks; needs 10 logged days and two weeks
  of weigh-ins). The target calculator offers the trend weight and measured
  maintenance.
- Apple Health (Settings): writes each logged meal as a food correlation with its
  nutrients, and weigh-ins; reads weight and active energy. Every sample carries
  its Leanr entry or weight ID, so edits, deletes and undo replace exactly those
  samples. Weights deleted in Leanr that came from Health stay hidden.
- iCloud (Settings): a copy of the app data in the iCloud Drive app container.
  Newest copy wins; if both sides changed since the last sync they're merged by ID
  (a deletion on the other device can come back then). The current meal and
  display settings stay on each device.
- Undo: logging and deletes show a five-second Undo banner.
- Search: forgiving matching (one typo in 4–6 letter words, two in longer ones,
  first letter must match) with exact matches first; recent searches.
- Ingredient removals: McDonald's (official energy, estimated macros), GYG,
  Subway (full official nutrition from its per-ingredient guide; 6", footlong,
  regular wraps, breakfast, and cheese/dressing on regular salads) and Hungry
  Jack's cheese (the difference between with- and without-cheese versions). KFC
  doesn't publish ingredient nutrition.

Restaurant nutrition and prices are the existing web app's September 2026
snapshot, not live data. Missing values remain unknown. A macro or budget filter
excludes items without the required figures. Totals mark partial nutrient and
price data. Custom changes without published prices make that price unknown.

## Storage and transfer

All tabs use one observable store. Changes are written atomically to
`Application Support/MacroMenu/app-state.json` inside the app's device container.
Existing `foods.json` saves are migrated on first launch; the original is retained.
A corrupt save is preserved and modifications are blocked instead of overwriting
it. Historical log entries and saved meals retain their nutrition snapshots.

My foods → Export all app data includes foods, recipes, saved meals, daily history,
targets and the current meal. Import merges by ID after confirmation and keeps a
nonempty current meal. Native version-1 food backups and the web app's
`app: macro-menu, v: 1` exports are supported. Web exports contain no daily history;
imported custom orders retain the exported nutrition snapshot. Backups are for
manual transfer; iCloud sync (above) is automatic when it's on.

## Refresh the bundled menu

From the repository root:

```sh
node ios/Scripts/export-menu.cjs
```

The exporter uses only the web source's menu data and pure modifier functions,
then adds ingredient removals from `mcd-ingredients.json`, `subway-ingredients.json`
and Hungry Jack's with/without-cheese pairs. Subway builds are checked against
each item's published total and skipped (with a warning) if they drift over 3%.

Title font: Bebas Neue (SIL Open Font License, `ios/Licenses/BebasNeue-OFL.txt`).
Fonts whose licences don't allow redistribution live in `ios/LocalFonts/`, which
is ignored by git.
`MenuData.json` is included automatically by Xcode's synchronized app folder.

## Checks

```sh
sh ios/Tests/run-checks.sh
xcodebuild -project ios/MacroMenu.xcodeproj -scheme MacroMenu \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

The checks cover the catalogue, legacy migration, atomic storage and corrupt-save
preservation, native/web backup import, idempotent merging, recipe and partial
nutrition totals, historical targets, label parsing and meal-finder constraints.

Manual device checks: add/edit a food; create a two-ingredient recipe; customise
a GYG order; change servings; save and log a meal; switch dates and target sets;
export/import a backup; scan a label with two nutrition columns; share a meal image.
