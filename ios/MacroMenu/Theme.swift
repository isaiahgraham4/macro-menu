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

/// Premium features. Custom app colours are free for now; when Premium launches, replace
/// `isUnlocked` with the real purchase check and locked users fall back to the default colour.
enum Premium {
    static var isUnlocked: Bool { true }
}

/// The app's primary colour, chosen in Settings. Stored under the "accent" key.
extension AppAccent {
    /// The colour to use for a stored choice, honouring the Premium lock.
    static func resolved(_ raw: String) -> AppAccent {
        guard Premium.isUnlocked else { return standard }
        return AppAccent(rawValue: raw) ?? standard
    }
}
