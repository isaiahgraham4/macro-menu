package com.isaiahgraham.leanrrr.feature.scan

import androidx.compose.runtime.Composable
import com.isaiahgraham.leanrrr.data.Food
import com.isaiahgraham.leanrrr.data.MealTime

// Entry points (owner: Scan). Today, Meal and My foods open the scanners with these; the extra parameters all have defaults.

/**
 * Barcode scanner (BarcodeScanView.swift): finds the product in your foods, Leanrrr's supermarket foods or on Open Food Facts
 * and hands back a Food for review. With `quick`, the product can be logged ([BarcodeQuick.Log]) or saved to My foods
 * ([BarcodeQuick.Save]) straight from the scan screen. `onManualEntry` gets a barcode that wasn't found (or null) so the
 * caller can open the editor with it filled in; without it, those buttons close the scanner.
 */
@Composable
fun BarcodeScanScreen(
    onFound: (Food) -> Unit,
    onDismiss: () -> Unit,
    quick: BarcodeQuick? = null,
    actionTitle: String = "Log",
    onManualEntry: ((String?) -> Unit)? = null,
) = BarcodeScan(onFound, onDismiss, quick = quick, actionTitle = actionTitle, onManualEntry = onManualEntry)

/** Nutrition label reader (LabelParser.swift and the food editor's label scan): fills a new food from a photo of the panel. */
@Composable
fun LabelScanScreen(onFood: (Food) -> Unit, onDismiss: () -> Unit) = LabelScan(onFood, onDismiss)

/** Photo of a meal (MealPhotoView.swift): finds what's on the plate in Leanrrr's foods and logs it to `mealTime`. */
@Composable
fun MealPhotoScreen(onDismiss: () -> Unit, mealTime: MealTime = MealTime.suggested()) = MealPhoto(onDismiss, mealTime)

/** Menu scanner (MenuScanView.swift): photograph any restaurant's menu and get estimated dishes. Premium. */
@Composable
fun MenuScanScreen(onDismiss: () -> Unit, mealTime: MealTime = MealTime.suggested()) = MenuScan(onDismiss, mealTime)
