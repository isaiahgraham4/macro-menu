import SwiftUI

/// Bundled typefaces, shared by the app and its widgets: Bebas Neue for big titles, Roboto for everything else.
/// Both are free to ship (SIL OFL / Apache). The app registers them at launch; the widgets list them under UIAppFonts.
enum AppFonts {
    static let display = "BebasNeue-Regular"
    /// Bebas Neue is condensed, so titles are drawn this much larger than the system sizes.
    static let displayScale: CGFloat = 1.35

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

    /// The Roboto face that stands in for a system weight.
    static func roboto(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin: "Roboto-Thin"
        case .light: "Roboto-Light"
        case .medium, .semibold: "Roboto-Medium"
        case .bold: "Roboto-Bold"
        case .heavy, .black: "Roboto-Black"
        default: "Roboto-Regular"
        }
    }
}

extension Font {
    /// Roboto sized like `style` and scaled with Dynamic Type. Headlines default to medium weight.
    static func roboto(_ style: Font.TextStyle = .body, weight: Font.Weight? = nil) -> Font {
        .custom(AppFonts.roboto(weight ?? (style == .headline ? .semibold : .regular)), size: AppFonts.size(style), relativeTo: style)
    }

    /// Roboto at a fixed point size, for tight widget layouts that must not grow with Dynamic Type.
    static func roboto(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppFonts.roboto(weight), fixedSize: size)
    }

    /// Bebas Neue, for big titles.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .custom(AppFonts.display, size: AppFonts.size(style) * AppFonts.displayScale, relativeTo: style)
    }
}
