package com.isaiahgraham.leanrrr.billing

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import com.isaiahgraham.leanrrr.data.Prefs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import java.time.Instant
import kotlin.coroutines.resume

/**
 * Whether this Google account has Even Leanrrr, from Google Play Billing (Purchases.swift with StoreKit swapped for Play).
 * Play tells the app which purchases are active; Leanrrr never sees payment details. RevenueCat isn't used on Android.
 * When Play isn't installed or can't be reached, the remembered entitlement stands in for a while and the Even Leanrrr
 * screen says why it can't sell anything.
 */
object Purchases {
    var entitlement by mutableStateOf<PremiumAccess.Entitlement?>(null); private set
    /** True once Google Play has answered at least once this launch. */
    var checked by mutableStateOf(false); private set
    /** False when Google Play Billing can't be used on this phone (no Play Store, signed out, or an old Play version). */
    var available by mutableStateOf<Boolean?>(null); private set
    /** Why the last attempt to reach Play or buy failed, in words for the person. */
    var problem by mutableStateOf<String?>(null)
    /** Set while a purchase waits for Play to confirm it (a cash payment, say). */
    var pending by mutableStateOf(false); private set
    var products by mutableStateOf<Map<String, ProductDetails>>(emptyMap()); private set
    var loadingProducts by mutableStateOf(false); private set

    /** Called when Premium turns on or off, so widgets and reminders can follow. */
    var onChange: (() -> Unit)? = null

    private lateinit var appContext: Context
    private var client: BillingClient? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val connecting = Mutex()

    const val UNAVAILABLE_MESSAGE = "Google Play isn’t available on this phone, so Even Leanrrr can’t be bought here. Check that the Play Store is installed and you’re signed in to it, then try again."

    /** Reads the remembered entitlement and starts listening for purchases. Safe to call again. */
    fun start(context: Context) {
        if (client != null) return
        appContext = context.applicationContext
        val remembered = PremiumAccess.load()
        entitlement = remembered
        Premium.unlockedState = PremiumAccess.isRemembered(remembered)
        Premium.forcedState = Prefs.bool(Premium.FORCE_KEY)
        client = runCatching {
            BillingClient.newBuilder(appContext)
                .setListener { result, purchases -> scope.launch { purchasesUpdated(result, purchases) } }
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                .enableAutoServiceReconnection()
                .build()
        }.getOrNull()
        scope.launch { refresh() }
    }

    /** Connects to Google Play if it isn't already. False when Play Billing can't be used here. */
    private suspend fun ready(): Boolean {
        val client = client ?: run { available = false; return false }
        if (client.isReady) return true
        return connecting.withLock {
            if (client.isReady) return@withLock true
            val result = withTimeoutOrNull(10_000) {
                suspendCancellableCoroutine<BillingResult?> { continuation ->
                    runCatching {
                        client.startConnection(object : BillingClientStateListener {
                            override fun onBillingSetupFinished(result: BillingResult) { if (continuation.isActive) continuation.resume(result) }
                            override fun onBillingServiceDisconnected() { if (continuation.isActive) continuation.resume(null) }
                        })
                    }.onFailure { if (continuation.isActive) continuation.resume(null) }
                }
            }
            val ok = result?.responseCode == BillingClient.BillingResponseCode.OK
            available = ok
            if (!ok) problem = UNAVAILABLE_MESSAGE
            ok
        }
    }

    /** Asks Google Play what this account is entitled to now, and acknowledges new purchases so they aren't refunded. */
    suspend fun refresh() {
        if (!Premium.SUBSCRIPTIONS_ENABLED || !ready()) return
        val client = client ?: return
        val active = mutableListOf<PremiumAccess.Entitlement>()
        var anyPending = false
        for (type in listOf(BillingClient.ProductType.SUBS, BillingClient.ProductType.INAPP)) {
            val result = runCatching { client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build()) }.getOrNull() ?: return
            if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return
            for (purchase in result.purchasesList) {
                val ours = purchase.products.firstOrNull { it in PremiumAccess.productIDs } ?: continue
                when (purchase.purchaseState) {
                    Purchase.PurchaseState.PURCHASED -> {
                        acknowledge(purchase)
                        active += PremiumAccess.Entitlement(productID = ours, renews = if (ours == PremiumAccess.LIFETIME) null else purchase.isAutoRenewing,
                            checked = Instant.now().epochSecond)
                    }
                    Purchase.PurchaseState.PENDING -> anyPending = true
                }
            }
        }
        pending = anyPending && active.isEmpty()
        apply(PremiumAccess.best(active))
    }

    private suspend fun acknowledge(purchase: Purchase) {
        if (purchase.isAcknowledged) return
        val client = client ?: return
        runCatching { client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()) }
    }

    private fun apply(best: PremiumAccess.Entitlement?) {
        checked = true
        val wasUnlocked = Premium.unlockedState
        entitlement = best
        Premium.unlockedState = best != null
        PremiumAccess.save(best)
        if (wasUnlocked != Premium.unlockedState) onChange?.invoke()
    }

    /** The plans and the lifetime purchase with their prices, for the Even Leanrrr screen. */
    suspend fun loadProducts() {
        if (!ready()) return
        val client = client ?: return
        loadingProducts = true
        try {
            val found = mutableMapOf<String, ProductDetails>()
            for ((type, ids) in listOf(BillingClient.ProductType.SUBS to PremiumAccess.subscriptionIDs, BillingClient.ProductType.INAPP to listOf(PremiumAccess.LIFETIME))) {
                val params = QueryProductDetailsParams.newBuilder().setProductList(ids.map {
                    QueryProductDetailsParams.Product.newBuilder().setProductId(it).setProductType(type).build()
                }).build()
                val result = runCatching { client.queryProductDetails(params) }.getOrNull() ?: continue
                if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) result.productDetailsList?.forEach { found[it.productId] = it }
            }
            products = found
            if (found.isEmpty()) problem = "Google Play didn’t return any Even Leanrrr plans. Check your connection and try again."
        } finally { loadingProducts = false }
    }

    /** Opens Google Play's purchase sheet for a plan or the lifetime purchase. The answer arrives in [purchasesUpdated]. */
    fun buy(activity: Activity, productID: String) {
        val client = client
        val details = products[productID]
        if (client == null || !client.isReady || details == null) { problem = UNAVAILABLE_MESSAGE; return }
        val params = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
        if (details.productType == BillingClient.ProductType.SUBS) {
            // The offer with a free trial or introductory price when there is one, otherwise the base plan.
            val offer = details.subscriptionOfferDetails?.let { offers -> offers.firstOrNull { it.offerId != null } ?: offers.firstOrNull() }
                ?: run { problem = "That plan isn’t available right now."; return }
            params.setOfferToken(offer.offerToken)
        } else {
            details.oneTimePurchaseOfferDetailsList?.firstOrNull()?.offerToken?.let { params.setOfferToken(it) }
        }
        problem = null
        val result = client.launchBillingFlow(activity, BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(params.build())).build())
        if (result.responseCode != BillingClient.BillingResponseCode.OK && result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            problem = message(result)
        }
    }

    private suspend fun purchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases?.forEach { if (it.purchaseState == Purchase.PurchaseState.PURCHASED) acknowledge(it) }
                refresh()
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> refresh()
            BillingClient.BillingResponseCode.USER_CANCELED -> {}
            else -> problem = message(result)
        }
    }

    /** "Restore purchases": Play keeps purchases with the Google account, so asking again brings them back. */
    suspend fun restore(): Boolean {
        problem = null
        refresh()
        return Premium.unlockedState
    }

    private fun message(result: BillingResult): String = when (result.responseCode) {
        BillingClient.BillingResponseCode.BILLING_UNAVAILABLE, BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
        BillingClient.BillingResponseCode.SERVICE_DISCONNECTED -> UNAVAILABLE_MESSAGE
        BillingClient.BillingResponseCode.NETWORK_ERROR -> "Couldn’t reach Google Play. Check your connection and try again."
        BillingClient.BillingResponseCode.ITEM_UNAVAILABLE -> "That plan isn’t available in your country yet."
        else -> "Google Play couldn’t complete that. ${result.debugMessage}".trim()
    }

    /** Google Play's own page for changing plan or cancelling. */
    fun manageSubscriptions(context: Context) {
        val sku = entitlement?.productID?.takeIf { it != PremiumAccess.LIFETIME }
        val url = "https://play.google.com/store/account/subscriptions" + if (sku != null) "?sku=$sku&package=${context.packageName}" else ""
        open(context, url)
    }

    /** Google Play's page for entering a promo code (App Store offer codes on iOS). */
    fun redeemCode(context: Context) = open(context, "https://play.google.com/redeem")

    private fun open(context: Context, url: String) {
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    }

    /** Debug builds only. */
    fun force(on: Boolean) {
        Prefs.set(Premium.FORCE_KEY, on)
        val was = Premium.isUnlocked
        Premium.forcedState = on
        if (was != Premium.isUnlocked) onChange?.invoke()
    }
}
