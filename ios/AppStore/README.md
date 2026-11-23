# App Store and TestFlight

Everything for a first TestFlight build is ready except the upload itself, which is done from your Apple account.

## Upload a build

1. In App Store Connect, create the app if it isn't there yet: **Apps → + → New App**, platform iOS, name **Leanrrr**,
   bundle ID `com.isaiahgraham.MacroMenu`, SKU of your choice.
2. In Xcode, open **Window → Organizer → Archives**, pick the latest **Leanrrr** archive and press **Distribute App →
   App Store Connect → Upload**. Or make a fresh one with **Product → Archive**.
3. When the build finishes processing, add testers under **TestFlight**. Internal testers need no review.

Before each new upload, raise the build number (`CURRENT_PROJECT_VERSION`) in the MacroMenu and LeanrWidgets targets.

## Privacy and legal

- The privacy policy and terms are in `MacroMenu/Legal/` (`PrivacyPolicy.md`, `Terms.md`) and show in the app under
  Settings → Privacy and legal. The privacy policy is hosted as a public gist for App Store Connect:
  https://gist.github.com/isaiahgraham4/26dad078a14afa56462a3438de13cc98 (not the Macro Menu site, which is no longer
  updated). When `PrivacyPolicy.md` or the contact email changes, update the gist to match.
  The terms of use are hosted the same way (since 16 Nov 2026):
  https://gist.github.com/isaiahgraham4/239ce4f41914e5991bb0eb1bbff215aa. Subscriptions need a working terms link in the
  listing, so it's at the end of the description below; update that gist whenever `Terms.md` changes.
  The consumer health data privacy policy (`ConsumerHealthData.md`, added 22 Nov 2026 for Washington's My Health My
  Data Act and Nevada's similar law) shows in Settings → Privacy and legal. The Act also wants it linked from the App Store
  page. Hosted 22 Nov 2026: https://gist.github.com/isaiahgraham4/736ca5bc1111b2d52fc67b60f1c804b8 — linked as the last line
  of the description ("Consumer health data: …") from version 1.3 (created 22 Nov 2026, Prepare for Submission). The privacy gist links to it (its own
  "Consumer health data" section, which keeps the older-version notes); update both when `ConsumerHealthData.md` changes.
  Both files also carry a `{{DEVICE}}` placeholder: the app shows iPhone or iPad, and the hosted copies say
  "iPhone or iPad". Fill both placeholders before updating a gist.
- **App store age laws (Texas SB 2420, in force for new Texas Apple Accounts since 4 June 2026; Utah 6 May 2027,
  Louisiana 1 July 2027).** `AgeCheck.swift` asks the App Store for the age category (Declared Age Range API, gates 13/16/18)
  only where `requiredRegulatoryFeatures` (iOS 26.4+) or `isEligibleForAgeFeatures` (26.2–26.3) says the law applies, and
  blocks anyone under 13 (the terms' minimum age). The category stays on the device. Needs the
  `com.apple.developer.declared-age-range` entitlement (added 22 Nov 2026, Build 124). Keep the age rating for the app and
  every in-app purchase current in App Store Connect. **Don't change Leanrrr's age rating** without first building the
  significant-change flow: Texas treats a new rating as a significant change needing a parent's consent for under-18s
  (`AppStore.ageRatingCode` to notice it, PermissionKit `SignificantAppUpdateTopic` to ask). Apple blocks the app itself
  when a parent withdraws consent (`RESCIND_CONSENT` server notification), so no server is needed for that.
- `AppInfo.contactEmail` in `MacroMenu/LegalView.swift` is isaiahgraham.app@gmail.com (set 16 Nov 2026). It shows in the policies
  and as the Contact row in Settings, and both hosted gists carry it. Use the same address for support in App Store Connect.
- `MacroMenu/PrivacyInfo.xcprivacy` declares no tracking and two collected data types for shared foods (Other User Content and User ID, not linked, App Functionality only). `LeanrWidgets/PrivacyInfo.xcprivacy` declares no tracking and no collected data. The app's only required-reason API is UserDefaults,
  for its own settings (reason `CA92.1`).
- App Privacy answers in App Store Connect (filled in 15 Nov 2026, privacy policy URL set to the gist): **Data Not Linked to You: User Content (Other User Content) and Identifiers (User ID)**, both for App Functionality and not used for tracking, because of shared foods. Nothing else is collected. Location is only used on the device and by Apple Maps,
  which Apple doesn't count as collection by the developer. Food logs, weights and targets stay on the device, in the
  user's iCloud and (if connected) in Apple Health. Barcode lookups send only the barcode number, and packaged-food searches only the search words, to Open Food Facts.
- Weights read from Apple Health never go to iCloud (App Review Guideline 5.1.3). Weights entered in Leanrrr do.
- Photo of your meal and Visual Intelligence results run on the device and use Leanrrr's own data; nothing is sent, so the
  privacy answers don't change. Naming the foods uses Apple Intelligence's on-device model (iOS 27, where the iPhone has it)
  and otherwise Apple's built-in Vision image classifier (`MealVision.swift`, `VisionFoodLabels.swift`), which works on
  every supported iPhone. Restaurant items are never ticked from a photo unless the photo shows that restaurant's brand.
- No third-party SDKs, analytics, ads, cookies or web views. Network requests go only to Apple, Open Food Facts
  (a barcode number, or search words when the user taps Search packaged foods), GitHub (downloading the menu file,
  which carries nothing about the user) and, only when the user imports a recipe from a link, that recipe page itself
  (a plain HTTPS request for the page), without cookies. None of these count as collection, so the answer stays
  Data Not Collected.
- Describe your meal reads the words on the device (Apple Intelligence's on-device model on iOS 26+ where available,
  otherwise `FoodPhrase`), and the Apple Watch app gets today's totals and quick-log options straight from the iPhone over
  WatchConnectivity. Neither sends anything off the device, so the privacy answers don't change.
- Settings → Delete all my data erases the device data and the iCloud copy, can remove what Leanrrr saved to Health, and
  turns iCloud sync off.
- Age rating: answer the questionnaire honestly (no objectionable content). The terms ask for 13+ and the target
  estimate is 18+.
- Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`. The app uses only standard HTTPS.
- Fonts: Roboto (Apache 2.0) and Bebas Neue (SIL OFL 1.1). Their licence texts ship in `MacroMenu/Legal/` and show under
  Settings → Acknowledgements, with the Open Food Facts credit (ODbL) and the USDA FoodData Central credit (public
  domain; `MacroMenu/GenericFoods.json` is built by `Scripts/generic-foods.py`).

## Even Leanrrr (subscriptions)

**Switched on 15 Nov 2026.** `Premium.subscriptionsEnabled` in `MacroMenu/Theme.swift` is `true`: the Even Leanrrr row shows
at the top of Settings, Premium features lock without a subscription and StoreKit is asked at launch. Terms.md and
PrivacyPolicy.md describe the subscription again (effective 15 Nov 2026); the hosted privacy gist must match before review.
Setting the switch back to `false` unlocks everything and hides the row, but the legal text would then need the old "Cost"
section back (it's in git history, `AppStore/even-leanr-legal.md` before 15 Nov 2026).

The subscription is called **Even Leanrrr** everywhere users see it. In code it's still "Premium" (`Premium.isUnlocked`,
`PremiumView`) and the product IDs keep `premium`; users never see those, and product IDs can't be renamed once created.

`MacroMenu/Purchases.swift` reads StoreKit 2 entitlements; `MacroMenu/PremiumView.swift` is Apple's subscription view with
the features list; `Premium.isUnlocked` (Theme.swift) is what the screens, widgets and reminders check. Premium gates: menu
scanning (Today → Scan a menu) and Plan ahead (both since 15 Nov 2026; planned meals still show and tick off), app
colours (presets and custom), colour packs other than Classic, background tints other than Cream, app icons, macro colours, the
Calories & macros and All targets widgets, and choosing meal and water reminders and the weekly review time.

In App Store Connect → the app → Monetization → Subscriptions (all set up 15 Nov 2026):

1. Subscription group "Even Leanrrr" (ID 22580539). Its English (Australia) display name is "Even Leanrrr" with the custom
   app name "Leanrrr", because the App Store Connect app name is still "Leanr".
2. Three auto-renewable subscriptions with these exact product IDs (hard-coded in `PremiumAccess.swift`):
   level 1 `com.isaiahgraham.MacroMenu.premium.yearly` (1 year, A$35.00), level 2 `com.isaiahgraham.MacroMenu.premium.monthly`
   (1 month, A$10.00) and level 3 `com.isaiahgraham.MacroMenu.premium.weekly` (1 week, A$5.00). Round prices come from
   "See Additional Prices" in the price picker. Other countries use Apple's conversions from the AUD price (US$22 / US$6 / US$3).
3. Each is on sale in all 175 countries, has an English (Australia) display name and description, and a free 1-week
   introductory offer for new subscribers with no end date. A trial is once per Apple Account across the whole group.
   `Configuration/Leanr.storekit` mirrors these prices and trials. Its descriptions were changed on 16 Nov 2026 to
   "Menu scans, plans, colours and widgets, billed yearly" (and monthly, weekly); App Store Connect has the same wording
   since 17 Nov 2026 (the monthly plan had no display name until then). Each subscription's Review Information has
   `AppStore/Review/even-leanrrr-subscriptions.png` (added 15 Nov 2026): the Even Leanrrr screen with all three plans,
   taken from Xcode with the StoreKit file and a 9:41 status bar. Retake it if the screen or the prices change.
4. Accept the Paid Apps agreement and add banking and tax details, or the products won't load.
5. Add the subscriptions to the version you submit; Apple reviews them with the app.
6. The Premium screen shows the required subscription wording and links to the privacy policy and terms itself. Also put the
   hosted privacy policy URL in App Store Connect, and mention subscription terms in the app description.

Codes for friends: "Redeem a code" at the very bottom of Settings (shown until Premium is on) and the Redeem Code button on the Even Leanrrr
screen both open Apple's offer-code sheet. App Review rule 3.1.1 rules out Leanrrr's own unlock codes, so make them in
App Store Connect → Subscriptions → pick a plan → Subscription Prices → Offer Codes: choose "Free" for up to 12 months,
eligibility "New, Active and Expired subscribers" as needed, then generate one-time codes (download as CSV) or a custom code
like a word you text to friends. A redeemed code starts the subscription free; it renews at the normal price at the end
unless the friend turns off auto-renew in their Apple Account. Codes only work once the Paid Apps agreement is active, and
the offer-code sheet doesn't open in the simulator.

Testing without paying: in Xcode, Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration →
`Configuration/Leanr.storekit` (set it on a scheme you don't commit), then run on a simulator. Purchases are free there, and
Debug → StoreKit → Manage Transactions can expire or refund them. On TestFlight, purchases use Apple's sandbox and cost nothing.
In Debug builds only, launching with `-LeanrForcePremium` shows the unlocked screens without buying.

## Screenshots

`Screenshots/` holds five 6.9-inch iPhone screenshots (1320 × 2868, retaken 16 Nov 2026 on the iPhone 18 Pro Max
simulator with a 9:41 status bar and the same sample data as the iPad set):

1. Today: calories left, protein and the Log food card.
2. Find: an order that fits your calories and protein.
3. Progress: your week, with days logged, averages and protein days.
4. Weight: scale readings and the smoothed trend.
5. Meal: Log again.

App Store Connect's required iPhone slot is the 6.1/6.3-inch size, not 6.9-inch. `Screenshots/iPhone-6.3/` holds the same
five scaled to 1206 × 2622 (`sips -z 2622 1206`; the two shapes differ by under two pixels). On 16 Nov 2026 the 6.3-inch
set went into the required "medium display" slot and the full-size set into the optional "large display" slot (Media
Manager), with the iPad and Watch sets in theirs.

Later on 16 Nov 2026 both iPhone slots were replaced with the seven campaign slides from `Campaign/final-1206x2622/`
(medium) and `Campaign/final-1320x2868/` (large). The five plain screenshots above were removed from the listing but stay
in the Asset Library and in this folder. iPad, Watch and iPhone Duo slots were not changed.

On 17 Nov 2026 the iPhone Duo slot got seven slides from `Campaign/final-duo-2007x2853/` (2007 × 2853, built by
`Campaign/duo.py` from cover-screen captures in `Campaign/raw/duo/`; the Duo simulator captures its cover screen while
closed with `simctl io <udid> screenshot --display=primary`). The product page header is `Campaign/header/`
(5244 × 2950 PNG, built by `Campaign/header.py`; App Store Connect takes PNG only). Each device shows a different slice
of the header, so its message sits in the band y 700-1700, centred; the measured crops are noted in `header.py`.

On 17 Nov 2026 seven iPad campaign slides were built in `Campaign/final-ipad-2064x2752/` (2064 × 2752) by
`Campaign/ipad.py` from Gemini plates in `Campaign/native/ipad/` and captures in `Campaign/raw/ipad/`. They replaced the
five plain screenshots in the iPad 13-inch slot the same day (the plain ones stay in the Asset Library). Not submitted.

`Screenshots/iPad/` holds five 13-inch iPad screenshots (2064 × 2752, taken 16 Nov 2026 on an iPad Pro 13-inch (M5)
simulator named "Leanr iPad 13"): Today, Find, Progress (Eating), Weight and Meal. `Screenshots/Watch/` holds three Apple
Watch screenshots (422 × 514, the Ultra size, from the "Leanr Ultra 49" simulator): calories left, Log again and water.

To retake the iPad ones: build Debug for the simulator, copy `Screenshots/sample-app-state.json` (two weeks of sample
meals, weigh-ins and water ending 16 Nov 2026, with the protein target met on most days; for a later date run
`python3 Screenshots/make-sample.py <ios folder> <output file> [YYYY-MM-DD]`, which ends on today by default) to
`Library/Application Support/MacroMenu/app-state.json` in the app's data container, set the defaults
`leanr.onboarding.completed` to YES and `tips.enabled` to NO, set the status bar with `xcrun simctl status_bar … override
--time 9:41`, and launch with `-LeanrForcePremium`. The Watch ones are a Debug build of LeanrWatch launched with
`-demoWatch`; the status bar override doesn't work on the watch simulator, so they show the real time.

## Listing draft

Entered in App Store Connect on 17 Nov 2026 (name Leanrrr, category, description, keywords, copyright "2026 Isaiah Graham",
review notes, Free in all 175 countries, Build 111 attached, "Sign-in required" unticked). The support URL is the privacy
policy gist, which carries the contact email. The subscription group and all three plans are in the draft submission; the
app version joins it with Add for Review once the age rating, content rights, review contact and App Privacy Publish are done.

**Subtitle:** Fast food to fit your macros (the limit is 30 characters; "that fits" was 31)

**Promotional text** (entered 18 Nov 2026; 150 of 170 characters; can be changed any time without a new version or review):
Eat out and stay on target. Tell Leanrrr the calories and macros you have left, and it finds the orders that fit, using
each restaurant's own numbers.

The Regulated Medical Device declaration (App Compliance) was answered "No" on 18 Nov 2026.

**Description:**
Leanrrr finds the order that fits. Tell it your calories and protein and it searches the published nutrition figures from
McDonald's, KFC, Hungry Jack's, Subway, Guzman y Gomez, Nando's, Oporto, Red Rooster, Domino's, Grill'd, Zambrero and
more than ten other Australian restaurants for combinations from one restaurant.

- Log meals, scan barcodes and nutrition labels, and see what's left of your day at a glance.
- Take ingredients off: no cheese, no sauce, no mayo, with the figures adjusted.
- Ask in plain words: "40 g protein under 600 Cal at Nando's".
- Vegetarian, no beef, no pork and allergen filters, using each restaurant's own ingredient and allergen information.
- Weight trend that smooths out day-to-day swings, and a measured maintenance estimate from your own data.
- Type or say what you ate and Leanrrr logs it.
- A weekly check-in that adjusts your calorie target to the pace you want, from your own log and weight trend.
- Apple Watch: calories left, calories burnt, and your usual meals, pinned foods and water in a tap.
- Siri: "Log my usual lunch in Leanrrr", "What fits at KFC in Leanrrr" or "Log a glass of water in Leanrrr".
- Meal and water reminders, a Sunday weekly review, widgets, Apple Health and iCloud sync.
- CSV export of your food log and daily totals.

Nutrition figures are the chains' own published data; where a chain doesn't publish a figure, Leanrrr leaves it blank
rather than guessing. Custom orders and recipes are estimates. Leanrrr isn't medical advice and isn't affiliated with
any restaurant.

Leanrrr is free to use. Even Leanrrr is an optional subscription that adds menu scanning (photograph any restaurant's menu
for estimated calories and macros), meal planning, recipe import from a link, app colours, colour packs and icons, two more widgets, and your choice of
meal and water reminders. It's A$35 a year, A$10 a month or A$5 a week in Australia, with a 7-day free trial for new
subscribers. Payment is charged to your Apple Account, and it renews automatically unless you cancel at least 24 hours
before the end of the period, in your Apple Account settings.

Terms of use: https://gist.github.com/isaiahgraham4/239ce4f41914e5991bb0eb1bbff215aa
Privacy policy: https://gist.github.com/isaiahgraham4/26dad078a14afa56462a3438de13cc98

**Keywords:** macros,calories,protein,fast food,drive thru,meal finder,nutrition,diet,tracker,weight

**Category:** Health & Fitness
