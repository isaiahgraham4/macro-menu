import Foundation
import Observation
import StoreKit

/// Whether this Apple Account has Leanr Premium, from StoreKit 2.
/// Only transactions Apple has signed count, and the answer is worked out on the device. Leanr never sees payment details.
@MainActor @Observable
final class Purchases {
    static let shared = Purchases()

    /// Read by the screens through `Premium.isUnlocked`; being observable, they redraw when it changes.
    private(set) var isUnlocked: Bool
    private(set) var entitlement: PremiumAccess.Entitlement?
    /// The gym colour packs this Apple Account owns (see `PartnerPacks`), read through `Premium.owns(pack:)`.
    private(set) var packs: Set<String>
    /// True once StoreKit has answered at least once this launch.
    private(set) var checked = false
    /// Called when Premium turns on or off, so widgets and reminders can follow.
    var onChange: (() -> Void)?

    private var listener: Task<Void, Never>?

    private init() {
        let remembered = PremiumAccess.load()
        entitlement = remembered
        isUnlocked = PremiumAccess.isRemembered(remembered, now: Date())
        packs = PartnerPacks.load()
    }

    /// Starts listening for purchases, renewals and refunds, including ones made outside the app. Safe to call again.
    func start() {
        guard listener == nil else { return }
        listener = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Asks StoreKit what this Apple Account is entitled to now.
    func refresh() async {
        var active: [PremiumAccess.Entitlement] = []
        var owned: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // A gym pack: bought on its own, or Even Leanrrr bought with the gym's offer code.
            let codeOffer = transaction.offer?.type == .code ? transaction.offer?.id : nil
            if let pack = PartnerPacks.pack(productID: transaction.productID, codeOffer: codeOffer, revoked: transaction.revocationDate != nil) {
                owned.insert(pack)
            }
            guard PremiumAccess.isActive(productID: transaction.productID, expires: transaction.expirationDate,
                                         revoked: transaction.revocationDate != nil, now: Date()) else { continue }
            let trial = transaction.offer?.type == .introductory && transaction.offer?.paymentMode == .freeTrial
            active.append(.init(productID: transaction.productID, expires: transaction.expirationDate, renews: nil, trial: trial))
        }
        var best = PremiumAccess.best(active)
        if var found = best { found.renews = await willRenew(found.productID); best = found }
        apply(best, packs: owned)
    }

    /// Asks Apple to sync purchases, for "Restore purchases" after a new phone or a reinstall.
    func restore() async throws {
        try await StoreKit.AppStore.sync()
        await refresh()
        await RevenueCatLink.sync()
    }

    private func willRenew(_ productID: String) async -> Bool? {
        guard let product = try? await Product.products(for: [productID]).first,
              let statuses = try? await product.subscription?.status else { return nil }
        for status in statuses {
            if case .verified(let info) = status.renewalInfo { return info.willAutoRenew }
        }
        return nil
    }

    private func apply(_ best: PremiumAccess.Entitlement?, packs owned: Set<String>) {
        checked = true
        let wasUnlocked = isUnlocked
        let hadPacks = packs
        entitlement = best
        isUnlocked = best != nil
        packs = owned
        PremiumAccess.save(best)
        PartnerPacks.save(owned)
        if wasUnlocked != isUnlocked || hadPacks != owned { onChange?() }
    }
}
