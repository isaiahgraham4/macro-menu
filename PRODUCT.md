# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

The native iOS app, **Leanr** (`ios/MacroMenu.xcodeproj`, SwiftUI, iOS 18+, bundle id `com.isaiahgraham.MacroMenu`), is the primary product and the surface future design work serves. The **Macro Menu** web app (`index.html`, built into `docs/` by `build.py`, served on GitHub Pages and as a Claude artifact) is a secondary companion surface and the source of the bundled menu data.

## Users

General calorie trackers in Australia who often eat fast food. They are logging what they eat, usually to lose or manage weight, and open the app either before ordering (to find what fits what they have left today) or after eating (to log it quickly and see where the day stands).

## Product Purpose

Leanr answers "what can I order here that fits my day?" and then tracks the day. It ranks whole orders from Australian fast-food menus against the user's remaining calories, protein and budget, and logs meals, foods and weight against personal targets. Success is a user who can eat out without blowing their targets and who keeps logging because doing so is fast.

## Positioning

A calorie tracker built around eating out, rather than a generic food diary with restaurant entries added. It works from each chain's own published Australian nutrition figures, not crowd-sourced entries. It builds and ranks complete orders (up to three items from one restaurant) by fit, calories, protein, price or protein per dollar. It knows real Melbourne CBD pick-up prices, lets users customise orders with official ingredient removals, and hands off to the nearest store or the chain's own ordering app.

## Operating Context

- Used on an iPhone, often standing in or near a restaurant, or deciding where to go. Quick one-handed decisions matter more than long sessions.
- Tabs, in order: Today, Find, Map, Meal, My foods. Settings sits in a gear sheet opened from the top right of every tab; Map shows nearby stores.
- Companion surfaces: Home Screen widgets (calories left, macros, targets, streak), Apple Health (writes meals and weigh-ins; reads weight and active energy), iCloud sync between devices, and onboarding (`LeanrOnboarding`).
- Hand-offs out of the app: each chain's AU app via verified universal links, or its App Store page (see `ios/APP-LINKS.md`); Maps for the nearest store.
- Adding foods not on a menu: product barcode lookup (Open Food Facts), on-device nutrition-label photo reading (Apple Vision), or manual entry per serving or per 100 g/mL.

## Capabilities and Constraints

- **Menu data:** 1,026 bundled items across McDonald's, KFC, Hungry Jack's, Subway, GYG, Nando's, Oporto, Red Rooster, Domino's and Spud Bar. It is a September 2026 snapshot of each chain's official AU figures, not live data. Refresh with `node ios/Scripts/export-menu.cjs` from the web source.
- **Unknown stays unknown:** missing nutrients or prices are never filled with zeroes. Filters exclude items lacking the required figure, and totals mark partial data. Estimated values (e.g. McDonald's ingredient-removal macros) are flagged `est`.
- **Prices:** Melbourne CBD pick-up prices only. McDonald's and Hungry Jack's have none (app-only pricing); KFC is partial.
- **Ingredient removals:** McDonald's, GYG, Subway, and Hungry Jack's cheese only. KFC publishes no ingredient nutrition.
- **Tracking:** dated meal logs, target sets (e.g. training and rest days) with optional nutrient goals as at-most or at-least, a Mifflin–St Jeor target calculator, weight log and trend, day history, five-second Undo on logs and deletes.
- **Storage and privacy:** data lives on-device (`app-state.json`), with optional iCloud and Apple Health. No accounts, no third-party SDKs, no API keys. Barcode lookups send only the barcode number, and label photos are processed on-device.
- **Monetisation:** free today. A free + Premium tier is planned soon. `Premium.isUnlocked` is currently a stub returning true; Premium is expected to gate custom app colours and the all-targets widget. Premium pricing, the full list of Premium features and the purchase flow are undecided.
- **Font licensing:** Big Noodle Titling's EULA bars redistribution, so it stays in the gitignored `ios/LocalFonts/` and must not ship in a public build without Sentinel Type's written consent.
- **Terminology:** "Find" builds orders against targets; "Best choices" (inside Find) searches and compares all menu foods; "Map" finds nearby stores; "Meal" is the current meal being built; "My foods" holds the user's own foods, recipes and saved custom orders.

## Brand Commitments

- The iOS app's name is **Leanr**. The web app keeps the name **Macro Menu**, and its localStorage key stays `drivethru-macros.v1` so saved data survives.
- The data sources are part of the brand's honesty: each chain's official published figures, with sources linked in the app.

## Evidence on Hand

- Official nutrition sources per chain, documented in the web app's source links and this repo's notes; Subway ingredient data in `ios/Scripts/subway-ingredients.json`, McDonald's in `ios/Scripts/mcd-ingredients.json`.
- No user testimonials, reviews, download counts, press or outcome data exist. Future work must not invent them, nor claim App Store availability, ratings, or Premium pricing until they are real.

## Product Principles

1. **Official numbers, honestly labelled.** Published figures beat estimates; estimates and gaps are always visible, never hidden or zero-filled.
2. **Decide at the counter.** The core moment is choosing an order fast; getting from "where am I eating" to "what fits" should take seconds.
3. **Logging must be lighter than skipping it.** Re-log, undo, and sensible defaults keep daily tracking effortless for general users, not just enthusiasts.
4. **Your data stays yours.** On-device first, no account, and sync and Health are opt-in.
5. **Free is genuinely useful.** Premium adds personalisation and depth; the core find-and-track loop stays free.
