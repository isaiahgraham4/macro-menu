import SwiftUI
import StoreKit

/// A gym colour pack that isn't unlocked yet: the gym's code gets it free, or it can be bought on its own. No Even Leanrrr needed.
/// Both go through Apple (an offer code, or the pack's own product), so nothing here is an unlock code of Leanrrr's own.
/// Closes itself, and calls `onUnlocked`, once the pack is owned.
struct PartnerPackView: View {
    let partner: PartnerPacks.Partner
    var onUnlocked: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var redeeming = false
    private var pack: ColourPack? { ColourPack.all.first { $0.id == partner.pack } }

    var body: some View {
        NavigationStack {
            LeanrList {
                if let pack {
                    Section {
                        HStack(spacing: 14) {
                            Image(pack.icon.previewAsset)
                                .resizable().scaledToFill().frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(pack.name) colour pack").font(.roboto(.headline))
                                Text(pack.detail).font(.roboto(.subheadline)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    } footer: {
                        Text("Made with \(partner.gym). Members get it free with the code from their gym. You don't need Even Leanrrr to use it.")
                    }
                }
                Section {
                    Button { redeeming = true } label: { Label("Redeem \(partner.aCode)", systemImage: "ticket") }
                } footer: {
                    Text("Scan the QR code at your gym, or type its code here. The pack code and the gym's Even Leanrrr Lifetime code both unlock it.")
                }
                Section {
                    ProductView(id: partner.productID) {
                        Image(systemName: "swatchpalette").font(.title2).foregroundStyle(.tint)
                    }
                    .productViewStyle(.compact)
                } footer: {
                    Text("Not a member? You can buy the pack on its own.")
                }
            }
            .navigationTitle(pack?.name ?? partner.gym)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await Purchases.shared.refresh(); await RevenueCatLink.sync() } }
            .onInAppPurchaseCompletion { _, result in
                guard case .success(let outcome) = result else { return }
                await RevenueCatLink.record(outcome)
                if case .success = outcome { await Purchases.shared.refresh() }
            }
            .onChange(of: Premium.owns(pack: partner.pack)) { _, owned in
                if owned { onUnlocked(); dismiss() }
            }
        }
    }
}
