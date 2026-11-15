import SwiftUI
import StoreKit

/// What Premium includes. Kept in one place so the paywall and the locked screens say the same thing.
enum PremiumFeatures {
    static let all: [(symbol: String, title: String, detail: String)] = [
        ("menucard", "Scan a menu", "Photograph any menu and see estimated calories and macros for each dish, then log it."),
        ("calendar.badge.plus", "Plan ahead", "Plan tomorrow's meals now and tick them off with one tap when you eat them."),
        ("paintpalette", "App colours", "Pick a preset or any colour you like for buttons, tabs and progress bars."),
        ("swatchpalette", "Colour packs", "Matching sets of app icon, app colour, macro colours and background tint, from Warm to Ocean."),
        ("app.badge", "App icons", "More icon packs for your Home Screen."),
        ("chart.bar.fill", "Macro colours", "Pick any colour for protein, carbs and fat, in the app and widgets."),
        ("square.grid.2x2", "Two more widgets", "Calories & macros, and All targets."),
        ("bell.badge", "Meal and water reminders", "Choose which meals remind you, and when, pick when your weekly review arrives, and get nudged to drink water."),
    ]
}

/// The Premium screen: what it includes, the price from the App Store, and Restore purchases.
/// Apple's subscription view supplies the price, billing period, renewal terms and Restore, so the required wording is always correct.
struct PremiumView: View {
    @Environment(\.dismiss) private var dismiss
    private let purchases = Purchases.shared
    @State private var managing = false

    var body: some View {
        NavigationStack {
            if purchases.isUnlocked {
                subscribed
                    .navigationTitle("Even Leanrrr").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            } else {
                // The store's own heading says "Even Leanrrr" and Apple's view brings its own close button,
                // so a navigation bar here would only repeat the title.
                store.toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: PremiumAccess.productIDs) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Even Leanrrr").font(.display(.largeTitle))
                ForEach(PremiumFeatures.all, id: \.title) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.roboto(.headline))
                            Text(feature.detail).font(.roboto(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Logging, searching, barcode scanning, photos, Siri and your data stay free.")
                    .font(.roboto(.footnote)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 12)
            .accessibilityElement(children: .contain)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases, .redeemCode)
        .subscriptionStorePolicyDestination(for: .privacyPolicy) { NavigationStack { LegalDocumentView(document: .privacy) } }
        .subscriptionStorePolicyDestination(for: .termsOfService) { NavigationStack { LegalDocumentView(document: .terms) } }
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result { await purchases.refresh() }
        }
    }

    private var subscribed: some View {
        LeanrList {
            Section {
                Label("You have Even Leanrrr", systemImage: "checkmark.seal.fill").font(.roboto(.headline)).foregroundStyle(.tint)
                Text(PremiumAccess.statusText(purchases.entitlement)).foregroundStyle(.secondary)
            }
            Section("Included") {
                ForEach(PremiumFeatures.all, id: \.title) { feature in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                            Text(feature.detail).font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: feature.symbol) }
                }
            }
            Section {
                Button("Manage subscription", systemImage: "gearshape") { managing = true }
            } footer: {
                Text("Change plan, cancel or see receipts in your Apple Account. Cancelling keeps Even Leanrrr until the end of the period you've paid for.")
            }
        }
        .manageSubscriptionsSheet(isPresented: $managing)
    }
}

/// A row that tells a locked user what Premium adds and opens the Premium screen. Shows nothing once they have it.
struct PremiumPromptRow: View {
    var message = "Part of Even Leanrrr."
    @State private var showing = false
    var body: some View {
        if !Premium.isUnlocked {
            Button { showing = true } label: {
                HStack {
                    Label(message, systemImage: "lock.fill")
                    Spacer()
                    Text("See Even Leanrrr").font(.roboto(.subheadline, weight: .semibold)).foregroundStyle(.tint)
                }
            }
            .sheet(isPresented: $showing) { PremiumView() }
        }
    }
}
