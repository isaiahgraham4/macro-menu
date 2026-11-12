# Shared foods

People can share a food they've added so everyone else finds it in search (marked "Community") and when they scan its barcode. Code: `MacroMenu/SharedFoods.swift`. Sharing is off for every food until the person turns on "Share with other Leanrrr users" in the food editor. The first time, they're asked to agree to the rules.

## How it works

- Storage is the **public database** of the existing container `iCloud.com.isaiahgraham.MacroMenu`. There's no server or account to run. People need to be signed in to iCloud to share, but not to see shared foods.
- Each shared food is one `SharedFood` record named `food-<the sharer's food ID>`, so editing the food replaces the record. Turning sharing off or deleting the food deletes the record. Changes go through a small queue in UserDefaults, so they still upload later if the phone was offline.
- The app downloads every shared food, report and removal (newest first, up to 5,000 of each) at launch and on foreground, at most every 6 hours, and caches them in `community-foods.json`. Search works offline. Barcode scans fall back to a live query on `barcodeKey`, the barcode without leading zeros, once the list is past the cap.
- Barcode order is: your own foods, then Open Food Facts, then shared foods.
- Shared foods rank after published figures that match a search equally well. They never feed suggestions, photo or text matching, Siri or orders.

## Keeping it clean (App Store guideline 1.2)

| Requirement | What the app does |
|---|---|
| Filter objectionable content | `SharingRules.problem`: a whole-word strong-language and slur filter, no links or phone numbers, name 3–80 characters, serving required, carbs and fat required, energy within 15% (or 25 Cal) of 4/4/9 from the macros (alcohol excepted), macros no heavier than the serving, sane maximums. The same check runs on every record the app reads back, so a record written outside the app is ignored. |
| Report | Food page → Report this food (reason picker). The food is hidden for the reporter immediately. **3 different reporters hide it for everyone.** One report per person per food (`report-<food>-<user>`). |
| Block | Food page → Hide foods from this person. It's kept on the device; Settings → Shared foods brings them back. |
| Remove | A `SharedFoodRemoved` record with `foodRecord` = the food's record name hides it for everyone. Only the Moderator role can write these. |
| Terms agreed | One-time alert before the first share. Terms.md has a "Foods you share" section with zero tolerance and a 24-hour review promise. |
| Contact | `AppInfo.contactEmail` (still nil, so the App Store support link is used). |

## One-time setup before TestFlight or release

1. **Signing:** the app entitlement now lists `CloudKit` beside `CloudDocuments`. In Xcode open the MacroMenu target → Signing & Capabilities and check that iCloud shows CloudKit ticked for `iCloud.com.isaiahgraham.MacroMenu`, so automatic signing refreshes the profile.
2. **Schema:** import `cloudkit/schema.ckdb` into Development. A management token comes from CloudKit Console → Settings → Tokens.
   ```
   xcrun cktool save-token --type management
   xcrun cktool import-schema --team-id <TEAM> --container-id iCloud.com.isaiahgraham.MacroMenu --environment development --file cloudkit/schema.ckdb
   ```
   Or add the record types and indexes by hand in CloudKit Console. The indexes that matter: `___modTime` SORTABLE and `___recordID` QUERYABLE on all three types, `barcodeKey` QUERYABLE, `foodRecord` QUERYABLE.
3. **Moderator:** in CloudKit Console → Development → Public database → Records → `Users`, find your own user record and add the `Moderator` role to it. Do the same in Production after deploying.
4. **Deploy to Production:** CloudKit Console → Deploy Schema Changes. TestFlight and App Store builds use Production, so nothing works there until this is done.
5. **App Store Connect:** App Privacy → add **User Content → Other User Content**, used for App Functionality, not linked to identity, not used for tracking. Update the hosted privacy policy gist from `MacroMenu/Legal/PrivacyPolicy.md`. In the review notes, say where Report and Hide are and that reports are reviewed within 24 hours.

## Reviewing reports

CloudKit Console → Production → Public database → query `SharedFoodReport` sorted by modification date. Look up the `foodRecord` in `SharedFood`. To take one down, create a `SharedFoodRemoved` record with `foodRecord` set to that record name and an optional `note`, acting as your own iCloud account (the one with the Moderator role). Every phone hides it the next time it refreshes, at most 6 hours later.

To stop one person sharing entirely, remove each of their foods the same way. The anonymous creator ID is shown on the record.

## Trying it

- Launch with `-demoCommunityFoods` to use four made-up shared foods kept in memory, without iCloud. One of them has three reports and stays hidden. Barcode `9310000000017` finds the protein bar.
- With iCloud: sign in on the simulator or a device, share a food from one Apple Account, then search for it from another. Your own shared foods never show as Community on your own phone.

Checks: `bash Tests/run-checks.sh` covers the sharing rules and the content filter.
