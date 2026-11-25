import Foundation

/// The rules for who has Leanr Premium, kept free of StoreKit so they can be checked on their own.
/// The product IDs must match the products created in App Store Connect (and `Configuration/Leanr.storekit`, for testing).
enum PremiumAccess {
    static let yearly = "com.isaiahgraham.MacroMenu.premium.yearly"
    static let monthly = "com.isaiahgraham.MacroMenu.premium.monthly"
    static let weekly = "com.isaiahgraham.MacroMenu.premium.weekly"
    /// A one-off purchase that never ends. Also given away free with Apple offer codes.
    static let lifetime = "com.isaiahgraham.MacroMenu.premium.lifetime"
    /// The auto-renewing plans, longest first, so it's listed first in Apple's subscription view.
    static let subscriptionIDs = [yearly, monthly, weekly]
    /// Everything that gives Premium.
    static let productIDs = subscriptionIDs + [lifetime]

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
        if entitlement?.productID == lifetime { return "Lifetime" }
        guard let entitlement, let expires = entitlement.expires else { return "Active" }
        let date = expires.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_AU")))
        if entitlement.trial == true { return (entitlement.renews ?? true) ? "Free trial ends \(date), then renews" : "Free trial ends \(date)" }
        return (entitlement.renews ?? true) ? "Renews \(date)" : "Ends \(date)"
    }
}

/// The gym colour packs (Sunshine, Revved, Anytime). Unlike the other packs they don't come with Even Leanrrr alone:
/// each one also needs its gym's code, or the pack bought on its own. Kept free of StoreKit so it can be checked on its own.
///
/// A pack is owned when this Apple Account has either
/// - bought or redeemed the pack's own product (people who already had Even Leanrrr get a free Apple code for it), or
/// - any Even Leanrrr purchase made with that gym's Apple offer code (SUNSHINE50, REVO50, ANYTIME50 on Lifetime).
/// Apple reports an offer code purchase with the offer's reference name ("Sunshine Fitness 50%"), so the gym is
/// recognised by a word in that name. Both routes are Apple's own codes: App Review rule 3.1.1 allows no other kind.
enum PartnerPacks {
    struct Partner: Identifiable, Equatable, Sendable {
        /// The `ColourPack` id, also the partner colour, icon and the key in `owned`.
        let pack: String
        let gym: String
        /// The non-consumable that unlocks the pack by itself. Must match App Store Connect and `Configuration/Leanr.storekit`.
        let productID: String
        /// Lower-case word that appears in the gym's offer code reference name in App Store Connect.
        let offerWord: String
        var id: String { pack }
        /// "a Sunshine Fitness code", "an Anytime Fitness code".
        var aCode: String { "\("AEIOU".contains(gym.prefix(1)) ? "an" : "a") \(gym) code" }
    }

    static let all: [Partner] = [
        Partner(pack: "sunshine", gym: "Sunshine Fitness", productID: "com.isaiahgraham.MacroMenu.pack.sunshine", offerWord: "sunshine"),
        Partner(pack: "revved", gym: "Revo Fitness", productID: "com.isaiahgraham.MacroMenu.pack.revved", offerWord: "revo"),
        Partner(pack: "anytime", gym: "Anytime Fitness", productID: "com.isaiahgraham.MacroMenu.pack.anytime", offerWord: "anytime"),
    ]
    static var productIDs: [String] { all.map(\.productID) }

    static func partner(pack: String) -> Partner? { all.first { $0.pack == pack } }

    /// The pack a transaction gives, if any. `codeOffer` is the offer's id when it was bought with an offer code.
    static func pack(productID: String, codeOffer: String?, revoked: Bool) -> String? {
        guard !revoked else { return nil }
        if let partner = all.first(where: { $0.productID == productID }) { return partner.pack }
        guard PremiumAccess.productIDs.contains(productID), let offer = codeOffer?.lowercased() else { return nil }
        return all.first { offer.contains($0.offerWord) }?.pack
    }

    static let cacheKey = "leanr.partnerPacks"

    /// The packs owned as of the last time StoreKit was asked, so they don't flicker off at launch.
    static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: cacheKey) ?? [])
    }

    static func save(_ packs: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(packs.sorted(), forKey: cacheKey)
    }
}
