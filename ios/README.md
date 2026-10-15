# Native Macro Menu

Open `MacroMenu.xcodeproj` and run the MacroMenu scheme on iOS 18 or later.
The app uses SwiftUI and requires no third-party packages or API keys.

## Features

- Find: combinations of up to three items from one restaurant, ranked by fit,
  calories or protein; optional macro caps.
- Best: search all 1,443 bundled menu foods from 14 restaurants, filter by restaurant/category and
  compare nutrition and protein density. Source links are in the toolbar.
- Meal: fractional servings, gram/mL portions when a serving weight is known,
  restaurant adjustments, personal adjustments, saved meals, logging to a chosen
  day, text copying/sharing and shareable meal images.
- My foods (Meal tab → My foods; Edit from a food's details, its swipe or its touch-and-hold menu): foods per serving or per 100 g/mL, optional and custom nutrients,
  recipes with ingredient portions and a serving yield, and saved custom orders.
  Swipe a saved food right to edit or left to delete.
- Photo of your meal (Today → Photo of your meal): foods are named on the device, by Apple Intelligence where the iPhone
  has it, otherwise by Apple's Vision image classifier over the photo and its four quarters (`MealVision`,
  `VisionFoodLabels`: label chains collapse to one food, a dish hides its parts, labels map to everyday-food names). Each
  food is matched to Leanr's own data; only everyday foods, or a restaurant the photo's brand names, are ticked for you.
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
- Progress tab (replaces My foods in the tab bar): weight trend and goal (opens the full weight page), measurements, progress
  photos, and a 7/30/90-day breakdown: calories per day against target, averages, macro split, calories by meal, biggest
  contributors, water and weight change (`ProgressBreakdown`), and a "Your week" section with the full review one tap away.
- Water (Today, below the meals): tap-to-add glasses against a daily target (Settings → Targets → Water target), hold the plus for a bottle
  or any amount. One total a day (`AppData.water`, millilitres), merged by taking the larger, and written to Apple Health
  as one water sample per day when Health is connected.
- Body measurements and progress photos (Weight → Body): waist, hips, chest, neck, upper arm and thigh in cm with change
  since last time and since the first reading (`BodyMeasurements`, synced like the rest). Progress photos are JPEG files in
  Application Support (`ProgressPhotoFiles`), never in `AppData`, so never in iCloud sync, backups or exports; "Delete all
  my data" removes them.
- Left today (Meal tab, a dropdown at the bottom; Settings turns it off): up to three one-meal suggestions for what's left of
  today's calories and protein, from pinned, recently eaten, saved and your own foods, an order at the restaurant you log
  most, then everyday foods (`Assistant.suggestions`).
- Weekly review fibre and sodium: averages over days where every logged food lists the nutrient, against your target or the
  25 g / 2,000 mg guide, with short nudges once two days are counted.
- Steps (Today under Water, Progress, Settings → Targets → Steps goal): the day's steps from Apple Health against a goal
  (default 8,000), and a chart, average and days-at-goal over the Progress range. Read-only and held in memory
  (`HealthSync.steps`), never in `AppData`, iCloud or backups; only the goal (`AppData.stepGoal`) is saved. The Steps widget
  (`LeanrStepsWidget`: small, medium with the last 7 days, and Lock Screen sizes) reads the last week of counts from the
  shared widget snapshot, which Leanr refreshes whenever Health reports new steps (HealthKit background delivery). Google's health
  data has no iPhone API, so only Apple Health is read. Apple Health itself combines the iPhone, a watch and anything
  else that writes steps to it.
- Weekly check-in (on Progress, first in the list by default): measured maintenance (as above) plus the chosen pace in kg a week
  gives a new calorie target, at most 300 Cal from the current one per check-in and never under 1,200 (`CheckIn`). Protein
  stays; carbs and fat are rescaled in the same proportions. Accepting or keeping the targets records the check-in
  (`AppData.checkIns`, last 52) and the next one is due a week later. The pace defaults from the weight goal.
- Describe your meal (Today → Log food, and each meal's +): type or dictate "two eggs, toast with butter and a flat white".
  Apple Intelligence (iOS 26+, on device) splits it into foods and amounts where available, otherwise `FoodPhrase.meal`
  does; each is matched like a photo's foods and amounts become servings from the food's serving weight. Typed restaurant
  items are ticked only when one restaurant has them or a brand was named.
- Dietary needs (Find → Dietary needs): vegetarian, vegan, no beef, no pork, and the 12 allergens on Australia's list (gluten, wheat, milk, egg, soy, sesame, peanuts, tree nuts, fish, shellfish, lupin, sulphites). An item whose restaurant doesn't say either way about an allergen, like Hungry Jack's café drinks it doesn't list, is left out. Orders, Best
  choices, search and the Left today and Plan ahead suggestions only offer items whose restaurant's own words show they
  fit; unknown items are left out (`DietFilter`, `Food.diet`). With needs set, the finder customises by taking things off
  only. Each item's page shows its meats, allergens and "may contain", and where that came from. The data is built by
  `Scripts/diet-info.py` from Grill'd's ingredient lists and allergen statements, Nando's and Hungry Jack's allergens,
  McDonald's and Subway ingredients, Hungry Jack's, Oporto, Red Rooster and Domino's descriptions, and GYG, Zambrero and
  KFC names, plus the restaurants' own allergen guides read by `Scripts/allergen-guides.py` (Domino's, Boost, Oporto, Red
  Rooster, Spud Bar, Schnitz, Zambrero, GYG and Hungry Jack's; items built from parts, like a GYG burrito, use the
  restaurant's own list of what's in them). "May contain" counts as contains, and gelatine counts against no beef and no
  pork. To refresh: `allergen-guides.py fetch`, `allergen-guides.py build`, `diet-info.py build`, then `export-menu.cjs`.
  McDonald's, KFC and Subway publish allergens only behind bot protection, so they have none yet.
- Ask Leanr (Find, at the top): a question in plain words ("vegetarian, 40 g protein under 600 Cal at Nando's") becomes an
  order search. `AskLeanr.parse` reads numbers, restaurants, item counts and needs; with Apple Intelligence, `AskLeanrModel`
  fills in what the rules miss, but only numbers that are in the question. What was understood is shown as chips.
- Plan ahead (Today → Log food): set out meals for today and the next six days against the targets, with suggestions to
  fill the gap. Plans (`AppData.plans`, by day) count for nothing until logged; on the day they appear on Today under
  Planned, and a tick logs each one. Past days are pruned.
- Import a recipe (My foods): paste a link; the page's schema.org Recipe is read (`RecipeImport`). Save it with the site's
  per-serving nutrition, or match the ingredient lines (`FoodPhrase.ingredient`, raw foods first) and open the recipe
  editor filled in.
- Progress sections can be reordered and hidden (the arrows button; `ProgressPart`, stored in UserDefaults).
- Apple Watch (`LeanrWatch` target, embedded in the app): calories left, protein and water, the Log again options (usual
  meals and pinned foods) and a glass of water in a tap. The iPhone sends a `WatchSnapshot` as the application context
  whenever the widgets refresh (`WatchLink`); the watch sends `WatchRequest`s back by message or queued user info, and
  shows the change straight away.
- Watch complications (`LeanrWatchWidgets`, embedded in the watch app): Calories left (circular, corner, rectangular,
  inline), Protein and Water (circular, corner, inline). The watch app keeps the latest snapshot in the App Group
  (`WatchStorage`) and reloads them when a figure they show changes; each timeline has a second entry at midnight that
  starts the day at nothing. With a Leanr complication on the face, the iPhone also sends a complication update
  (`transferCurrentComplicationUserInfo`, about 50 a day), only when calories, protein or water change, so the face
  updates without opening the app.
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
- Opening hours (Map tab and the nearest restaurant on orders): an "Opening hours" button opens Apple Maps' place card,
  which shows the hours and whether it's open now; map pins show Apple's callout too. Apple doesn't let apps read hours
  themselves. Leanr's own hours lookups (OpenStreetMap's public Overpass server) and the "Open now only" filter were
  removed on 6 Oct 2026: Overpass asks public apps not to rely on its free servers, and App Review Guideline 5.1.2
  requires permission before location-derived data goes to a third party.
- Delivery (under the hours button on the same rows): "Delivery likely" within 5 km, "Delivery may reach you" up to 8 km,
  otherwise "Probably too far to deliver" (`Delivery.swift`). Distance is from your location, or the place searched on the Map tab. It's an estimate:
  delivery apps don't let other apps check an address. Tapping it lists Uber Eats, DoorDash, Menulog and the chain's
  own app to confirm and order.
- Water widget (Home Screen and Lock Screen): today's water against the target, with a button that adds one glass
  ("water:<mL>" through `LogAgainIntent`, queued like Log again when Leanr can't run).
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
  `LeanrIntents.swift`; both use the shared store in `AppServices.swift`. "Log a glass of water in Leanr" (or
  "Log water in Leanr", a bottle or a litre) adds to today's water through `LogWaterIntent`, and "How much water have I
  had in Leanr" reads the total back. In Shortcuts, Millilitres sets an exact amount.
  Siri hears "Leanr" as the word "leaner", so `Configuration/App-Info.plist` lists "Leaner" and "Lean R" under
  `INAlternativeAppNames`; every phrase works with either spelling.
- Meal reminders (Settings → Targets): breakfast, lunch, dinner and a late-night
  one, each ticked on and timed separately (or "Turn on all reminders"). A meal
  reminder only goes out if nothing is logged to that meal; the late-night one
  (the Snacks slot, 9:30 pm by default) only if nothing at all was logged that day.
  Six messages per reminder rotate by day (`MealReminders.message`), in a fixed order so
  rebooking doesn't change tomorrow's wording. Choosing reminders is a Premium
  feature (`Premium.isUnlocked`, always true while `Premium.subscriptionsEnabled` is false; locked clears the booked meal reminders and keeps
  the weekly review). Notifications are booked two weeks ahead and
  rebooked when the log changes. The optional Sunday 6 pm weekly review
  notification carries that week's summary.
- Your week (Today): days logged, averages over logged days, protein and calorie
  days, weight-trend change and most-logged meals, with a shareable card.
- CSV export (Settings → Your data): every logged food, or daily totals with that
  day's targets. Figures a food didn't list are blank, and an "Incomplete" column
  names partial totals.
- Menu updates: `MenuUpdates.swift` downloads a newer `MenuData.json` (known
  format, newer, every item valid; the bundled copy is the fallback) from an unlisted GitHub gist, at most every
  6 hours, asking "only if changed" (ETag) so an unchanged menu costs a 304, not 2.9 MB. The request carries nothing
  about the user. Publish with `Scripts/publish-menu.sh` (below).
  Settings → About shows the date of the menu in use.

Restaurant nutrition is a September 2026 snapshot, not live data. Zambrero (July 2026 sheet; burritos, bowls,
nachos and tacos without sauce, sauces as extras) and Boost Juice (original and medium sizes; boosters aren't
published) are included. Three Zambrero per-serve rows misprinted on the sheet are worked out from its per-100 g
figures. Schnitz (October 2026, from the menu's nutrition panels) is included where Schnitz publishes protein, carbs
and fat; its plates, salads, desserts and dips with energy only are left out. Grill'd (October 2026) comes from the panels in
Grill'd's ordering app (`Scripts/grilld-menu.py fetch` then `build`); each burger is on its default bun, with bun and patty
swaps and a few extras that are exact differences between Grill'd's published burgers (`grilld-mods.json`). Grill'd lists no
figures for single ingredients; the one estimate is taking off herbed mayo, sweet chilli mayo, chipotle mayo or tomato relish,
worked out from Grill'd's figures for that sauce as a dip at an assumed 15 g (`SAUCE_GRAMS`), marked `est`. Nando's (October
2026) comes from Nando's online ordering data (`Scripts/nandos-menu.py fetch` then `build`), which has a panel for every item,
option, protein and style: each burger, wrap and pita is on its default protein and style, with swaps that are the difference
between its published panels and extras and removals at Nando's own figures (`nandos-mods.json`). Hungry Jack's and Oporto
add-ons and removals come from their ordering menus (`Scripts/ordering-options.py fetch` then `build`, into `hj-mods.json` and
`oporto-mods.json`): energy is the restaurant's, a sauce also sold as a dip takes the dip's make-up, anything else's protein,
carbs and fat are estimated, and taking something off uses one serve of it, so removals are marked `est`. Red Rooster's
ordering menu gives no figures for its add-ons, and KFC's and Domino's ordering sites block scripted requests. Missing values remain unknown. A macro filter excludes items without the required figures. Totals mark
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

Settings → Export all app data includes foods, recipes, saved meals, daily history,
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
and a publish date that only changes when the menu does. To send it to phones without an app update, run the
checks and then `sh ios/Scripts/publish-menu.sh`, which uploads it to the menu gist and waits until GitHub serves it.
The gist is unlisted (not searchable) and its address is in `MenuUpdates.url`; the GitHub pages site stays off. The Macro Menu web app
(`index.html`, `docs/`) is no longer updated; don't edit or publish it.

The exporter runs the menu source's data and pure modifier functions,
then adds ingredient removals from `mcd-ingredients.json`, `subway-ingredients.json`
and Hungry Jack's with/without-cheese pairs. Subway builds are checked against
each item's published total and skipped (with a warning) if they drift over 3%.

## Refresh everyday foods

Everyday foods (bananas, chicken breast, rice and about 335 others) come from USDA
FoodData Central's SR Legacy data, which is public domain. Download "SR Legacy, CSV"
from https://fdc.nal.usda.gov/download-datasets, unzip it, then run:

```sh
python3 ios/Scripts/generic-foods.py path/to/FoodData_Central_sr_legacy_food_csv_2018-04
```

The script names each food's USDA entry and serving exactly, fails rather than guessing
if one is missing, and writes `ios/MacroMenu/GenericFoods.json`. To add a food, add a
line to `FOODS` in the script. These foods appear in search and Best choices under
"Everyday foods", but never in "An order that fits" or Smarter swaps.

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
