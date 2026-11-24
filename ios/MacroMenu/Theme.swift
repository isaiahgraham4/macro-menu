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
    case anytime, berry, cream, crimson, forest, latte, midnight, ocean, plum, revved, sage, slate, sunshine, terracotta, warm

    static let storageKey = "appIcon"
    var id: Self { self }
    var name: String { self == .standard ? "Default" : rawValue.capitalized }
    var previewAsset: String { "IconPreview\(name)" }
    var alternateName: String? { self == .standard ? nil : "AppIcon\(name)" }
}

/// A matching set: app icon, app colour, the three macro colours and a paper tint, applied together from Settings.
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
    let paper: PaperTint

    var isFree: Bool { id == "classic" }

    static let all: [ColourPack] = [
        ColourPack(id: "classic", name: "Classic", detail: "Emerald with blue, orange and red", icon: .standard, accent: .green, protein: .blue, carbs: .orange, fat: .red, paper: .cream),
        ColourPack(id: "warm", name: "Warm", detail: "Terracotta, ember and toast", icon: .warm, accent: .orange, protein: .red, carbs: .orange, fat: .brown, paper: .peach),
        ColourPack(id: "crimson", name: "Crimson", detail: "Deep red with pink and plum", icon: .crimson, accent: .red, protein: .pink, carbs: .orange, fat: .purple, paper: .blush),
        ColourPack(id: "berry", name: "Berry", detail: "Plum, raspberry and blackcurrant", icon: .berry, accent: .purple, protein: .indigo, carbs: .pink, fat: .purple, paper: .lilac),
        ColourPack(id: "forest", name: "Forest", detail: "Pine, bark and autumn leaves", icon: .forest, accent: .green, protein: .teal, carbs: .brown, fat: .orange, paper: .moss),
        ColourPack(id: "ocean", name: "Ocean", detail: "Deep blue, sea glass and dusk", icon: .ocean, accent: .blue, protein: .blue, carbs: .teal, fat: .purple, paper: .mist),
        ColourPack(id: "sage", name: "Sage", detail: "Soft mint, clay and stone", icon: .sage, accent: .mint, protein: .indigo, carbs: .brown, fat: .graphite, paper: .sage),
        ColourPack(id: "latte", name: "Latte", detail: "Coffee, caramel and steel", icon: .latte, accent: .brown, protein: .brown, carbs: .orange, fat: .graphite, paper: .oat),
        ColourPack(id: "slate", name: "Slate", detail: "Quiet grey with the classic macro colours", icon: .slate, accent: .graphite, protein: .blue, carbs: .orange, fat: .red, paper: .fog),
        ColourPack(id: "sunshine", name: "Sunshine", detail: "Black, white and bright orange", icon: .sunshine, accent: .sunshine, protein: .sunshine, carbs: .graphite, fat: .brown, paper: .chalk),
        ColourPack(id: "revved", name: "Revved", detail: "Red, charcoal and cream", icon: .revved, accent: .revved, protein: .revved, carbs: .graphite, fat: .orange, paper: .linen),
        ColourPack(id: "anytime", name: "Anytime", detail: "Purple, charcoal and white", icon: .anytime, accent: .anytime, protein: .anytime, carbs: .graphite, fat: .teal, paper: .frost),
    ]

    /// The pack whose settings all match what's stored, or nil when the person has mixed their own.
    /// `paper` is nil when no tint has ever been chosen (packs applied before tints existed still count as that pack).
    static func matching(accent: String, protein: String, carbs: String, fat: String, icon: String, paper: String?) -> ColourPack? {
        all.first {
            $0.accent.rawValue == accent && $0.protein.rawValue == protein && $0.carbs.rawValue == carbs
                && $0.fat.rawValue == fat && $0.icon.rawValue == icon && (paper == nil || $0.paper.rawValue == paper)
        }
    }
}

/// The page colour behind every screen: the order-pad cream, or a faint wash of a pack's colour.
/// Flat colours only (no gradients), each checked so every preset and custom colour still reads at 4.5:1 on it.
/// Oat is the darkest light tint, so `ThemeColour.lightBackground` uses it as the reference.
enum PaperTint: String, CaseIterable, Identifiable {
    case cream, peach, blush, lilac, moss, mist, sage, oat, fog, chalk, linen, frost

    static let storageKey = "paperTint"
    var id: Self { self }
    var name: String { rawValue.capitalized }

    private var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .cream: (0xF6F2EA, 0x121714)
        case .peach: (0xF8EDE2, 0x1A1410)
        case .blush: (0xF8ECEC, 0x1B1113)
        case .lilac: (0xF4ECF3, 0x181119)
        case .moss: (0xEDF1E8, 0x0F1610)
        case .mist: (0xE9F1F3, 0x0D151A)
        case .sage: (0xEEF1EA, 0x121612)
        case .oat: (0xF3ECE2, 0x17130F)
        case .fog: (0xEDEFF1, 0x121418)
        case .chalk: (0xF5F5F3, 0x0D0D0D)
        case .linen: (0xFFFAF3, 0x1A171B)
        case .frost: (0xF6F5FB, 0x14131B)
        }
    }

    func color(dark: Bool) -> Color {
        let v = dark ? hex.dark : hex.light
        return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    /// The tint to draw for a stored choice; cream when Premium is locked or the value is unknown.
    @MainActor static func resolved(_ raw: String) -> PaperTint {
        Premium.isUnlocked ? PaperTint(rawValue: raw) ?? .cream : .cream
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

/// Even Leanrrr (called Premium in code): custom app colours, colour packs, background tints and icons, separate macro colours,
/// the Calories & macros and All targets widgets, and choosing which meal reminders you get. Locked users fall back to the
/// defaults; nothing they've logged is affected.
/// The answer comes from StoreKit (see `Purchases`); the screens that read it redraw when it changes.
enum Premium {
    /// Whether Even Leanrrr (the paid subscription) is on sale. While it's false, nothing is locked: every feature is
    /// available to everyone, the Even Leanrrr row and screen are hidden, and StoreKit is never contacted.
    /// Turned on 15 Nov 2026. The subscriptions must exist in App Store Connect (see AppStore/README.md) before a build
    /// with this on goes to review, or the Even Leanrrr screen has nothing to sell.
    static let subscriptionsEnabled = true

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
