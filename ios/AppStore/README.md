# App Store and TestFlight

Everything for a first TestFlight build is ready except the upload itself, which is done from your Apple account.

## Upload a build

1. In App Store Connect, create the app if it isn't there yet: **Apps → + → New App**, platform iOS, name **Leanr**,
   bundle ID `com.isaiahgraham.MacroMenu`, SKU of your choice.
2. In Xcode, open **Window → Organizer → Archives**, pick the latest **Leanr** archive and press **Distribute App →
   App Store Connect → Upload**. Or make a fresh one with **Product → Archive**.
3. When the build finishes processing, add testers under **TestFlight**. Internal testers need no review.

Before each new upload, raise the build number (`CURRENT_PROJECT_VERSION`) in the MacroMenu and LeanrWidgets targets.

## Privacy and legal

- The privacy policy and terms are in `MacroMenu/Legal/` (`PrivacyPolicy.md`, `Terms.md`) and show in the app under
  Settings → Privacy and legal. App Store Connect needs the privacy policy at a public URL: host `PrivacyPolicy.md`
  somewhere other than the Macro Menu site (which is no longer updated), for example a GitHub Gist or Notion page.
- Before release, set `AppInfo.contactEmail` in `MacroMenu/LegalView.swift`. Until then the policies point people to the
  App Support link on the App Store page, and the Contact row in Settings is hidden. Add the same address as the
  support URL or email in App Store Connect.
- `MacroMenu/PrivacyInfo.xcprivacy` declares no tracking, and coarse location (app functionality, not linked) because
  opening hours are looked up on OpenStreetMap's Overpass API using the positions of restaurants near you.
  `LeanrWidgets/PrivacyInfo.xcprivacy` declares no collected data. The app's only required-reason API is UserDefaults,
  for its own settings (reason `CA92.1`).
- App Privacy answers in App Store Connect: Location → Coarse Location, used for App Functionality, not linked to the
  user, not used for tracking. Nothing else is collected. Food logs, weights and targets stay on the device, in the
  user's iCloud and (if connected) in Apple Health. Barcode lookups send only the barcode number to Open Food Facts.
- Weights read from Apple Health never go to iCloud (App Review Guideline 5.1.3). Weights entered in Leanr do.
- No third-party SDKs, analytics, ads, cookies or web views. Network requests go only to Apple, Open Food Facts and
  the Overpass API, without cookies.
- Settings → Delete all my data erases the device data and the iCloud copy, can remove what Leanr saved to Health, and
  turns iCloud sync off.
- Age rating: answer the questionnaire honestly (no objectionable content). The terms ask for 13+ and the target
  estimate is 18+.
- Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`. The app uses only standard HTTPS.
- Fonts: Roboto (Apache 2.0) and Bebas Neue (SIL OFL 1.1). Their licence texts ship in `MacroMenu/Legal/` and show under
  Settings → Acknowledgements, with Open Food Facts and OpenStreetMap credits (both ODbL).

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
Leanr finds the order that fits. Tell it your calories and protein and it searches the published nutrition figures from
McDonald's, KFC, Hungry Jack's, Subway, Guzman y Gomez, Nando's, Oporto, Red Rooster, Domino's, Spud Bar, Zambrero
and Boost Juice for combinations from one restaurant.

- Log meals, scan barcodes and nutrition labels, and see what's left of your day at a glance.
- Take ingredients off: no cheese, no sauce, no mayo, with the figures adjusted.
- Weight trend that smooths out day-to-day swings, and a measured maintenance estimate from your own data.
- Siri: "Log my usual lunch in Leanr" or "What fits at KFC in Leanr".
- Meal reminders, a Sunday weekly review, widgets, Apple Health and iCloud sync.
- CSV export of your food log and daily totals.

Nutrition figures are the chains' own published data; where a chain doesn't publish a figure, Leanr leaves it blank
rather than guessing. Custom orders and recipes are estimates. Leanr isn't medical advice and isn't affiliated with
any restaurant.

**Keywords:** macros,calories,protein,fast food,drive thru,meal finder,nutrition,diet,tracker,weight

**Category:** Health & Fitness
