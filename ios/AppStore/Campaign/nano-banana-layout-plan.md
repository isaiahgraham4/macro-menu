# Leanrrr Nano Banana Layout Plan

Status: all seven slides finished on 16 Nov 2026. Upload files are in `final-1320x2868/` and `final-1206x2622/`; overview in `contact-sheet.png`; method in `prompt-log.md`. Where a slide differs from the spec below, the finished slide and the prompt log are right: slides 2 and 5 have upright phones, slide 4 has its headline on two lines at the bottom, slide 6 shows one widget, and several headlines have extra line breaks to fit.

## Summary

Create a 7-slide iPhone App Store campaign for Leanrrr from real app screenshots.

Generation path:
- `Nano Banana`
- path used: the Gemini app (gemini.google.com, Isaiah's Pro plan, Create image tool, 9:16), driven in Chrome. The API key in `GEMINI_API_KEY` is on the free tier, which allows no Nano Banana Pro images (HTTP 429, limit 0), so `generate.py` is unused until billing is on.
- the app does not name its image model on screen, so the model is taken to be the Pro plan's Nano Banana image model, not confirmed.

Campaign positioning:
- primary story: a calorie tracker built around eating out. It tells you what to order that fits what you have left today.
- secondary story: logging is fast enough that you keep doing it.
- differentiators, all grounded in the app:
  - ranks whole orders against remaining calories and protein (`FindView`, `MealFinder`)
  - works from each chain's own published figures, 23 Australian chains and 2,979 items in `MenuData.json`
  - removes ingredients and recalculates (`FoodDetailView`, "Remove ingredients")
  - no account, data on the iPhone, optional iCloud and Health (`PRODUCT.md`, `PrivacyInfo.xcprivacy`)

Claims this campaign must not make:
- "free" with no qualifier (Even Leanrrr is a paid subscription and gates menu scanning, Plan ahead, colours and two widgets)
- ratings, download counts, reviews or press
- live prices or live menus (the menu is a bundled snapshot)
- any restaurant logo, mascot or branded packaging in the artwork. Chain names appear only inside the real screenshots.

## Story Spine

- slide 1 sells: you can eat takeaway and still hit your calories (the desire)
- slide 2 sells: the app picks the order that fits what is left (the shift)
- slide 3 sells: the numbers are the restaurant's own (proof)
- slide 4 sells: change the order and the numbers change with it (delivery)
- slide 5 sells: logging a repeat meal takes one tap (delivery)
- slide 6 sells: calories left without opening the app (ecosystem)
- slide 7 sells: no account, your data stays yours (trust)

Slots skipped on purpose:
- "More features" last slide. Seven slides already carry the story, and a pill list would weaken the trust close.
- Progress and Weight. Every calorie tracker has them, so they do not earn a slide. `3-progress.png` and `4-weight.png` stay in reserve if slide 6 is dropped.

Pain, shift, proof, delivery: slide 1 names the tension, slide 2 is the shift, slide 3 is proof, slides 4 to 6 deliver, slide 7 closes on trust.

## Headlines

Three options per slide. The first of each is approved.

### Slide 1
1. `Eat out.<br />Stay on target.` (outcome) Seven syllables, and it says the whole product.
2. `Takeaway that<br />fits your day.` (moment) Warmer, but softer as an opener.
3. `Stop guessing<br />at the counter.` (pain) Strong, but it leads with the negative.

### Slide 2
1. `Orders that fit<br />what's left.` (outcome) Matches the "An order that fits" wording in Find.
2. `500 calories left.<br />Here's dinner.` (moment) Most vivid. Good alternative if you want more punch.
3. `Never scroll<br />a menu blind.` (pain)

### Slide 3
1. `The restaurant's<br />own numbers.` (outcome) The honest-data claim in four words.
2. `Not a stranger's<br />best guess.` (pain) Sharper, but it takes a swipe at other apps.
3. `Straight off<br />the menu board.` (moment)

### Slide 4
1. `Hold the cheese.<br />See the change.` (moment) Shows the feature by doing it.
2. `Your order,<br />your numbers.` (outcome)
3. `No more guessing<br />what you skipped.` (pain)

### Slide 5
1. `Same dinner?<br />One tap.` (moment) Four words, reads at thumbnail size. Changed from lunch to match the screenshot. Final slide says "Same meal?" since the props became a yogurt bowl and smoothie (16 Nov).
2. `Logged before<br />you sit down.` (outcome)
3. `Skip the<br />retyping.` (pain)

### Slide 6
1. `Calories left,<br />at a glance.` (outcome)
2. `Check your day<br />from the Home Screen.` (moment) Clearer but long for one line.
3. `Don't open the app<br />to check.` (pain)

### Slide 7
1. `No account.<br />No sign-up.` (pain) Concrete and checkable.
2. `Your food log<br />stays yours.` (outcome)
3. `Open it.<br />Start logging.` (moment)

Text-only read of the picks: Eat out, stay on target. Orders that fit what's left. The restaurant's own numbers. Hold the cheese, see the change. Same meal, one tap. Calories left, at a glance. No account, no sign-up. It reads as an argument, and the order matters.

## Screenshots

| Slide | File | Status |
| --- | --- | --- |
| 1 | `AppStore/Screenshots/1-today.png` | have it: 984 Cal left ring, protein bar, Log food card |
| 2 | `AppStore/Screenshots/2-find.png` | have it: 500 Cal and 40 g protein, Subway order with "Protein target met" |
| 3 | `Campaign/raw/03-food-detail.png` | recaptured 16 Nov: Grilled Chicken Burrito Bowl (Guzman y Gomez), 660 Cal, protein, carbs and fat row |
| 4 | `Campaign/raw/04-remove-ingredients.png` | recaptured 16 Nov: Grilled Chicken Burrito Bowl, No Cheese switched on (-100 Cal), button reads Log to Dinner · 560 Cal |
| 5 | `AppStore/Screenshots/5-meal.png` | have it: "Same as yesterday's dinner", Log again tiles |
| 6 | `Campaign/raw/06-home-widgets.png` and `06-widget-crop.png` | captured 16 Nov: small Calories left widget only, 984 Cals left today, dark style |
| 7 | none | brand-value slide |

Capture list, all on the iPhone 18 Pro Max simulator at 1320 x 2868, 9:41 status bar, light mode, Classic colours, same sample data as the current set (`make-sample.py`):

- `03-food-detail.png`: a restaurant item's detail screen, scrolled to the top. Item name, restaurant name, the big calorie figure and the protein, carbs and fat row must all be visible. Pick an item with complete figures, no `est` flag and no mismatch warning. A grilled chicken burger or wrap is ideal.
- `04-remove-ingredients.png`: the same or another McDonald's, GYG or Subway item with the "Remove ingredients" section open and one ingredient (cheese) ticked, so the calorie total at the top has already dropped. Both the ticked row and the new total must be on screen.
- `06-home-widgets.png`: the Home Screen with the medium Calories left widget in the top row and the small one beside or below it, on a plain wallpaper. Values should match slide 1 (984 Cal left). Use only the free Calories left widget, since the Calories & macros and All targets widgets are Even Leanrrr only.

## Visual Rhythm Plan

- slide 1 archetype: Typography-led hero with a centred phone
- slide 2 archetype: Hybrid ad (phone plus food on a paper tray)
- slide 3 archetype: Product proof
- slide 4 archetype: Product proof with one enlarged UI fragment
- slide 5 archetype: Contextual (hand tapping, lunch on the table)
- slide 6 archetype: Hybrid ad (widgets as objects, no full app screen)
- slide 7 archetype: Brand-value, no screenshot
- boldest slide: slide 2, emerald field with the largest headline
- cleanest proof slide: slide 3
- richest supporting imagery: slide 2
- contrast-slide plan: slides 2 and 7 are solid Counter Emerald with cream type. The other five are order-pad cream.

Phone placement, so no two neighbours match:
1. centred, upright, bottom third runs off the canvas
2. right of centre, tilted about 6 degrees, food lower left
3. left of centre, upright, enlarged figure fragment on the right
4. centred, low, enlarged "Cheese" row lifted above the phone
5. right, tilted the other way, a thumb coming in from the lower right
6. no phone: one widget card off-centre left
7. no phone: app icon and three small panels

## Consistency Spine

- typography DNA: Bebas Neue style condensed all-caps display for headlines, tight leading, like a menu board. Support lines in a plain geometric sans in the Roboto family, medium weight. No serif anywhere.
- background language: flat warm cream `#F6F2EA` with a fine dot grid in `#664F33` at low opacity, like an order pad. Contrast slides use flat Counter Emerald `#01714C` with the same dot grid in a lighter green. No gradients, no glows, no moving-light effects.
- panel treatment: flat white rounded cards (28 px feel) with a soft, short shadow. No glass.
- device treatment: current iPhone, natural titanium frame, soft contact shadow, straight-on or a slight tilt. Never floating in space with neon rim light.
- accent behaviour: emerald only for emphasis. Macro colours keep their app meaning: protein blue `#007AFF`, carbs orange `#FF9500`, fat red `#FF3B30`.
- negative space: airy. One headline, one focal object, at most one fragment.
- supporting imagery language: unbranded takeaway food shot from above on brown paper or a wooden board (`#E3C496`): a plain burger, a wrap, a salad bowl, a paper bag, a receipt. No logos, no people's faces, hands only.
- follow-up anchor source: `AppStore/Campaign/final-1320x2868/slide-01-eat-out.png`

## Anchor Findings

From slide 1, 16 Nov 2026. Source comes back as a 1536 x 2752 JPEG; the centre crop keeps 1267 px of width and cuts 135 px (8.8 percent) from each side.

- headline width: a 15-character line ("STAY ON TARGET.") filled about 90 percent of the source width and was cut off at both edges after the crop. Asking for it "30 percent smaller" changed nothing. Breaking the headline into three lines of 7 to 8 characters fixed it.
- rule for slides 2 to 7: no headline line longer than 9 characters including spaces. Break long lines rather than asking for smaller type.
- approved slide 1 headline is now three lines: `EAT OUT.<br />STAY ON<br />TARGET.` Same words as approved, one extra break.
- support line: two short centred lines, no wider than the headline. It sits close under the headline; ask for a little more gap on later slides.
- phone: about 72 percent of the cropped width, straight-on, lower third off the canvas. This scale reads well and survives the crop.
- screenshot fidelity: the model redraws the screen. Large text, numbers and layout match the real screenshot; the smallest grey text at the very bottom edge is garbled. Keep small text out of the visible area or crop the phone above it.
- supporting imagery: the paper bag and receipt at the lower left are cut by the crop, which is fine as background. Nothing that must be seen whole can sit in the outer 9 percent.
- the Gemini app's corner mark, if any, falls in the cropped strip; none is visible in the export.
- finishing pass: every slide gets the real screenshot pasted back onto the phone screen and its headline re-set in Bebas Neue and Roboto by script, because the model's own type has rough edges and its redrawn screen is soft at full size. So prompts only need the model to get the layout, phone, background and props right.
- upload files are the `final-*` folders: 1320 x 2868 for the 6.9-inch slot and 1206 x 2622 for the required 6.3-inch slot.
- instructions that worked: naming an empty strip "at least 22 percent of the canvas width" each side of the headline.

## Export Standard

- final export size: `1320x2868`, portrait
- App Store Connect's required slot is 6.3-inch, so also make `export-1206x2622/` with the same normaliser (`--width 1206 --height 2622`)
- run the scripts with `uv run --with pillow python <script>`, because this Mac's Python has no Pillow

## Crop-Safe Rules

- compose every source for a later centre crop to 0.4603
- if the model returns 1024 x 1536: about 707 px of width survives, 158 px is lost each side, so keep everything that must be read inside x = 216 to 808 and y = 92 to 1413
- if the source size is unknown: keep all type, the phone and any fragment inside the middle 60 percent of the width
- side margin at least 8 percent, top 6 percent, bottom 8 percent, after cropping
- only background paper and dots may sit near the edges

## Slide Specs

### Slide 1
- screenshot: `AppStore/Screenshots/1-today.png`
- archetype: Typography-led hero
- headline: `Eat out.<br />Stay on<br />target.` (three lines, see Anchor Findings)
- support: `The calorie tracker for takeaway.`
- chips: none
- purpose: the one-line promise, with the 984 Cal left ring as proof
- layout: app icon small at the top, headline across the top fifth, phone centred below with its lower third cropped by the canvas. Cream order-pad background. A paper bag edge and a receipt corner peek in at the lower left, small.

### Slide 2
- screenshot: `AppStore/Screenshots/2-find.png`
- archetype: Hybrid ad
- headline: `Orders that fit<br />what's left.`
- support: `Ranked by calories and protein.`
- purpose: the differentiator, an order chosen for you
- layout: emerald field, cream headline. Phone right of centre, tilted. The Subway order card is the part of the screen in focus. Lower left: an unbranded salad bowl and wrap on brown paper.

### Slide 3
- screenshot: `Campaign/raw/03-food-detail.png`
- archetype: Product proof
- headline: `The restaurant's<br />own numbers.`
- support: `Official figures from 31 restaurant chains.` (distinct chains across all country menus, 16 Nov 2026)
- purpose: trust in the data
- layout: cream. Phone left of centre. On the right, the calorie and macro row from the same screenshot enlarged as one white card. Nothing else.

### Slide 4
- screenshot: `Campaign/raw/04-remove-ingredients.png`
- archetype: Product proof with fragment
- headline: `Hold the cheese.<br />See the change.`
- support: none
- purpose: customising an order
- layout: cream. Phone centred and low. The ticked "Cheese" row lifted out above the phone as a white card. One unbranded cheese slice sits on the paper beside it.

### Slide 5
- screenshot: `AppStore/Screenshots/5-meal.png`
- archetype: Contextual
- headline: `Same meal?<br />One tap.`
- support: none
- purpose: logging speed
- layout: cream. Phone right, tilted the opposite way to slide 2, a thumb reaching for the "Same as yesterday's dinner" row. A plain dinner plate on a board at the lower left.

### Slide 6
- screenshot: `Campaign/raw/06-home-widgets.png`
- archetype: Hybrid ad
- headline: `Calories left,<br />at a glance.`
- support: `A Home Screen widget.`
- purpose: ecosystem
- layout: cream. The small Calories left widget from `06-widget-crop.png`, enlarged as one dark card off-centre left, slightly tilted. No phone frame, and none of the other Home Screen icons.
- note: only the small widget was captured, in the simulator's dark Home Screen style. The dark card gives contrast on cream. Retake with the medium widget in light style if two cards are wanted.

### Slide 7
- screenshot: none
- archetype: Brand-value
- headline: `No account.<br />No sign-up.`
- support: `Your food log stays on your iPhone.`
- purpose: trust close
- layout: emerald field, cream type, app icon above the headline. Three small flat cream panels below, icon plus two words each: "On your iPhone", "iCloud if you want", "Health if you want". No fake app screen, no padlock clichés.

## Prompt Rules

- preserve screenshots faithfully, do not redraw or restyle the app UI
- convert `<br />` into explicit line blocks in prompts and tell the model not to render the characters
- same headline type style as the anchor on every slide
- no restaurant logos, wordmarks, mascots or branded packaging in generated imagery
- no gradients, glows, emoji or invented claims

## Workflow

1. Headlines approved 16 Nov 2026.
2. Add a Gemini API key as `GEMINI_API_KEY`.
3. New screenshots captured 16 Nov 2026 into `AppStore/Campaign/raw/`.
4. Generate slide 1 as the style anchor, normalise it, check the crop, record the findings here.
5. Generate slides 2 to 7 from the normalised anchor.
6. Normalise to `export-1320x2868/` and `export-1206x2622/`, build `contact-sheet.png`, write `prompt-log.md`.
