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
  Settings → Privacy and legal. The privacy policy is hosted as a public gist for App Store Connect:
  https://gist.github.com/isaiahgraham4/26dad078a14afa56462a3438de13cc98 (not the Macro Menu site, which is no longer
  updated). When `PrivacyPolicy.md` or the contact email changes, update the gist to match.
- Before release, set `AppInfo.contactEmail` in `MacroMenu/LegalView.swift`. Until then the policies point people to the
  App Support link on the App Store page, and the Contact row in Settings is hidden. Add the same address as the
  support URL or email in App Store Connect.
- `MacroMenu/PrivacyInfo.xcprivacy` and `LeanrWidgets/PrivacyInfo.xcprivacy` declare no tracking and no collected data. The app's only required-reason API is UserDefaults,
  for its own settings (reason `CA92.1`).
- App Privacy answers in App Store Connect: **Data Not Collected**. Location is only used on the device and by Apple Maps,
  which Apple doesn't count as collection by the developer. Food logs, weights and targets stay on the device, in the
  user's iCloud and (if connected) in Apple Health. Barcode lookups send only the barcode number, and packaged-food searches only the search words, to Open Food Facts.
- Weights read from Apple Health never go to iCloud (App Review Guideline 5.1.3). Weights entered in Leanr do.
- Photo of your meal and Visual Intelligence results run on the device and use Leanr's own data; nothing is sent, so the
  privacy answers don't change. Naming the foods uses Apple Intelligence's on-device model (iOS 27, where the iPhone has it)
  and otherwise Apple's built-in Vision image classifier (`MealVision.swift`, `VisionFoodLabels.swift`), which works on
  every supported iPhone. Restaurant items are never ticked from a photo unless the photo shows that restaurant's brand.
- No third-party SDKs, analytics, ads, cookies or web views. Network requests go only to Apple, Open Food Facts
  (a barcode number, or search words when the user taps Search packaged foods) and GitHub (downloading the menu file,
  which carries nothing about the user), without cookies. None of these count as collection, so the answer stays
  Data Not Collected.
- Settings → Delete all my data erases the device data and the iCloud copy, can remove what Leanr saved to Health, and
  turns iCloud sync off.
- Age rating: answer the questionnaire honestly (no objectionable content). The terms ask for 13+ and the target
  estimate is 18+.
- Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`. The app uses only standard HTTPS.
- Fonts: Roboto (Apache 2.0) and Bebas Neue (SIL OFL 1.1). Their licence texts ship in `MacroMenu/Legal/` and show under
  Settings → Acknowledgements, with the Open Food Facts credit (ODbL) and the USDA FoodData Central credit (public
  domain; `MacroMenu/GenericFoods.json` is built by `Scripts/generic-foods.py`).

## Even Leanr (subscriptions): currently switched off

**Subscriptions are off for now.** `Premium.subscriptionsEnabled` in `MacroMenu/Theme.swift` is `false`: every feature is unlocked
for everyone, the Even Leanr row and screen are hidden and StoreKit is never contacted. The legal text that describes the
subscription is held in `AppStore/even-leanr-legal.md` and must go back into Terms.md and PrivacyPolicy.md (and the hosted
privacy gist) when the switch is turned on.

The subscription is called **Even Leanr** everywhere users see it. In code it's still "Premium" (`Premium.isUnlocked`,
`PremiumView`) and the product IDs keep `premium`; users never see those, and product IDs can't be renamed once created.

`MacroMenu/Purchases.swift` reads StoreKit 2 entitlements; `MacroMenu/PremiumView.swift` is Apple's subscription view with
the features list; `Premium.isUnlocked` (Theme.swift) is what the screens, widgets and reminders check. Premium gates: app
colours, app icons, macro colours, the Calories & macros and All targets widgets, and choosing meal reminders.

Before the first release, in App Store Connect → the app → Monetization → Subscriptions:

1. Create a subscription group named "Even Leanr".
2. Add two auto-renewable subscriptions with these exact product IDs (they're hard-coded in `PremiumAccess.swift`):
   `com.isaiahgraham.MacroMenu.premium.yearly` (1 year) and `com.isaiahgraham.MacroMenu.premium.monthly` (1 month).
3. Set the prices: monthly A$5.99, yearly A$49.99 (App Store Connect only offers Apple's price points, and A$49.99 is the
   one nearest $50; `Configuration/Leanr.storekit` uses the same). Add a display name and description for each and a review
   screenshot of the Premium screen. Then on each subscription add a **Subscription Prices → Introductory offer**: Free,
   1 week (7 days), all countries, new subscribers. A trial is once per Apple Account across the whole group.
4. Accept the Paid Apps agreement and add banking and tax details, or the products won't load.
5. Add the subscriptions to the version you submit; Apple reviews them with the app.
6. The Premium screen shows the required subscription wording and links to the privacy policy and terms itself. Also put the
   hosted privacy policy URL in App Store Connect, and mention subscription terms in the app description.

Testing without paying: in Xcode, Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration →
`Configuration/Leanr.storekit` (set it on a scheme you don't commit), then run on a simulator. Purchases are free there, and
Debug → StoreKit → Manage Transactions can expire or refund them. On TestFlight, purchases use Apple's sandbox and cost nothing.
In Debug builds only, launching with `-LeanrForcePremium` shows the unlocked screens without buying.

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
- Siri: "Log my usual lunch in Leanr", "What fits at KFC in Leanr" or "Log a glass of water in Leanr".
- Meal reminders, a Sunday weekly review, widgets, Apple Health and iCloud sync.
- CSV export of your food log and daily totals.

Nutrition figures are the chains' own published data; where a chain doesn't publish a figure, Leanr leaves it blank
rather than guessing. Custom orders and recipes are estimates. Leanr isn't medical advice and isn't affiliated with
any restaurant.

**Keywords:** macros,calories,protein,fast food,drive thru,meal finder,nutrition,diet,tracker,weight

**Category:** Health & Fitness
