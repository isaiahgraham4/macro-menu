package com.isaiahgraham.leanrrr.feature.settings

import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.ColorLens
import androidx.compose.material.icons.outlined.EditCalendar
import androidx.compose.material.icons.outlined.ManageAccounts
import androidx.compose.material.icons.outlined.NotificationsActive
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.android.billingclient.api.ProductDetails
import com.isaiahgraham.leanrrr.billing.Premium
import com.isaiahgraham.leanrrr.billing.PremiumAccess
import com.isaiahgraham.leanrrr.billing.PremiumFeatures
import com.isaiahgraham.leanrrr.billing.Purchases
import com.isaiahgraham.leanrrr.ui.components.LeanrRow
import com.isaiahgraham.leanrrr.ui.components.LeanrScreen
import com.isaiahgraham.leanrrr.ui.theme.Leanr
import com.isaiahgraham.leanrrr.ui.theme.LeanrType
import kotlinx.coroutines.launch

internal fun featureIcon(key: String): ImageVector = when (key) {
    "menu" -> Icons.AutoMirrored.Outlined.MenuBook
    "plan" -> Icons.Outlined.EditCalendar
    "colours" -> Icons.Outlined.Palette
    "packs" -> Icons.Outlined.ColorLens
    "icons" -> Icons.Outlined.Apps
    "macros" -> Icons.Outlined.BarChart
    "widgets" -> Icons.Outlined.Widgets
    else -> Icons.Outlined.NotificationsActive
}

/**
 * The Even Leanrrr screen: what it includes, the plans with prices from Google Play, the lifetime purchase, and Restore.
 * Google Play's own purchase sheet shows the final price, billing period and renewal terms before anything is charged.
 */
@Composable
internal fun PremiumScreen(onDismiss: () -> Unit) {
    var legal by remember { mutableStateOf<LegalDocument?>(null) }
    val current = legal
    if (current != null) { LegalDocumentScreen(current, onBack = { legal = null }); return }
    if (Premium.isUnlocked) Subscribed(onDismiss) else Store(onDismiss, openLegal = { legal = it })
}

@Composable
private fun Subscribed(onDismiss: () -> Unit) {
    val c = Leanr.colours
    val context = LocalContext.current
    LeanrScreen("Even Leanrrr", showSettings = false, actions = { TextButton(onClick = onDismiss) { Text("Done", style = LeanrType.headline, color = c.accent) } }) {
        item {
            SettingsSection {
                LeanrRow("You have Even Leanrrr", titleColour = c.accent, leading = { Icon(Icons.Filled.Verified, null, tint = c.accent) })
                NoteRow(if (Premium.unlockedState) PremiumAccess.statusText(Purchases.entitlement) else "Turned on for testing", primary = false)
            }
        }
        item {
            SettingsSection("Included") {
                PremiumFeatures.all.forEachIndexed { i, feature ->
                    LeanrRow(feature.title, feature.detail, divider = i < PremiumFeatures.all.lastIndex,
                        leading = { Icon(featureIcon(feature.key), null, tint = c.accent) })
                }
            }
        }
        if (Purchases.entitlement?.productID != PremiumAccess.LIFETIME && Premium.unlockedState) item {
            SettingsSection(footerText = "Change plan, cancel or see receipts in Google Play. Cancelling keeps Even Leanrrr until the end of the period you've paid for.") {
                ButtonRow("Manage subscription", Icons.Outlined.ManageAccounts, divider = false) { Purchases.manageSubscriptions(context) }
            }
        }
    }
}

/** The plan's period from its pricing phase: "P1Y" is a year. */
private fun periodName(period: String): String = when (period) {
    "P1Y" -> "year"; "P6M" -> "6 months"; "P3M" -> "3 months"; "P1M" -> "month"; "P1W" -> "week"; "P4W" -> "4 weeks"; else -> period
}

private fun planTitle(id: String): String = when (id) {
    PremiumAccess.YEARLY -> "Yearly"; PremiumAccess.MONTHLY -> "Monthly"; else -> "Weekly"
}

/** "A$34.99 a year" and, when the chosen offer starts with a free trial, "1 week free, then A$34.99 a year". */
private fun planPrice(details: ProductDetails): String? {
    val offers = details.subscriptionOfferDetails ?: return null
    val offer = offers.firstOrNull { it.offerId != null } ?: offers.firstOrNull() ?: return null
    val phases = offer.pricingPhases.pricingPhaseList
    val recurring = phases.lastOrNull() ?: return null
    val base = "${recurring.formattedPrice} a ${periodName(recurring.billingPeriod)}".replace("a 6 months", "every 6 months").replace("a 3 months", "every 3 months").replace("a 4 weeks", "every 4 weeks")
    val trial = phases.firstOrNull { it.priceAmountMicros == 0L && it != recurring }
    val intro = phases.firstOrNull { it.priceAmountMicros > 0L && it != recurring }
    return when {
        trial != null -> "${trialText(trial.billingPeriod)} free, then $base"
        intro != null -> "${intro.formattedPrice} for the first ${periodName(intro.billingPeriod)}, then $base"
        else -> base
    }
}

private fun trialText(period: String): String = when (period) {
    "P3D" -> "3 days"; "P1W", "P7D" -> "1 week"; "P2W", "P14D" -> "2 weeks"; "P1M" -> "1 month"; else -> periodName(period)
}

@Composable
private fun Store(onDismiss: () -> Unit, openLegal: (LegalDocument) -> Unit) {
    val c = Leanr.colours
    val context = LocalContext.current
    val activity = LocalActivity.current
    val scope = rememberCoroutineScope()
    var chosen by remember { mutableStateOf(PremiumAccess.YEARLY) }
    var restoring by remember { mutableStateOf(false) }
    var restoreMessage by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) { Purchases.problem = null; Purchases.loadProducts() }

    LeanrScreen("Even Leanrrr", showSettings = false, actions = { TextButton(onClick = onDismiss) { Text("Close", style = LeanrType.headline, color = c.accent) } }) {
        item {
            Column(Modifier.padding(horizontal = 4.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                PremiumFeatures.all.forEach { feature ->
                    Row(verticalAlignment = Alignment.Top) {
                        Icon(featureIcon(feature.key), null, tint = c.accent, modifier = Modifier.size(26.dp))
                        Spacer(Modifier.width(12.dp))
                        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(feature.title, style = LeanrType.headline, color = c.text)
                            Text(feature.detail, style = LeanrType.subheadline, color = c.secondaryText)
                        }
                    }
                }
                Text("Logging, searching, barcode scanning, photos, app shortcuts and your data stay free.", style = LeanrType.footnote, color = c.secondaryText)
                Spacer(Modifier.size(4.dp))
            }
        }
        val products = Purchases.products
        if (Purchases.available == false && products.isEmpty()) item {
            SettingsSection(footerText = Purchases.UNAVAILABLE_MESSAGE) {
                ButtonRow("Try again", divider = false) { scope.launch { Purchases.problem = null; Purchases.loadProducts(); Purchases.refresh() } }
            }
        } else if (products.isEmpty()) item {
            SettingsSection(footerText = Purchases.problem) {
                Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (Purchases.loadingProducts) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp, color = c.accent)
                    Text(if (Purchases.loadingProducts) "Getting prices from Google Play…" else "Prices aren’t available right now.", style = LeanrType.body, color = c.secondaryText,
                        modifier = Modifier.weight(1f))
                    if (!Purchases.loadingProducts) TextButton(onClick = { scope.launch { Purchases.problem = null; Purchases.loadProducts() } }) { Text("Try again", color = c.accent) }
                }
            }
        } else {
            item {
                Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    PremiumAccess.subscriptionIDs.mapNotNull { id -> products[id]?.let { id to it } }.forEach { (id, details) ->
                        val selected = chosen == id
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.card)
                                .border(2.dp, if (selected) c.accent else Color.Transparent, RoundedCornerShape(14.dp))
                                .clickable { chosen = id }.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(Modifier.weight(1f)) {
                                Text(planTitle(id), style = LeanrType.headline, color = c.text)
                                planPrice(details)?.let { Text(it, style = LeanrType.subheadline, color = c.secondaryText) }
                            }
                            Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (selected) c.accent else c.tertiaryText)
                        }
                    }
                    if (PremiumAccess.subscriptionIDs.any { products[it] != null }) {
                        Button(
                            onClick = { if (activity != null) Purchases.buy(activity, chosen) },
                            enabled = products[chosen] != null && activity != null,
                            colors = ButtonDefaults.buttonColors(containerColor = c.accent, contentColor = if (c.dark) Color.Black else Color.White),
                            shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                        ) { Text("Subscribe", style = LeanrType.headline) }
                    }
                    products[PremiumAccess.LIFETIME]?.let { lifetime ->
                        val price = lifetime.oneTimePurchaseOfferDetailsList?.firstOrNull()?.formattedPrice ?: lifetime.oneTimePurchaseOfferDetails?.formattedPrice
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.card).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.AllInclusive, null, tint = c.accent, modifier = Modifier.size(28.dp))
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text("Lifetime", style = LeanrType.headline, color = c.text)
                                Text("Pay once, keep Even Leanrrr for good.", style = LeanrType.caption, color = c.secondaryText)
                            }
                            Button(onClick = { if (activity != null) Purchases.buy(activity, PremiumAccess.LIFETIME) }, enabled = activity != null,
                                colors = ButtonDefaults.buttonColors(containerColor = c.accent.copy(alpha = 0.16f), contentColor = c.accent)) {
                                Text(price ?: "Buy", style = LeanrType.subheadline.copy(fontWeight = FontWeight.SemiBold))
                            }
                        }
                    }
                    if (Purchases.pending) Text("Your purchase is waiting for Google Play to confirm it. Even Leanrrr turns on as soon as it does.",
                        style = LeanrType.footnote, color = c.secondaryText)
                    Purchases.problem?.let { Text(it, style = LeanrType.footnote, color = c.over) }
                    Text("Billed to your Google Play account. A subscription renews automatically at the price shown until you cancel it in Google Play, " +
                        "at least a day before it renews. A free trial, when offered, becomes a paid subscription when it ends unless you cancel first.",
                        style = LeanrType.caption, color = c.secondaryText)
                }
            }
        }
        item {
            SettingsSection {
                ButtonRow(if (restoring) "Restoring…" else "Restore purchases", enabled = !restoring) {
                    restoring = true
                    scope.launch {
                        val found = Purchases.restore()
                        restoring = false
                        restoreMessage = if (found) null else Purchases.problem ?: "No Even Leanrrr purchase was found for this Google account."
                    }
                }
                ButtonRow("Redeem a code") { Purchases.redeemCode(context) }
                ButtonRow("Privacy policy") { openLegal(LegalDocument.PRIVACY) }
                ButtonRow("Terms of use", divider = false) { openLegal(LegalDocument.TERMS) }
            }
        }
    }
    restoreMessage?.let { MessageAlert("Nothing to restore", it) { restoreMessage = null } }
}
