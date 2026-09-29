---
name: Leanr
description: A warm order counter for eating out on target. Native iOS, warmed up with a worktop surface, Bebas titles and big honest numbers.
colors:
  emerald: "#01714C"
  emerald-night: "#2BC47A"
  protein-blue: "#007AFF"
  carbs-orange: "#FF9500"
  fat-red: "#FF3B30"
  worktop-cream: "#F7F2E3"
  worktop-sage: "#E8F0E0"
  worktop-wheat: "#F5E6CF"
  worktop-night: "#1A211C"
  worktop-umber: "#29241C"
  cutting-board: "#E3C496"
  grain-brown: "#A2845E"
  grouped-cell: "#FFFFFF"
  share-card-white: "#FFFFFF"
  accent-green: "#34C759"
  accent-mint: "#00C7BE"
  accent-teal: "#30B0C7"
  accent-cyan: "#32ADE6"
  accent-blue: "#007AFF"
  accent-indigo: "#5856D6"
  accent-purple: "#AF52DE"
  accent-pink: "#FF2D55"
  accent-red: "#FF3B30"
  accent-orange: "#FF9500"
  accent-brown: "#A2845E"
  accent-graphite: "#8E8E93"
typography:
  display:
    fontFamily: "Bebas Neue, Roboto, sans-serif"
    fontSize: "46px"
    fontWeight: 400
  title:
    fontFamily: "Bebas Neue, Roboto, sans-serif"
    fontSize: "27px"
    fontWeight: 400
  stat-hero:
    fontFamily: "Roboto, sans-serif"
    fontSize: "34px"
    fontWeight: 700
    fontFeature: "tnum"
  stat:
    fontFamily: "Roboto, sans-serif"
    fontSize: "22px"
    fontWeight: 700
    fontFeature: "tnum"
  headline:
    fontFamily: "Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 500
  body:
    fontFamily: "Roboto, sans-serif"
    fontSize: "17px"
    fontWeight: 400
  subheadline:
    fontFamily: "Roboto, sans-serif"
    fontSize: "15px"
    fontWeight: 400
  label:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 500
  caption:
    fontFamily: "Roboto, sans-serif"
    fontSize: "12px"
    fontWeight: 400
  tab-label:
    fontFamily: "Roboto, sans-serif"
    fontSize: "10px"
    fontWeight: 500
rounded:
  field: "14px"
  tile: "16px"
  board-inset: "22px"
  board: "28px"
  capsule: "9999px"
spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
components:
  chip:
    backgroundColor: "{colors.grouped-cell}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.capsule}"
    padding: "8px 14px"
  chip-selected:
    backgroundColor: "{colors.emerald}"
    textColor: "{colors.share-card-white}"
    typography: "{typography.subheadline}"
    rounded: "{rounded.capsule}"
    padding: "8px 14px"
  stat-field:
    typography: "{typography.stat}"
    rounded: "{rounded.field}"
    padding: "12px"
  action-tile:
    typography: "{typography.label}"
    rounded: "{rounded.tile}"
    height: "78px"
  button-primary:
    backgroundColor: "{colors.emerald}"
    textColor: "{colors.share-card-white}"
    typography: "{typography.headline}"
  undo-toast:
    typography: "{typography.subheadline}"
    rounded: "{rounded.capsule}"
    padding: "12px 16px 12px 20px"
  calorie-ring:
    typography: "{typography.stat}"
    size: "116px"
  target-bar:
    typography: "{typography.caption}"
    height: "6px"
---

# Design System: Leanr

This file governs the native iOS app, Leanr (`ios/`), which is the primary product. The Macro Menu web app (`index.html`) keeps its own incumbent styling and is not governed by this file. Values here come from `Shared/AppAccent.swift`, `MacroMenu/Theme.swift`, `Shared/AppFonts.swift`, `DesignKit.swift`, `Components.swift`, `LeanrOnboarding.swift` and the asset catalog. Colour hex values for iOS system colours are their light-mode values; SwiftUI resolves the dark variants.

## Overview

**Creative North Star: "The Order Counter"**

Leanr is the counter you stand at when you order: you read the menu, weigh it against what's left in your day, and pick. The screens have that decisiveness. Bebas Neue headlines read like a menu board, and big Roboto numbers answer the question before any label does. The first thing on each screen is a choice or a number, never decoration.

The counter sits in a warm kitchen, not a gym. Every screen rests on the worktop: a cream-to-wheat gradient with faint timber grain, off-canvas plate rings, paper flecks and a soft accent glow in the top corner. That surface is what makes Leanr feel homely rather than clinical. Controls on top of it are stock iOS, warmed up with Leanr's fonts and accent rather than restyled. Native behaviour, gestures and Dynamic Type stay intact.

Density is moderate: grouped lists, a few signature summaries (the calorie ring, target bars, stat tiles), and one prominent action per screen, pinned above the tab bar.

**Key Characteristics:**
- Menu-board display type over a readable Roboto interface.
- A warm, textured worktop under every list, form and sheet.
- Numbers as heroes: bold and tabular, with gaps marked plainly (`+`, "partial").
- Stock iOS controls tinted with the chosen accent. No custom chrome.
- Macro colours that mean the same thing everywhere.

## Colors

The palette is a warm neutral ground with one user-chosen accent and three fixed macro signals.

### Primary
- **Counter Emerald** (`emerald`, `emerald-night` in dark mode): the brand green and the default accent. It tints the tab bar, prominent buttons, selected chips, tile icons, the calorie ring's progress and the worktop's corner glow. It is defined in the asset catalog as `AccentColor`.

### Secondary: the accent presets
- **Twelve accent presets** (`accent-*`): the user picks one in Settings (`AppAccent`, stored under `accent`), and it replaces Counter Emerald wherever the accent applies. Custom accents are planned as a Premium feature, so a locked user falls back to the default. Always read it through `AppAccent.resolved(...)`.

### Tertiary: macro signals
- **Protein Blue** (`protein-blue`), **Carbs Orange** (`carbs-orange`) and **Fat Red** (`fat-red`) are the macro defaults. They colour macro figures, the energy-split bar and nutrient target bars. Users can recolour them from the preset list (`MacroColours`, planned Premium).
- **Over-target orange** is the same system orange. It marks a calorie ring past its target, target figures over a maximum, and a "g short" protein pill.
- **Target-met green** is iOS system green, deliberately fixed rather than the accent. It is used only on the "Protein target met" pill.

### Neutral
- **Worktop Cream → Sage → Wheat** (`worktop-cream`, `worktop-sage`, `worktop-wheat`): the light-mode worktop gradient, running from top-leading to bottom-trailing.
- **Worktop Night → Umber** (`worktop-night`, `worktop-umber`): the dark-mode worktop, a deep green-black warming into brown.
- **Cutting Board** (`cutting-board`): the timber card used in onboarding.
- **Grain Brown** (`grain-brown`): the ink for grain, rings and flecks, used only at 3.5–7% opacity. In dark mode the ink is white at the same opacities.
- **Grouped cell** (`grouped-cell`): the light-mode value of `secondarySystemGroupedBackground`, the fill for cells, unselected chips and action tiles.
- **Share-card white** (`share-card-white`): the meal share image is always light, on a white ground.
- Text, secondary text and the grouped-cell fill (`secondarySystemGroupedBackground`) are iOS semantic colours, so they adapt to dark mode and increased contrast automatically.

### Named Rules
**The One Accent Rule.** Only the resolved accent carries brand colour in the interface. Never hard-code `.green` or the emerald hex for accent UI; read `AppAccent.resolved(...)` or `.tint`.

**The Fixed Meaning Rule.** Macro colours and the over/met signals mean the same thing on every screen and in every widget. Read macro colours through `MacroColours`, never as literal `.blue`, `.orange` or `.red`.

## Typography

**Display Font:** Bebas Neue (bundled, SIL OFL), drawn at 1.35× the system text style because it is condensed.
**Body Font:** Roboto (bundled, Apache): Thin, Light, Regular, Medium, Bold and Black.

**Character:** A tall, condensed menu-board capital over a plain, friendly grotesque. The display type shouts the name of the screen; Roboto does all the reading.

### Hierarchy
- **Display** (`display`, the large-title style): large navigation titles and the name on the meal share card.
- **Title** (`title`): inline navigation titles.
- **Stat Hero** (`stat-hero`): the calorie total in a nutrition summary.
- **Stat** (`stat`): the calorie ring's centre, typed stat fields and other headline numbers.
- **Headline** (`headline`): food names in rows and prominent button labels.
- **Body** (`body`): the default for all interface text, set app-wide with `.font(.roboto())`.
- **Subheadline** (`subheadline`): chips, row metadata, toast messages and nutrient rows.
- **Label** (`label`): stat captions, target-bar names and tile labels.
- **Caption** (`caption`): serving and chain lines, units, source notes and partial-data notes.
- **Tab Label** (`tab-label`): tab bar item titles.

Every size scales with Dynamic Type (`relativeTo:` the matching text style). Widgets use the same faces; their tight layouts use `.roboto(size:weight:)`, which is fixed-size, and big widget numbers are Roboto Bold with tabular digits. The widgets can keep a plain background for Home Screen legibility.

### Named Rules
**The Helper Rule.** Set type only with `.display(_:)` and `.roboto(_:weight:)`. Never use system fonts or `.custom` directly in the app or its widgets. Big Noodle Titling is local-only and must never be referenced in shipped code.

**The Steady Numbers Rule.** Any number that updates in place (calories, grams, targets, totals) uses `.monospacedDigit()`, so the figures don't jitter as they change.

## Layout

The app is built from SwiftUI `List` and `Form` screens inside a five-tab `TabView`: Today, Find, Map, Meal and My foods. Each tab has its own `NavigationStack`, and Settings is a gear button at the top right. Content uses the standard grouped-list insets.

Signature rows break out of the cell to sit directly on the worktop: `ChipRow` and `TileRow` use zero leading inset, a clear row background and no separator. Chips scroll horizontally, and tiles share a row equally with 10pt gaps.

The primary action of a screen sits in a `BottomActionBar`, pinned above the tab bar at full width with 20pt horizontal and 10pt vertical padding. Transient feedback (Undo and other notices) floats at the top in a capsule toast.

Spacing steps are 2, 4, 8, 12, 16, 20 and 24pt, with 5, 6, 10 and 14 used inside tight components. Stat tiles pad 12pt, and the share card pads 28pt at a fixed 390pt width.

## Elevation & Depth

Leanr is flat. Depth comes from layering, not shadows. Controls sit in grouped cells (`secondarySystemGroupedBackground`) or on translucent `.fill.tertiary` tiles, which float over the textured worktop. Toasts use `.regularMaterial` blur. The single shadow in the app is a 3pt lift that keeps a lock glyph legible on a colour swatch.

### Named Rules
**The Flat Counter Rule.** No drop shadows on cards, tiles, buttons or sheets. To separate something, change the fill or use material, never add a shadow.

**The Quiet Texture Rule.** The worktop's grain, rings and flecks stay at or below 7% ink opacity and never carry information. When the user has Increase Contrast turned on, the texture and accent glow are removed and only the gradient remains.

## Shapes

The shapes are soft and familiar: capsules for anything you tap or read at a glance, and rounded rectangles for anything you type into or hold.

- **Capsule** (`capsule`): chips, target bars, the energy-split bar, toasts and status pills. Buttons keep the system's own shape for the running iOS version.
- **Field** (`field`): typed stat tiles.
- **Tile** (`tile`): action tiles.
- **Board** (`board`, with an inset stroke at `board-inset`): the onboarding cutting board, with a 1pt grain-brown border inset 7pt.
- **Rings:** the calorie ring has a 12pt stroke with round caps and starts at 12 o'clock.

## Components

The feel is native iOS, warmed up. Use stock controls and the Leanr tint, and create custom pieces only where a number needs to be the hero.

### Buttons
- **Primary:** `.borderedProminent` with `.controlSize(.large)`, filled with the accent. There is one per screen, usually in a `BottomActionBar` with a headline label.
- **Secondary:** `.bordered`, accent-tinted.
- **Inline / row actions:** `.borderless` or `.plain`.

### Chips
- **Style:** a capsule with 14pt horizontal and 8pt vertical padding, a subheadline Medium label and a single line. When unselected, it has a grouped-cell fill and primary text.
- **Selected:** filled with the accent, with white text and the `.isSelected` accessibility trait.

### Cards / Containers
- **Grouped cells** on the worktop are the default container.
- **Stat Field:** a caption title over a Stat-weight number and its unit, on a `.fill.tertiary` field-radius tile. They come in side-by-side pairs.
- **Action Tile:** an accent SF Symbol (title3) over a two-line caption label, on a grouped-cell fill with tile radius and a minimum height of 78pt.

### Inputs / Fields
- **Number rows:** a label on the left and a trailing, right-aligned decimal field up to 120pt wide, using the decimal-pad keyboard. Optional fields show "Not set". Values show one decimal place, or two for prices and servings.

### Navigation
- **Tab bar:** the five tabs, with SF Symbols and Roboto Medium 10pt labels, tinted with the accent. The Meal tab shows a count badge for the current meal.
- **Nav bars:** Bebas large and inline titles, with a gear button at the top right on each tab root.

### Calorie Ring (signature)
A 116pt ring. The track is quaternary; progress is the accent, or orange when over target. The centre shows the calories left (or over) in Stat type over a caption. It reads as one accessibility element: "x of y calories".

### Target Bar (signature)
A label and "value / target unit" on one baseline over a 6pt capsule bar, filled in the nutrient's colour. The figure turns orange when a maximum is exceeded. It reads as one accessibility element.

### Nutrition Summary (signature)
Stat Hero calories with a trailing price, then three macro columns (caption name over coloured headline grams, with `+` when partial), then a 6pt capsule energy-split bar weighted 4/4/9. Details list kJ and the optional nutrients, marking partial values "(partial)".

### Undo Toast
A floating `.regularMaterial` capsule at the top: a semibold message and a bold "Undo" button. It lasts 5 seconds; plain notices last 2 seconds and dismiss on tap.

### Meal Share Card
A fixed 390pt, always-light white card with 28pt padding: a small accent "LEANR" label with the leaf glyph (matching the widgets), a Display meal name, item lines, a divider, the nutrition summary and a caption disclaimer.

## Do's and Don'ts

### Do:
- **Do** wrap every list and form screen in `LeanrList` or `LeanrForm` so it sits on the worktop.
- **Do** tint accent UI with `AppAccent.resolved(...)`, and let the Premium lock fall back to Counter Emerald.
- **Do** use `.display()` for screen names and `.roboto()` for everything else, including in widgets.
- **Do** make the answer the biggest thing on screen: calories left, grams short, a price.
- **Do** mark missing data visibly with `+`, "(partial)" or "Not set", never with a zero.
- **Do** group a compound visual (ring, bar, summary) into one accessibility element with a spoken label.

### Don't:
- **Don't** replace stock iOS controls with custom-drawn buttons, toggles or pickers.
- **Don't** add drop shadows or glossy effects; the counter is flat.
- **Don't** hard-code `.green` for accent UI. The only fixed green is the "Protein target met" pill.
- **Don't** render the worktop texture at more than 7% ink, or keep it when the user has Increase Contrast turned on.
- **Don't** use the system font, SF Rounded or Big Noodle Titling anywhere that ships.

### Known drift (fix when those files are next touched)
- The **Green** accent preset resolves to iOS system green (`accent-green`), not Counter Emerald. Emerald is the confirmed brand green, so the preset should use the `AccentColor` asset.
- `nutrientStyle(_:)` in `DesignKit.swift` hard-codes blue, orange and red, so target bars ignore the user's macro colour choices. That breaks the Fixed Meaning Rule.
