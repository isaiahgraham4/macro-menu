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
| Filter objectionable content | `SharingRules.problem`: a whole-word strong-language and slur filter (`ContentFilter`, which also catches look-alike spellings such as "sh1t", "f*ck", "f u c k" and "fuuuck"; the same filter flags every food, custom order and meal name as it is typed and keeps Save off until it is changed), no links or phone numbers, name 3–80 characters, serving required, carbs and fat required, energy within 15% (or 25 Cal) of 4/4/9 from the macros (alcohol excepted), macros no heavier than the serving, sane maximums, only known extra nutrients within per-serving limits, a 6 to 14 digit barcode and a one-word category. Oversized text fields are dropped before decoding, and downloads are converted a page at a time. The same check runs on every record the app reads back, so a record written outside the app is ignored. |
| Report | Food page → Report this food (reason picker: wrong numbers, offensive or abusive, promotes eating disorders or self-harm, illegal content, spam, something else). The food is hidden for the reporter immediately. **3 different reporters hide it for everyone.** Barcode scans that fall back to a live query check the food's reports live too. One report per person per food (`report-<food>-<user>`). |
| Harmful to children | `ContentFilter.promotesHarm` (shared foods only, not private names): pro-eating-disorder words (ana, mia, thinspo, purge…), self-harm and suicide words, and risky weight-loss products (laxatives, DNP, clenbuterol, diet pills). Exact whole words with look-alike digits unmasked, but no shortening of repeated letters, so "Anna's Thins" passes. Added 22 Nov 2026 from the UK Online Safety Act risk assessment. |
| Moderator alert | On the moderator's phone only (`Moderation.moderatorID`, his user record), the app asks for notification permission, registers for remote notifications and saves a `CKQuerySubscription` (`moderator-new-reports`) on `SharedFoodReport` creations and updates. iCloud then sends a push for every report. Needs the `aps-environment` entitlement (added 22 Nov 2026). |
| Block | Food page → Hide foods from this person. It's kept on the device; Settings → Shared foods brings them back. |
| Remove | A `SharedFoodRemoved` record with `foodRecord` = the food's record name hides it for everyone. Only the Moderator role can write these. |
| Terms agreed | One-time alert before the first share. Terms.md has a "Foods you share" section with zero tolerance, no illegal or eating-disorder content and a 24-hour review promise, plus "Complaints and appeals" (anyone can email; acknowledged within 2 working days, decided within 14). |
| Contact | `AppInfo.contactEmail` (isaiahgraham.app@gmail.com), shown in the policies and Settings. |

## Setup status and steps

Done in Development on 15 Nov 2026 through CloudKit Console (no management token needed):
- Sidebar → **Import Schema…** with `cloudkit/schema.ckdb`. It validates first, then replaces the environment's whole schema.
- Moderator role given to Isaiah's user record `_d08d3c20c6b8a5196c36bbfa9ec833d8`: Records → Public Database → query `Users` → open the record → **Security Roles** → tick Moderator → Save. Opening the Console creates your user record in that environment.
- Checked: an anonymous Debug build in the simulator fetched the shared list from Development without errors. A test record `food-console-test` is still there.
- Not yet checked: uploading from the app, since the simulator isn't signed in to iCloud.

Done in Production on 15 Nov 2026: Deploy Schema Changes (it only added the three types, their indexes and the Moderator role), Moderator ticked on the same user record in Production, and a SharedFood query there returns without errors.

Moderator alert subscription (found 24 Nov 2026): Production refused `moderator-new-reports` with "attempting to create a subscription in a production container". Production won't take a subscription type that isn't in its schema, and this one was added on 22 Nov, after the 15 Nov deploy, without ever being saved in Development. To fix: run a Debug build from Xcode on the moderator's iPhone (Debug uses Development), open Settings so shared foods refresh, then CloudKit Console → Development → Deploy Schema Changes (it should list the subscription type). The App Store build retries on its next refresh.

Done 24 Nov 2026: a Debug build on the moderator's iPhone created the subscription in Development (SubscriptionCreate in the Development logs at 08:06 UTC; Update now has to be tapped, since a launch inside 6 hours of the last refresh skips it), then Deploy Schema Changes ran. The deploy dialog showed 0 changes and an empty diff because it doesn't list subscriptions; it deployed anyway. Not yet confirmed that Production accepts the subscription: reinstall the App Store build and tap Update now; no grey line means it worked. From the next build on, the failure shows as a grey "Report alerts aren't on yet" line instead of the shared-foods error.

Still to do (App Store Connect, needs Isaiah):
- App Privacy → add **User Content → Other User Content**, used for App Functionality, not linked to identity, not used for tracking.
- Update the hosted privacy policy gist from `MacroMenu/Legal/PrivacyPolicy.md`.
- In review notes, say where Report and Hide are and that reports are reviewed within 24 hours.
- Try sharing a food from a TestFlight build on a phone signed in to iCloud, then find it from a second Apple Account.

## Reviewing reports

A push notification arrives on the moderator's phone for each report. Log every decision in the Moderation log section of the private Online Safety Act risk assessment doc (date, food record, reason, decision). The assessment is reviewed by 22 Nov 2027 or before shared foods gain images, comments, profiles or messaging.

CloudKit Console → Production → Public database → query `SharedFoodReport` sorted by modification date. Look up the `foodRecord` in `SharedFood`. To take one down, create a `SharedFoodRemoved` record with `foodRecord` set to that record name and an optional `note`, acting as your own iCloud account (the one with the Moderator role). Every phone hides it the next time it refreshes, at most 6 hours later.

To stop one person sharing entirely, remove each of their foods the same way. The anonymous creator ID is shown on the record.

## Trying it

- Launch with `-demoCommunityFoods` to use four made-up shared foods kept in memory, without iCloud. One of them has three reports and stays hidden. Barcode `9310000000017` finds the protein bar.
- With iCloud: sign in on the simulator or a device, share a food from one Apple Account, then search for it from another. Your own shared foods never show as Community on your own phone.

Checks: `bash Tests/run-checks.sh` covers the sharing rules and the content filter.
