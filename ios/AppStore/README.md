# App Store and TestFlight

Everything for a first TestFlight build is ready except the upload itself, which is done from your Apple account.

## Upload a build

1. In App Store Connect, create the app if it isn't there yet: **Apps → + → New App**, platform iOS, name **Leanr**,
   bundle ID `com.isaiahgraham.MacroMenu`, SKU of your choice.
2. In Xcode, open **Window → Organizer → Archives**, pick the latest **Leanr** archive and press **Distribute App →
   App Store Connect → Upload**. Or make a fresh one with **Product → Archive**.
3. When the build finishes processing, add testers under **TestFlight**. Internal testers need no review.

Before each new upload, raise the build number (`CURRENT_PROJECT_VERSION`) in the MacroMenu and LeanrWidgets targets.

## Privacy

- `MacroMenu/PrivacyInfo.xcprivacy` declares no tracking, and coarse location (app functionality, not linked) because opening
  hours are looked up with Google Places using the name and position of restaurants near you.
  `LeanrWidgets/PrivacyInfo.xcprivacy` declares no collected data.
- With opening hours on, App Privacy answers change from **Data Not Collected** to: Location → Coarse Location, used for App
  Functionality, not linked to the user, not used for tracking. The privacy policy should say Google Places receives
  restaurant names and positions to look up opening hours.
  The app's only required-reason API is UserDefaults, for its own settings (reason `CA92.1`).
- App Privacy answers in App Store Connect: **Data Not Collected**. Your food log, weights and targets stay on the device,
  in your iCloud and (if you connect it) in Apple Health. None of it reaches the developer. Barcode lookups send only the
  barcode number to Open Food Facts, and nearby search uses Apple Maps.
- Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`. The app uses only standard HTTPS.
- A privacy policy URL is required and needs hosting somewhere (not the Macro Menu site, which is no longer updated).

## Screenshots

`Screenshots/` holds 6.9-inch iPhone screenshots (1320 × 2868) from the iPhone 18 Pro Max simulator, with a clean
status bar and a week of sample meals:

1. Today: calories left, protein, weight trend and the weekly review.
2. Find: an order that fits your calories and protein.
3. Your week: days logged, averages, protein days and trend.
4. Weight: scale readings and the smoothed trend.
5. Meal: Log again.

## Listing draft

**Subtitle:** Fast food that fits your macros

**Description:**
Leanr finds the order that fits. Tell it your calories and protein and it searches the official nutrition figures from
McDonald's, KFC, Hungry Jack's, Subway, Guzman y Gomez, Nando's, Oporto, Red Rooster, Domino's, Spud Bar, Zambrero
and Boost Juice for combinations from one restaurant.

- Log meals, scan barcodes and nutrition labels, and see what's left of your day at a glance.
- Take ingredients off: no cheese, no sauce, no mayo, with the figures adjusted.
- Weight trend that smooths out day-to-day swings, and a measured maintenance estimate from your own data.
- Siri: "Log my usual lunch in Leanr" or "What fits at KFC in Leanr".
- Meal reminders, a Sunday weekly review, widgets, Apple Health and iCloud sync.
- CSV export of your food log and daily totals.

Nutrition figures are the chains' own published data; where a chain doesn't publish a figure, Leanr leaves it blank
rather than guessing.

**Keywords:** macros,calories,protein,fast food,drive thru,meal finder,nutrition,diet,tracker,weight

**Category:** Health & Fitness
