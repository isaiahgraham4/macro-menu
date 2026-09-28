import SwiftUI
import UIKit
import CoreText

/// Bundled typefaces: Big Noodle Titling for big titles, Roboto for everything else.
enum AppFonts {
    static let display = "BigNoodleTitling"
    /// Big Noodle is condensed, so titles are drawn this much larger than the system sizes.
    static let displayScale: CGFloat = 1.35

    /// Registers the bundled fonts and styles the navigation and tab bars. Call once at launch.
    @MainActor static func setUp() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        let bar = UINavigationBar.appearance()
        if let font = UIFont(name: display, size: 34 * displayScale) { bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: font)] }
        if let font = UIFont(name: display, size: 20 * displayScale) { bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)] }
        if let font = UIFont(name: "Roboto-Medium", size: 10) { UITabBarItem.appearance().setTitleTextAttributes([.font: font], for: .normal) }
    }

    /// Point size of each text style at the default Dynamic Type setting.
    static func size(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .extraLargeTitle2: 28
        case .extraLargeTitle: 36
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

extension Font {
    /// Roboto sized like `style` and scaled with Dynamic Type. Headlines default to medium weight.
    static func roboto(_ style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> Font {
        let face = switch weight ?? (style == .headline ? .semibold : .regular) {
        case .ultraLight, .thin: "Roboto-Thin"
        case .light: "Roboto-Light"
        case .medium, .semibold: "Roboto-Medium"
        case .bold: "Roboto-Bold"
        case .heavy, .black: "Roboto-Black"
        default: "Roboto-Regular"
        }
        return .custom(face, size: AppFonts.size(style), relativeTo: style)
    }

    /// Big Noodle Titling, for big titles.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .custom(AppFonts.display, size: AppFonts.size(style) * AppFonts.displayScale, relativeTo: style)
    }
}
