# Leanrrr for Android

Native Kotlin + Jetpack Compose port of the iOS app in `../ios`. App ID `com.isaiahgraham.leanrrr`, min Android 9, target 36.
See [PORTING.md](PORTING.md) for how the code is laid out and the conventions.

## Build and run

```bash
source ~/.android-tools/env.sh          # JDK 21, Android SDK, emulator, adb
cd ~/drive-thru-macros/android
./gradlew :app:assembleDebug             # APK in app/build/outputs/apk/debug/
./gradlew :app:testDebugUnitTest         # Find, Scan and Progress checks ported from AppChecks.swift
emulator -avd Leanrrr_Pixel &            # Pixel 9, Android 16 with Google Play
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The food data is not copied into this folder: `copyFoodData` in `app/build.gradle.kts` takes every JSON file and the legal
texts from `../ios/MacroMenu` at build time, so menu updates land in both apps. Newer data still arrives from Supabase.

## What maps to what

| iOS | Android |
|---|---|
| Apple Health | Health Connect (meals, water, weigh-ins written; weight, steps, active calories read) |
| iCloud sync | Android backup to the Google account (`app-state.json` and settings) |
| WidgetKit | Glance widgets (9) |
| Vision / VisionKit | ML Kit barcode + text recognition, CameraX |
| MapKit search | OpenStreetMap tiles (osmdroid) + Overpass, mirror fallback |
| StoreKit | Play Billing: `premium_yearly`, `premium_monthly`, `premium_weekly`, `premium_lifetime` |
| Alternate icons | Launcher activity-aliases `.MainActivity<Theme>` |
| Siri / Shortcuts | Static shortcuts + dynamic pinned-food shortcuts |

Backups use the same JSON as iOS, so an iPhone backup imports on Android and back.

## Not there yet

- Community foods: sharing rules and UI are ported; there's no backend outside CloudKit, so sharing is off.
- Meal photo recognition: ML Kit has no food classifier; the photo screen uses text, barcodes and remembered choices.
- Apple Intelligence features, the Watch app, Live Activity (an ongoing "Cal left" notification instead).
- Billing needs the app on a Play Console track with the four products set up before prices load.
- Privacy policy and terms are the iOS text; they need Android wording (Health Connect, Google Play, OpenStreetMap).
