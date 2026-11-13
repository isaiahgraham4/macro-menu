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
    /// The icon that follows the person's own appearance: white in light mode, black in dark mode.
    /// The raw value stays "black" so a choice saved by an earlier version still matches.
    case standard = "black"
    case cream, crimson, forest, midnight, plum, sage, terracotta

    static let storageKey = "appIcon"
    var id: Self { self }
    var name: String { self == .standard ? "Default" : rawValue.capitalized }
    var previewAsset: String { "IconPreview\(name)" }
    var alternateName: String? { self == .standard ? nil : "AppIcon\(name)" }
}

/// A matching set: app icon, app colour and the three macro colours, applied together from Settings.
/// Built only from `AppAccent` presets, so widgets and the watch show a pack without knowing about it.
/// Classic is the default look and stays free; the rest need Even Leanrrr.
struct ColourPack: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    let icon: AppIconTheme
    let accent: AppAccent
    let protein: AppAccent
    let carbs: AppAccent
    let fat: AppAccent

    var isFree: Bool { id == "classic" }

    static let all: [ColourPack] = [
        ColourPack(id: "classic", name: "Classic", detail: "Emerald with blue, orange and red", icon: .standard, accent: .green, protein: .blue, carbs: .orange, fat: .red),
        ColourPack(id: "warm", name: "Warm", detail: "Terracotta, ember and toast", icon: .terracotta, accent: .orange, protein: .red, carbs: .orange, fat: .brown),
        ColourPack(id: "crimson", name: "Crimson", detail: "Deep red with pink and plum", icon: .crimson, accent: .red, protein: .pink, carbs: .orange, fat: .purple),
        ColourPack(id: "berry", name: "Berry", detail: "Plum, raspberry and blackcurrant", icon: .plum, accent: .purple, protein: .indigo, carbs: .pink, fat: .purple),
        ColourPack(id: "forest", name: "Forest", detail: "Pine, bark and autumn leaves", icon: .forest, accent: .green, protein: .teal, carbs: .brown, fat: .orange),
        ColourPack(id: "ocean", name: "Ocean", detail: "Deep blue, sea glass and dusk", icon: .midnight, accent: .blue, protein: .blue, carbs: .teal, fat: .purple),
        ColourPack(id: "sage", name: "Sage", detail: "Soft mint, clay and stone", icon: .sage, accent: .mint, protein: .indigo, carbs: .brown, fat: .graphite),
        ColourPack(id: "latte", name: "Latte", detail: "Coffee, caramel and steel", icon: .cream, accent: .brown, protein: .brown, carbs: .orange, fat: .graphite),
        ColourPack(id: "slate", name: "Slate", detail: "Quiet grey with the classic macro colours", icon: .midnight, accent: .graphite, protein: .blue, carbs: .orange, fat: .red),
    ]

    /// The pack whose five settings all match what's stored, or nil when the person has mixed their own.
    static func matching(accent: String, protein: String, carbs: String, fat: String, icon: String) -> ColourPack? {
        all.first {
            $0.accent.rawValue == accent && $0.protein.rawValue == protein && $0.carbs.rawValue == carbs
                && $0.fat.rawValue == fat && $0.icon.rawValue == icon
        }
    }
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

    /// The colour to draw with, including a custom "#RRGGBB" choice, honouring the Premium lock.
    @MainActor static func resolvedColor(_ raw: String) -> Color {
        Premium.isUnlocked ? ThemeColour.color(raw, fallback: standard) : standard.color
    }

    /// The stored value to hand to widgets and the Live Activity: the choice itself, or green when locked or unreadable.
    @MainActor static func resolvedRaw(_ raw: String) -> String {
        Premium.isUnlocked && ThemeColour.isValid(raw) ? raw : standard.rawValue
    }
}

extension ThemeColour {
    /// A picked colour as "#RRGGBB" in sRGB, for storing.
    static func hex(from color: Color) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return hex(r: Double(r), g: Double(g), b: Double(b))
    }
}
