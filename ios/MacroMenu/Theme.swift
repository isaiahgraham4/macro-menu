import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "appearance"
    var id: Self { self }
    var name: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppIconTheme: String, CaseIterable, Identifiable {
    case black, cream, forest, midnight, plum, sage, terracotta

    static let storageKey = "appIcon"
    var id: Self { self }
    var name: String { rawValue.capitalized }
    var previewAsset: String { "IconPreview\(name)" }
    var alternateName: String? { self == .black ? nil : "AppIcon\(name)" }
}

/// Shared surfaces keep the background consistent in tabs, details and sheets.
struct LeanrList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        List { content }
            .scrollContentBackground(.hidden)
            .background { LeanrBackground() }
    }
}

struct LeanrForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .scrollContentBackground(.hidden)
            .background { LeanrBackground() }
    }
}

/// Leanr Premium: custom app colours and icons, separate macro colours, the Calories & macros and All targets widgets,
/// and choosing which meal reminders you get. Locked users fall back to the defaults; nothing they've logged is affected.
/// The answer comes from StoreKit (see `Purchases`); the screens that read it redraw when it changes.
enum Premium {
    /// Whether Even Leanr (the paid subscription) is on sale. While it's false, nothing is locked: every feature is
    /// available to everyone, the Even Leanr row and screen are hidden, and StoreKit is never contacted.
    /// Set it to true when the subscriptions exist in App Store Connect and the legal text in
    /// `AppStore/even-leanr-legal.md` is back in Terms.md and PrivacyPolicy.md.
    static let subscriptionsEnabled = false

    @MainActor static var isUnlocked: Bool {
        guard subscriptionsEnabled else { return true }
        #if DEBUG
        // For testing the unlocked screens without buying: launch with -LeanrForcePremium. Not compiled into releases.
        if ProcessInfo.processInfo.arguments.contains("-LeanrForcePremium") { return true }
        #endif
        return Purchases.shared.isUnlocked
    }
}

/// The app's primary colour, chosen in Settings. Stored under the "accent" key.
extension AppAccent {
    /// The colour to use for a stored choice, honouring the Premium lock.
    @MainActor static func resolved(_ raw: String) -> AppAccent {
        guard Premium.isUnlocked else { return standard }
        return AppAccent(rawValue: raw) ?? standard
    }
}
