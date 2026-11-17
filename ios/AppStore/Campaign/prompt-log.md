# Leanrrr campaign prompt log

Tool: Nano Banana, through the Gemini app (gemini.google.com, Pro plan, Create image, 9:16). Credential source: the signed-in Gemini app, not an API key. `GEMINI_API_KEY` exists but is free tier and returned HTTP 429 for `gemini-3-pro-image`.

## Slide 1, style anchor, 16 Nov 2026

References attached: `AppStore/Screenshots/1-today.png`, `MacroMenu/Assets.xcassets/AppIcon.appiconset/Leanr-Light-1024.png`.

1. First prompt: `prompts/slide-01-eat-out.txt`, sent as one paragraph. Result kept as `native/rejected/slide-01-v1-headline-too-wide.png`. Rejected: the green headline line was cut at both edges after normalising.
2. Follow-up asking for the headline 30 percent smaller and under 58 percent of the width. No visible change. Not saved.
3. Follow-up asking for three headline lines (EAT OUT. / STAY ON / TARGET.), no line wider than half the canvas, a 22 percent empty strip each side, support line on two lines. Result: `native/slide-01-eat-out.png`, normalised to `export-1320x2868/slide-01-eat-out.png`. Crop checked by eye: nothing that must be read is cut.

4. Finishing pass, `finish_slide01.py` (no image model): the real `1-today.png` is pasted back onto the phone screen using a mask taken from the generated image, and the headline band is rebuilt on the same dot grid with the headline set in Bebas Neue and the support line in Roboto from `Shared/Fonts`. Output: `final-1320x2868/slide-01-eat-out.png` and a 1206 x 2622 copy in `final-1206x2622/`. Both are PNG, RGB, no transparency, sRGB profile.

Isaiah approved slide 1 as the anchor on 16 Nov 2026.

## Slides 2 to 7, 16 Nov 2026

Same Gemini chat ("Leanrrr App Ad"), so each prompt leaned on slide 1 for style. Every prompt asked for the art only, with no text outside the phone: phone, background and props. Type, real screenshots and UI cards were added afterwards by `finish.py`.

| Slide | Attached | Asked for | Kept as |
| --- | --- | --- | --- |
| 2 | `2-find.png` | emerald dotted paper, phone right of centre, salad bowl and wrap on a kraft tray lower left | `native/slide-02-orders.png` |
| 3 | `raw/03-food-detail.png` | cream paper, phone left of centre, no props | `native/slide-03-numbers.png` |
| 4 | `raw/04-remove-ingredients.png` | cream paper, phone high, one cheese slice at its lower right | `native/slide-04-cheese.png` |
| 5 | `5-meal.png` | cream paper, phone right of centre, plate of chicken and rice lower left | `native/slide-05-dinner.png` |
| 6 | none | cream paper, no phone, plate with sandwich and coffee cup at the bottom | `native/slide-06-widget.png` (second try; the first had a much denser dot grid and is in `native/rejected/`) |
| 7 | none | emerald paper, no phone, paper bag and blank receipt at the bottom | `native/slide-07-no-account.png` |

What the model did not follow: it placed the phones on slides 2 and 5 against the right edge and made the slide 3 phone wider than asked, so `finish.py` crops those off-centre (x offset 269, 20 and 269 of the 1536 px source) instead of centre-cropping. It also laid the tray and the cheese over the phone; those are kept with hand-drawn outlines in `finish.py`.

Finishing, all by script and all from real assets: screenshot pasted onto each phone screen at one scale in both directions (never stretched), enlarged calorie card on slide 3 and lifted No Cheese row on slide 4 cut from the real screenshots, the real widget capture on slide 6, the real app icon and three drawn panels on slide 7, headlines in Bebas Neue and support lines in Roboto.

Checks: all 14 files are PNG, RGB, no transparency, sRGB; 1320 x 2868 in `final-1320x2868/` and 1206 x 2622 in `final-1206x2622/`. Each slide was looked at as a whole and in full-size close-ups of the screen, the joins and the type.

## Changes asked for by Isaiah, later on 16 Nov 2026

- Slide 5: new art from the same Gemini chat with a yogurt bowl and a berry smoothie in place of the chicken plate (`native/slide-05-dinner.png`; the chicken version is in `native/rejected/`). The generated phone was about 4.5 percent too short for a real iPhone screen, so `finish.py` lengthens its straight section by 107 px (two dot pitches) before pasting the screenshot.
- Slides 1 and 7: the Leanrrr mark and name are printed on the paper bags by `brand.py`, taken from the real app icon and set in Bebas Neue, blended as ink so the paper grain shows through. No image model involved.
- Slide 3 support line now reads "Official figures from 31 restaurant chains." 31 is the number of distinct chains across all five country menus on 16 Nov 2026 (23 in Australia, 7 in the US, 3 in Canada, 2 in the UK, 2 in New Zealand, with repeats counted once). Recount before reusing the slide.

## Slides 3 and 4: item swapped (16 Nov 2026)

- Quarter Pounder (McDonald's) replaced with Grilled Chicken Burrito Bowl (Guzman y Gomez) so no trademarked item name is the hero. Old captures kept in `raw/replaced/`.
- No new generation: same Nano Banana art, new simulator captures pasted by `finish.py 3 4`.
- Slide 4 row crop moved to (60, 1444, 1260, 1588); slide 3 lifted card moved down to 0.482 of the screen height so it covers the Sodium value cleanly.

## Slide 5 headline (16 Nov 2026)

- Headline changed from SAME / DINNER? / ONE TAP. to SAME / MEAL? / ONE TAP. so it fits the yogurt bowl and smoothie. Type only, no new generation. The app screen still reads "Same as yesterday's dinner".

## Uploaded to App Store Connect (16 Nov 2026)

- iOS 1.0 (Prepare for Submission), English (Australia): seven slides in the medium iPhone slot (1206x2622) and the large iPhone slot (1320x2868), in order 01 to 07. Previous five plain screenshots removed from both slots; they remain in the Asset Library. Not submitted for review.

## iPhone Duo slides and product page header (17 Nov 2026)

- Tool: Nano Banana through the Gemini app (same Pro account). The app allows about three images per chat, so the plates came from three chats.
- Header art (`native/header-art.jpeg`, 16:9, no text): emerald dotted background, kraft bag and salad bowl on the left, wrap, paper and coffee cup on the right, centre left empty. Headline, support line and the Leanrrr print on the bag are set by `header.py`.
- Duo plates (`native/duo/`, 3:4, no text, no device): 01-bag, 02-tray (green), 04-cheese, 05-bowl. Slide 3 uses a scripted dot grid; slides 6 and 7 reuse the device-free art from the iPhone set.
- The Duo itself is drawn by `duo.py` (closed, cover screen) with real captures from the Duo simulator; the cover camera position is a guess from where the app leaves space.
- Header v1 was cut off in App Store Connect's Device Preview on all three devices. v3 keeps the message in the band every device shows (crops measured and noted in `header.py`), checked in the preview on iPhone, iPhone Duo and iPad.
- Uploaded: seven Duo slides to the iPhone Duo slot, header to the Header slot. Two earlier header drafts remain in the Asset Library. Not submitted for review.
- Header v4 (17 Nov 2026, Isaiah asked for food in the part phones show): new Gemini art with the four props in a row (`native/header-art.jpeg`; the edge-cropped first art is `native/header-art-v1-edges.jpeg`). `header.py` now cuts each prop out by its distance from the background green, redraws the dot grid, and places the bowl and wrap either side of the headline inside x 1200-3720 (the Duo's cover camera covers the right side), with the bag and cup further out for iPad. Checked in Device Preview on iPhone, iPhone Duo and iPad, and uploaded as the full-quality PNG (1.9 MB).

## iPad 13-inch slides (17 Nov 2026)

- Tool: Nano Banana through the Gemini app in Chrome (same Pro account), Create image, 3:4 (the iPad canvas shape). Two chats, two plates each, each with the matching Duo plate attached for its look.
- First try asked Gemini to draw the iPad itself with a magenta screen for keying. It came back small, centred and with the bag over the screen, so it is kept in `native/ipad/rejected/` and the set uses device-free plates like the Duo, with the iPad drawn by script.
- Plates in `native/ipad/` (3:4, no text, no device), props pushed to the edges to leave room for a wide tablet: 01-bag (bag inside the left third), 02-tray (green, tray in the lower left), 04-cheese (one slice at the right edge), 05-bowl (yogurt bowl and smoothie on the left). Slide 3 is the scripted dot grid; slides 6 and 7 reuse the iPhone art through a 3:4 window.
- Captures in `raw/ipad/` from the "Leanr iPad 13" simulator (Debug build, sample data ending 17 Nov 2026, 9:41). Food detail and Remove ingredients come from the searched menu item, not the logged copy (the logged copy has no ingredient options); No Cheese on gives 560 Cal.
- `ipad.py` draws the iPad (aluminium edge, black bezel, camera on the right bezel), pastes the capture, removes the simulator's grey Quick Note corner mark, lifts the calorie card (slide 3) and the No Cheese row (slide 4), and sets the type. Slide 7 says "on your iPad".
- Output: `final-ipad-2064x2752/` (7 PNG, RGB, sRGB) and `contact-sheet-ipad.png`.
- Uploaded 17 Nov 2026 to the iPad 13-inch slot (iOS 1.0, English Australia), in order 01 to 07, after Remove All of the five plain screenshots (they stay in the Asset Library). Checked after a reload: 7 of 10. Not submitted for review.
