# Calories left widgets

The large “All targets · Premium” Home Screen widget shows calories and every enabled nutrient target (including optional nutrients), with consumed/target values and progress. Missing nutrient data is marked with a plus. It reads the app's shared Premium access flag; the current development `Premium.isUnlocked` stub enables it for testing. Replace that stub with verified purchase entitlement state when subscriptions launch. Older snapshots without access show a locked state until the app syncs. The free calories widget does not read this flag. Both widget kinds reload after relevant saves and target/colour/access changes when the app syncs.

The circular Lock Screen widget displays calories eaten, a compact “cals” and leaf row, then the daily target inside the progress ring.

LeanrWidgets ships inside the app and supports small/medium Home Screen widgets and inline/circular/rectangular Lock Screen widgets. Both targets share `group.com.isaiahgraham.MacroMenu` via `Configuration/Leanr.entitlements`.

All existing Calories left widget sizes are free and must remain available without a Premium subscription. Future premium widgets should use separate widget kinds and their own entitlement checks; do not gate the existing widget or its shared calorie updates. Matching the app's effective accent colour is included in the free widget.

The app and widget use the same `Shared/AppAccent.swift` palette. Changing the app colour publishes the resolved accent alongside calorie totals and requests a widget refresh. Older snapshots without a colour fall back to the standard green. System-rendered Lock Screen and tinted Home Screen appearances may override custom colours.

Open Leanr once after installing. On Home Screen, long-press a blank area, choose Edit → Add Widget, search Leanr, then choose Calories left. On Lock Screen, long-press, choose Customise → Lock Screen, then tap the widget area (or the date row for the inline widget).

The app atomically publishes only the active calorie target and daily calorie totals to the App Group after successful saves. Unlogged meal tray items are excluded. WidgetKit is asked to reload only when these values change. It controls when updates become visible; refreshes aren't guaranteed to be immediate. The extension schedules midnight entries for seven days and requests a new timeline at the next local midnight. Past goal snapshots are not used for today's target, matching TodayView.

If no snapshot is available, widgets prompt the user to open Leanr. If calories aren't tracked, they prompt for a target. Above-target totals display a positive amount labelled “Cal over target”. Tapping a widget opens today's log. Widget contents are marked privacy-sensitive for system redaction.

Build the MacroMenu scheme to include the extension. Automatic signing must provision the App Group for both app IDs. `bash ios/Tests/run-checks.sh` checks target selection, portion totals, tray exclusion, missing goals, over-target values and daylight-saving midnight rollover.
