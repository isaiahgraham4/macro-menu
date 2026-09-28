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
  Mifflin–St Jeor target calculator.

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
imported custom orders retain the exported nutrition snapshot. Backups provide
manual transfer, not automatic cloud sync. Removing the app removes local data.

## Refresh the bundled menu

From the repository root:

```sh
node ios/Scripts/export-menu.cjs
```

The exporter uses only the web source's menu data and pure modifier functions.
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
