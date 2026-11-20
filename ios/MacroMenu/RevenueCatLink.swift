import Foundation
import StoreKit
import RevenueCat

/// Sends Even Leanrrr purchases to RevenueCat, so subscriptions, trials and renewals show in its dashboard.
/// Apple's own store views still make every purchase and StoreKit 2 still decides who has Premium (see `Purchases`);
/// RevenueCat only records what happened, under an anonymous ID it makes up. It never unlocks or locks anything.
@MainActor enum RevenueCatLink {
    /// The App Store public SDK key from RevenueCat (Project settings → API keys), starting "appl_".
    /// Public by design (it ships inside the app). If it's ever empty, RevenueCat is simply never started.
    /// Never put a "test_" Test Store key here: RevenueCat crashes Release builds that use one on purpose.
    static let apiKey = "appl_YnlXOBohABxvQgFUwQLIZWGNWIS"

    private static var configured = false

    static var isOn: Bool { configured }

    /// Starts RevenueCat once, watching the purchases this app makes itself with StoreKit 2.
    static func start() {
        guard !configured, apiKey.hasPrefix("appl_") else { return }
        #if DEBUG
        RevenueCat.Purchases.logLevel = .info
        #else
        RevenueCat.Purchases.logLevel = .warn
        #endif
        RevenueCat.Purchases.configure(
            with: .builder(withAPIKey: apiKey)
                .with(purchasesAreCompletedBy: .myApp, storeKitVersion: .storeKit2)
                .build()
        )
        configured = true
    }

    /// Hands RevenueCat a purchase made in Apple's store views. Renewals, refunds and offer codes reach it on their own.
    static func record(_ result: Product.PurchaseResult) async {
        guard configured else { return }
        _ = try? await RevenueCat.Purchases.shared.recordPurchase(result)
    }

    /// After "Restore purchases", so RevenueCat's copy matches a new phone or a reinstall.
    static func sync() async {
        guard configured else { return }
        _ = try? await RevenueCat.Purchases.shared.syncPurchases()
    }
}
