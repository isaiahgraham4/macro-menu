#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d /tmp/macromenu-checks.XXXXXX)
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -swift-version 6 -parse-as-library ios/MacroMenu/FoodStore.swift ios/Tests/FoodStoreChecks.swift -o "$check_dir/food-checks"
"$check_dir/food-checks"
xcrun swiftc -swift-version 6 -parse-as-library \
  ios/MacroMenu/FoodStore.swift ios/MacroMenu/Models.swift \
  ios/MacroMenu/AppStore.swift ios/MacroMenu/WebBackup.swift \
  ios/Shared/WidgetCalories.swift ios/Shared/AppAccent.swift ios/MacroMenu/WidgetSync.swift \
  ios/MacroMenu/MealFinder.swift ios/MacroMenu/LabelParser.swift ios/MacroMenu/MealSwaps.swift \
  ios/MacroMenu/BarcodeProduct.swift ios/MacroMenu/Weight.swift ios/MacroMenu/FoodSearch.swift ios/MacroMenu/Assistant.swift ios/MacroMenu/MealReminders.swift ios/MacroMenu/LogExport.swift ios/MacroMenu/MenuUpdates.swift ios/MacroMenu/WeeklyReview.swift ios/MacroMenu/Delivery.swift ios/MacroMenu/MealPhoto.swift ios/MacroMenu/VisionFoodLabels.swift ios/MacroMenu/MealVision.swift ios/MacroMenu/PremiumAccess.swift ios/MacroMenu/ProgressBreakdown.swift ios/MacroMenu/Steps.swift ios/MacroMenu/Water.swift ios/MacroMenu/BodyMeasurements.swift ios/MacroMenu/ProgressPhotoFiles.swift ios/MacroMenu/CheckIn.swift ios/MacroMenu/MealPlan.swift ios/MacroMenu/FoodPhrase.swift ios/MacroMenu/RecipeImport.swift ios/WatchShared/WatchSnapshot.swift ios/Tests/BarcodeChecks.swift \
  ios/Tests/AppChecks.swift -o "$check_dir/app-checks"
"$check_dir/app-checks" ios/MacroMenu/MenuData.json
