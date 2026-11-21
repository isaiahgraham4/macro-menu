# Leanrrr for Android — porting guide

The Android app is a native Kotlin + Jetpack Compose port of the iOS app in `../ios` (SwiftUI). The iOS app is the
reference: same features, same words, same numbers, same rules. Read the Swift file before writing its Kotlin port, and
keep the doc comments' intent (shortened is fine). `../PRODUCT.md` and `../DESIGN.md` describe the product and design.

## Build

```bash
source ~/.android-tools/env.sh
cd ~/drive-thru-macros/android
./gradlew :app:compileDebugKotlin -q --console=plain 2>&1 | grep -E "^e: "     # compile check
./gradlew :app:assembleDebug                                                     # APK
```

Several people may be compiling at once in this checkout. When you compile, only fix errors in **your own files**;
ignore errors in files another feature owns (they're mid-edit). Never commit, and never edit files you don't own except
to add one line to `Startup.kt` (see below).

## Layout

- `data/` — shared foundation (owner: lead). Models (`Models.kt`, a port of Models.swift with identical JSON field names),
  `AppStore` (port of AppStore.swift), `MenuRegion`, `MenuUpdates` (Supabase), `Prefs` (UserDefaults, same key names),
  `Format.kt` (`Double.number`, `dayKey`), `Moments.kt` (owner: Progress).
- `ui/theme/` — colours (`AppAccent`, `ThemeColour`, `PaperTint`, `MacroColours`, `ColourPack`, `TargetStatus`), fonts
  (`LeanrType.*`: Bebas Neue display + Roboto), `LeanrTheme`, `LeanrBackground` (order-pad paper). Use `Leanr.colours`.
- `ui/components/` — `LeanrScreen` (big Bebas title, back arrow, gear, lazy list), `LeanrSection`, `LeanrRow`,
  `CalorieRing`, `TargetBar`, `Chip`, `ChipRow`, `ActionPill`, `ActionTile`, `TileRow`, `StatField`, `BottomActionBar`,
  `SearchField`, `NumberField`, `OptionalNumberField`, `NutritionView`, `FoodRow`, `LogTargetPicker`, `Card`,
  `LabeledValue`, `StoreToasts`, `countingValue`. Add a shared component here only if two features need it; otherwise
  keep it in your package.
- `ui/AppShell.kt` — tabs (Today, Find, Map, Meal, Progress), `Navigator` (`AppServices.nav`), `AppLifecycle.onResume`.
- `feature/<name>/` — one package per feature group. Each owns its package.
- `billing/Premium.kt` — `Premium.isUnlocked` (owner: Settings agent replaces the placeholder with Play Billing).
- `AppServices` (`LeanrApp.kt`) — the single `store` and `nav`. Never create another `AppStore`.
- `Startup.kt` — each feature adds one line in `register()` calling its own `install()` to hook into the store
  (e.g. `store.widgetsRefreshed`, `AppLifecycle.onResume { ... }`).

## Conventions

- **State:** `AppStore` exposes Compose state (`store.data`, `store.catalog`, ...). Mutate only through
  `store.change(undo = "Logged X") { data -> data.copy(...) }`. Feature-specific mutations are extension functions on
  `AppStore` in your package (see `feature/today/WaterLogic.kt`). Data classes are immutable: Swift's `inout` edits
  become `copy(...)`.
- **JSON:** `LeanrJson` matches Swift's Codable output (dates as seconds since 2001 via `AppleInstant`, IDs as
  upper-case UUID strings via `newId()`), so backups move between iOS and Android. Don't change field names.
- **Settings:** `Prefs` with the **same keys** as the iOS `@AppStorage`/`UserDefaults` keys. In Compose use
  `rememberStringPref(key, default)` / `rememberBoolPref`.
- **Navigation:** inside a tab, push screens with simple state (`var detail by remember { mutableStateOf<Food?>(null) }`
  then `if (detail != null) FoodDetailScreen(...) else ...`) and handle system back with `BackHandler`. Sheets are
  `ModalBottomSheet` (Material 3) or full-screen screens. Keep it simple and consistent.
- **Look:** stock Material 3 controls tinted with the accent, Roboto everywhere, Bebas for big titles (`LeanrScreen`
  does this), grouped sections on the paper, big bold numbers, macro colours (`c.protein`, `c.carbs`, `c.fat`) meaning the
  same thing everywhere. No gradients, no emoji, no coloured side borders. Icons: `Icons.Filled.*` /
  `Icons.Outlined.*` from material-icons-extended, picking the closest match to the SF Symbol.
- **Words:** Australian English and the iOS copy, word for word, except where it names an Apple thing:
  Apple Health → Health Connect, iCloud → your Google account backup, App Store → Google Play, iPhone → phone,
  Siri/Shortcuts → app shortcuts, Apple Intelligence → (feature omitted), Live Activity → ongoing notification.
- **Unknown stays unknown:** missing nutrients are never zero-filled; partial totals show "+".
- **Platform mapping:** HealthKit → Health Connect (`androidx.health.connect`), WidgetKit → Glance, Vision/VisionKit →
  ML Kit (barcode, text recognition) + CameraX, MapKit/MKLocalSearch → osmdroid + Overpass API (no API key), StoreKit →
  Play Billing, UserNotifications → `NotificationManager` + `AlarmManager`/WorkManager, CloudKit sync → Android Auto
  Backup (already configured), CloudKit community foods → read-only stub until a backend exists, App Intents → static and
  dynamic app shortcuts, Apple Watch → out of scope.
- **Debug flags:** iOS launch arguments like `-demoMoments` become intent extras if you need them; optional.

## Ownership

| Agent | Package(s) | iOS sources |
|---|---|---|
| Today | `feature/today` | TodayView, QuickAddView, DayBreakdown(View), LeftToday, MealTextView, FoodPhrase, LogExport, TrackingCalendarView, Water, WaterView, WaterWeight, MealPlan, PlanView, LiveDay (→ ongoing notification) |
| Find | `feature/find` | FindView, MealFinder, FoodSearch, FoodMatchList, FoodDetailView, Roulette(View), Copycat/CopycatKitchen(View), Diet/DietViews, Assistant, AskLeanr, MealSwaps(View), Delivery, Insights, SourcesView |
| Meal | `feature/meal` | MealView, MyFoodsView, RecipeImport(View), SharedFoods, SharingRules, MealShare, ShareDesign, ContentFilter (OffensiveTextNote) |
| Progress | `feature/progress`, `data/Moments.kt`, `ui/components/Moments.kt` | ProgressTabView, Weight, WeightView, BodyView, BodyMeasurements, CheckIn(View), WeeklyReview(View), YearReview(View), Steps(View), ActiveEnergy(View), ProgressBreakdown, ProgressPhotoFiles, AchievementsView, Moments, Celebration, MilestoneShare |
| Settings | `feature/settings`, `feature/onboarding`, `billing` | SettingsView, LeanrOnboarding, PremiumView, PremiumAccess, Purchases (→ Play Billing), MealReminders, ReminderPromptView, LegalView, TabTour, FeatureTips/FeatureTipView, WebBackup, theme/colour/icon pickers, DataDeletion |
| Scan | `feature/scan` | BarcodeScanView, BarcodeProduct, LabelParser, VisionFoodLabels, FoodCamera, MealPhoto(View), MealVision, PhotoMemory, MenuScanView, MenuParser, MenuEstimate, MenuCookbook, MenuReader |
| Map/Health/Widgets | `feature/map`, `feature/health`, `feature/widgets` | NearbyView, Places, HealthSync, WidgetSync, Shared/WidgetCalories, LeanrWidgets/*, LeanrIntents (→ app shortcuts) |

Cross-feature entry points already exist as stubs with fixed signatures — replace the body, keep the signature:
`FoodDetailScreen`, `FoodSearch.search`, `DietFilter` (Find); `BarcodeScanScreen`, `LabelScanScreen`,
`MealPhotoScreen`, `MenuScanScreen` (Scan); `MyFoodsScreen`, `FoodEditorScreen` (Meal); `WaterWeight.kilograms`,
`AppStore.addWater`, `AppStore.plan` (Today); `AppStore.logWeight`, `WeightLogSheet`, `Moment`, `earnMoments` (Progress);
`PremiumSheet`, `RemindersSheet`, `Premium.isUnlocked` (Settings); `HealthSync`, `HealthConnectSettings` (Health).
You may add parameters with defaults, never remove or rename.
