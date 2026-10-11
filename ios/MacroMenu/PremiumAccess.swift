import Foundation

/// The rules for who has Leanr Premium, kept free of StoreKit so they can be checked on their own.
/// The product IDs must match the subscriptions created in App Store Connect (and `Configuration/Leanr.storekit`, for testing).
enum PremiumAccess {
    static let yearly = "com.isaiahgraham.MacroMenu.premium.yearly"
    static let monthly = "com.isaiahgraham.MacroMenu.premium.monthly"
    /// Longest plan first, so it's listed first.
    static let productIDs = [yearly, monthly]

    /// A paid-up subscription as of the last time StoreKit was asked, remembered so Premium doesn't flicker off at launch
    /// or offline while StoreKit is still answering.
    struct Entitlement: Codable, Equatable, Sendable {
        var productID: String
        var expires: Date?
        var renews: Bool?
        /// True while it's the free trial, so Settings can say so. Absent in copies saved before trials existed.
        var trial: Bool?
    }

    /// Whether a transaction gives Premium right now: one of Leanr's products, not refunded or revoked, and not past its end.
    static func isActive(productID: String, expires: Date?, revoked: Bool, now: Date) -> Bool {
        productIDs.contains(productID) && !revoked && (expires.map { $0 > now } ?? true)
    }

    /// How long after its end date a remembered entitlement is still believed while StoreKit hasn't answered yet.
    /// A renewal can land after the old period ends, and Apple retries failed payments for a while.
    static let rememberedGrace: TimeInterval = 3 * 24 * 3600

    static func isRemembered(_ entitlement: Entitlement?, now: Date) -> Bool {
        guard let entitlement, productIDs.contains(entitlement.productID) else { return false }
        guard let expires = entitlement.expires else { return true }
        return expires.addingTimeInterval(rememberedGrace) > now
    }

    /// The entitlement that lasts longest, when more than one is active (a monthly bought, then a yearly).
    static func best(_ entitlements: [Entitlement]) -> Entitlement? {
        entitlements.max { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
    }

    static let cacheKey = "leanr.premium.entitlement"

    static func load(from defaults: UserDefaults = .standard) -> Entitlement? {
        defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(Entitlement.self, from: $0) }
    }

    static func save(_ entitlement: Entitlement?, to defaults: UserDefaults = .standard) {
        if let entitlement, let data = try? JSONEncoder().encode(entitlement) { defaults.set(data, forKey: cacheKey) }
        else { defaults.removeObject(forKey: cacheKey) }
    }

    /// "Renews 3 Nov 2026" or "Ends 3 Nov 2026" for the Premium row in Settings.
    static func statusText(_ entitlement: Entitlement?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let entitlement, let expires = entitlement.expires else { return "Active" }
        let date = expires.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_AU")))
        if entitlement.trial == true { return (entitlement.renews ?? true) ? "Free trial ends \(date), then renews" : "Free trial ends \(date)" }
        return (entitlement.renews ?? true) ? "Renews \(date)" : "Ends \(date)"
    }
}
