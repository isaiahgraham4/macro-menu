# Native Macro Menu

Open `MacroMenu.xcodeproj` and run the MacroMenu scheme on iOS 18 or later.
The app uses SwiftUI and requires no third-party packages or API keys.

## Features

- Find: combinations of up to three items from one restaurant, ranked by fit,
  calories or protein; optional macro caps.
- Best: search all 1,307 bundled menu foods from 12 restaurants, filter by restaurant/category and
  compare nutrition and protein density. Source links are in the toolbar.
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
- Meal: "Log again" logs yesterday's meal for the chosen meal time, or one of your
  most-logged meals, in one tap, without touching the meal you're building.
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
- Customising orders: McDonald's removals and extras (extra patty, fillet, egg,
  cheese, bacon, sauce; official energy, estimated macros except for parts sold
  on their own), GYG, Subway (full official nutrition from its per-ingredient
  guide; 6", footlong, regular wraps, breakfast, and cheese/dressing on regular
  salads), and Hungry Jack's and KFC cheese, bacon and extra patties (the
  difference between two burgers sold with and without them).
- Pinned foods: touch and hold a food (or use the pin on its details) to keep it
  at the top of the food chooser and the Today "+" menu. Up to 8; stored in
  `AppData.pinned` with a copy of the food, shown with current menu figures.
- Opening hours (Map tab, nearest restaurant on orders, and suggested orders on Find): "Open · closes 10:00 pm" or
  "Closed · opens 8:00 am" (orange within an hour of closing); tap for the week, today in bold. Hours come from
  OpenStreetMap (`PlaceHoursStore.swift`; the `opening_hours` reader and status are in `PlaceHours.swift`), free with no
  key or account. Restaurants on screen are looked up together in one Overpass API request, and answers are kept on the
  phone for a week (three days when a restaurant has no hours mapped). Each phone sends at most 60 requests a day
  (`DailyLimit`) and pauses five minutes after a failure, so a bug or an outage can't flood the free server. Apple doesn't let apps read hours, so restaurants
  without mapped hours offer Apple's place card instead, and map pins always show Apple's callout with hours. In
  Melbourne about 1 in 5 of these chains' restaurants have hours on OpenStreetMap; anyone can add them at
  openstreetmap.org and the app picks them up within a week. The week view credits "© OpenStreetMap contributors", which
  the ODbL licence requires.
  Debug builds can show sample hours with `-debug.demoHours YES`.
- Open now only (Find's suggested orders and Best choices, on by default): leaves out chains whose closest restaurant
  is closed, says which ones in the footer, and offers "Show anyway" if every chosen restaurant is closed. Your own
  foods are never hidden, and nothing is hidden when choosing a food to log. Unknown hours count as open
  (`OpenNow` in `PlaceHoursStore.swift`).
- Delivery (under the hours on the same rows): "Delivery likely" within 5 km, "Delivery may reach you" up to 8 km,
  otherwise "Probably too far to deliver", and "Closed, so no delivery right now" when the hours say it's closed
  (`Delivery.swift`). Distance is from your location, or the place searched on the Map tab. It's an estimate:
  delivery apps don't let other apps check an address. Tapping it lists Uber Eats, DoorDash, Menulog and the chain's
  own app to confirm and order.
- Log again widget (Home Screen and Lock Screen): the usual meal for this time of
  day, then pinned foods, each with a log button. `LogAgainIntent`
  (`Shared/LogAgain.swift`) is a Live Activity intent, so it runs in the app's
  process and logs through the normal store (Health and iCloud included). If it
  ever runs in the widget instead, the request is queued in the App Group and
  logged when Leanr next starts. A repeat tap within 10 seconds is ignored.
- Siri and Shortcuts: "Log my usual lunch in Leanr" logs the meal most often
  logged to that meal time in the last 30 days. "What fits at KFC in Leanr"
  runs the finder against what's left of today's targets (capped at your typical
  meal before 4 pm). The logic is in `Assistant.swift`, the intents in
  `LeanrIntents.swift`; both use the shared store in `AppServices.swift`.
- Meal reminders (Settings → Targets): breakfast, lunch, dinner and a late-night
  one, each ticked on and timed separately (or "Turn on all reminders"). A meal
  reminder only goes out if nothing is logged to that meal; the late-night one
  (the Snacks slot, 9:30 pm by default) only if nothing at all was logged that day.
  Six messages per reminder rotate by day (`MealReminders.message`), in a fixed order so
  rebooking doesn't change tomorrow's wording. Choosing reminders is a Premium
  feature (`Premium.isUnlocked`; locked clears the booked meal reminders and keeps
  the weekly review). Notifications are booked two weeks ahead and
  rebooked when the log changes. The optional Sunday 6 pm weekly review
  notification carries that week's summary.
- Your week (Today): days logged, averages over logged days, protein and calorie
  days, weight-trend change and most-logged meals, with a shareable card.
- CSV export (Settings → Your data): every logged food, or daily totals with that
  day's targets. Figures a food didn't list are blank, and an "Incomplete" column
  names partial totals.
- Menu updates: `MenuUpdates.swift` can download a newer `MenuData.json` (known
  format, newer, every item valid; the bundled copy is the fallback), but it's
  switched off (`MenuUpdates.url` is nil) because the menu isn't hosted anywhere.
  Settings → About shows the date of the menu in use.

Restaurant nutrition is a September 2026 snapshot, not live data. Zambrero (July 2026 sheet; burritos, bowls,
nachos and tacos without sauce, sauces as extras) and Boost Juice (original and medium sizes; boosters aren't
published) are included. Three Zambrero per-serve rows misprinted on the sheet are worked out from its per-100 g
figures. Missing values remain unknown. A macro filter excludes items without the required figures. Totals mark
partial nutrient data.

Prices are switched off for now because they vary too much between stores. `Scripts/menu-source.js` keeps them, and
`SHOW_PRICES` in `Scripts/export-menu.cjs` leaves them out of `MenuData.json`. The price fields stay in the data model
so older backups still open, and the finder's budget and price sorts are kept for when prices return.

## Data sources

Restaurant figures come only from each chain's own published nutrition information, re-entered as facts (no copied
descriptions, photos or logos). Each chain in `Scripts/menu-source.js` records its source (`src`), how it was collected
(`how`) and a link (`url`); every food's page shows these under Source with the menu snapshot date. Items a chain
publishes no figures for are left out rather than filled from third-party databases. Permission requests and the
removal process are in `AppStore/data-permissions.md`.

## Storage and transfer

All tabs use one observable store. Changes are written atomically to
`Application Support/MacroMenu/app-state.json` inside the app's device container.
Existing `foods.json` saves are migrated on first launch; the original is retained.
A corrupt save is preserved and modifications are blocked instead of overwriting
it. Historical log entries and saved meals retain their nutrition snapshots.
Saved meals open in an editor (Meal tab → tap a saved meal): rename it, change amounts, add foods from the menu or
swipe items out, then Save (`SavedMealEditor`, `AppStore.updateMeal`, with Undo).
Logged meals on Today open the same way (tap one): rename, change the meal time or move it to another day, change
servings, add foods or swipe them out, then Save (`LogEditor`, `AppStore.updateLog`, with Undo).

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

The menus live in `ios/Scripts/menu-source.js` (chains, every item's published
figures and the rules for customising orders). The exporter turns that into
`ios/MacroMenu/MenuData.json`, stamped with a format number, a content fingerprint
and a publish date that only changes when the menu does. The Macro Menu web app
(`index.html`, `docs/`) is no longer updated; don't edit or publish it.

The exporter runs the menu source's data and pure modifier functions,
then adds ingredient removals from `mcd-ingredients.json`, `subway-ingredients.json`
and Hungry Jack's with/without-cheese pairs. Subway builds are checked against
each item's published total and skipped (with a warning) if they drift over 3%.

Title font: Bebas Neue (SIL Open Font License, `ios/Licenses/BebasNeue-OFL.txt`).
Fonts whose licences don't allow redistribution live in `ios/LocalFonts/`, which
is ignored by git.
`MenuData.json` is included automatically by Xcode's synchronized app folder.

App Store and TestFlight steps, privacy answers, screenshots and a listing draft are
in `AppStore/README.md`.

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
