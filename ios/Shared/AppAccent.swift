import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension TargetStatus {
    /// Green when the protein goal is reached, orange when carbs or fat are over. Darker in light mode so small text stays readable.
    /// Nil when there's nothing to say, so the text keeps its usual colour.
    #if canImport(UIKit)
    var colour: Color? {
        switch self {
        case .none: nil
        case .reached: Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x6B / 255, alpha: 1)
            : UIColor(red: 0x0B / 255, green: 0x7A / 255, blue: 0x2E / 255, alpha: 1) })
        case .over: Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0xFF / 255, green: 0xA0 / 255, blue: 0x2E / 255, alpha: 1)
            : UIColor(red: 0xB8 / 255, green: 0x54 / 255, blue: 0x00 / 255, alpha: 1) })
        }
    }
    #else
    var colour: Color? {
        switch self {
        case .none: nil
        case .reached: Color(red: 0x0B / 255, green: 0x7A / 255, blue: 0x2E / 255)
        case .over: Color(red: 0xB8 / 255, green: 0x54 / 255, blue: 0x00 / 255)
        }
    }
    #endif
}

enum MacroColours {
    static let proteinKey = "macroColour.protein"
    static let carbsKey = "macroColour.carbs"
    static let fatKey = "macroColour.fat"
    static func colour(_ key: String, choices: [String: String]) -> Color {
        let fallback: AppAccent = key == "p" ? .blue : key == "c" ? .orange : .red
        return ThemeColour.color(choices[key], fallback: fallback)
    }
}

/// A stored colour choice: a preset name such as "blue", or a custom colour as "#RRGGBB".
/// The app, widgets and Live Activity all read colours through here, so a custom colour shows everywhere.
enum ThemeColour {
    static func color(_ raw: String?, fallback: AppAccent) -> Color {
        guard let raw else { return fallback.color }
        if let preset = AppAccent(rawValue: raw) { return preset.color }
        if let rgb = rgb(raw) { return readableColor(rgb) }
        return fallback.color
    }

    typealias RGB = (r: Double, g: Double, b: Double)
    /// What colours have to stay readable on: in light mode the darkest page tint (Oat, darker than the cream page and white
    /// cards, so the strictest), and grouped cards in dark mode (lighter than every page tint, so the strictest).
    static let lightBackground: RGB = (0xF3 / 255, 0xEC / 255, 0xE2 / 255)
    static let darkBackground: RGB = (0x1C / 255, 0x1C / 255, 0x1E / 255)
    /// WCAG AA for normal text.
    static let minimumContrast = 4.5

    /// The same hue, darkened (light mode) or lightened (dark mode) only as far as needed for 4.5:1.
    static func readable(_ c: RGB, dark: Bool) -> RGB {
        let background = dark ? darkBackground : lightBackground
        let target: Double = dark ? 1 : 0
        var out = c
        var step = 0
        while contrast(out, background) < minimumContrast && step < 40 {
            out = (out.r + (target - out.r) * 0.05, out.g + (target - out.g) * 0.05, out.b + (target - out.b) * 0.05)
            step += 1
        }
        return out
    }

    /// Whether a custom colour is shown differently from the picked value in either mode.
    static func isAdjusted(_ raw: String) -> Bool {
        guard isCustom(raw), let c = rgb(raw) else { return false }
        return contrast(c, lightBackground) < minimumContrast || contrast(c, darkBackground) < minimumContrast
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ c: RGB) -> Double {
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// A colour that adjusts itself to the light or dark appearance it's drawn in.
    static func readableColor(_ c: RGB) -> Color {
        #if canImport(UIKit)
        let light = readable(c, dark: false), dark = readable(c, dark: true)
        return Color(UIColor { trait in
            let x = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: x.r, green: x.g, blue: x.b, alpha: 1)
        })
        #else
        let x = readable(c, dark: false)
        return Color(red: x.r, green: x.g, blue: x.b)
        #endif
    }

    /// Whether a stored value is something this version can show (a preset or a well-formed hex colour).
    static func isValid(_ raw: String) -> Bool { AppAccent(rawValue: raw) != nil || rgb(raw) != nil }
    static func isCustom(_ raw: String) -> Bool { AppAccent(rawValue: raw) == nil && rgb(raw) != nil }

    /// "#RRGGBB" to 0–1 components, or nil for anything else.
    static func rgb(_ raw: String) -> (r: Double, g: Double, b: Double)? {
        guard raw.count == 7, raw.first == "#", let v = UInt32(raw.dropFirst(), radix: 16) else { return nil }
        return (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    static func hex(r: Double, g: Double, b: Double) -> String {
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

}

/// One palette for both the app and its widget extension.
enum AppAccent: String, CaseIterable, Identifiable {
    case green, mint, teal, cyan, blue, indigo, purple, pink, red, orange, brown, graphite, sunshine, revved, anytime

    static let storageKey = "accent"
    static let standard = AppAccent.green
    /// Counter Emerald, the brand green (same as the AccentColor asset): #01714C, or #2BC47A in dark mode.
    #if canImport(UIKit)
    static let emerald = Color(UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0x2B / 255, green: 0xC4 / 255, blue: 0x7A / 255, alpha: 1)
        : UIColor(red: 0x01 / 255, green: 0x71 / 255, blue: 0x4C / 255, alpha: 1) })
    #else
    static let emerald = Color(red: 0x01 / 255, green: 0x71 / 255, blue: 0x4C / 255)
    #endif
    var id: Self { self }
    var name: String { rawValue.capitalized }
    /// In light mode, darker shades of the system colours so text and buttons in the colour stay readable
    /// (at least 4.5:1 on white, the cream backgrounds and tinted buttons). Dark mode uses the system colours.
    var color: Color {
        #if canImport(UIKit)
        switch self {
        case .green: AppAccent.emerald
        case .mint: Self.readable(0x006D63, dark: .systemMint)
        case .teal: Self.readable(0x006B79, dark: .systemTeal)
        case .cyan: Self.readable(0x00698B, dark: .systemCyan)
        case .blue: Self.readable(0x005DC2, dark: .systemBlue)
        case .indigo: Self.readable(0x4B45D1, dark: .systemIndigo)
        case .purple: Self.readable(0x8A2FB0, dark: .systemPurple)
        case .pink: Self.readable(0xB71756, dark: .systemPink)
        case .red: Self.readable(0xB52525, dark: .systemRed)
        case .orange: Self.readable(0x9D4900, dark: .systemOrange)
        case .brown: Self.readable(0x7A5634, dark: .systemBrown)
        case .graphite: Self.readable(0x5E5E63, dark: .systemGray)
        // Sunshine pack: orange #FF8800 in dark mode; #B64A00 is the brightest orange that still reads at 4.5:1 in light mode.
        // Anytime pack: purple #5E56A3 (reads as is in light mode, lightened to 4.5:1 in dark mode).
        case .anytime: Self.readable(0x5E56A3, dark: UIColor(red: 0x5E / 255, green: 0x56 / 255, blue: 0xA3 / 255, alpha: 1))
        // Revved pack: red #DD2B32 (lightened in dark mode to 4.5:1); #CC282E is the closest red that reads in light mode.
        case .revved: Self.readable(0xCC282E, dark: UIColor(red: 0xDD / 255, green: 0x2B / 255, blue: 0x32 / 255, alpha: 1))
        case .sunshine: Self.readable(0xB64A00, dark: UIColor(red: 1, green: 0x88 / 255, blue: 0, alpha: 1))
        }
        #else
        switch self {
        case .green: AppAccent.emerald
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .brown: .brown
        case .graphite: .gray
        case .sunshine: Color(red: 1, green: 0x88 / 255, blue: 0)
        case .revved: Color(red: 0xDD / 255, green: 0x2B / 255, blue: 0x32 / 255)
        case .anytime: Color(red: 0x5E / 255, green: 0x56 / 255, blue: 0xA3 / 255)
        }
        #endif
    }

    #if canImport(UIKit)
    /// Dark mode starts from the system colour, then goes through `ThemeColour.readable` so every preset
    /// reaches 4.5:1 on dark cards too (system indigo on its own is only about 3.4:1).
    private static func readable(_ light: UInt32, dark: UIColor) -> Color {
        let shade = UIColor(red: CGFloat(light >> 16 & 0xFF) / 255, green: CGFloat(light >> 8 & 0xFF) / 255, blue: CGFloat(light & 0xFF) / 255, alpha: 1)
        return Color(UIColor { trait in
            guard trait.userInterfaceStyle == .dark else { return shade }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            dark.resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
            let x = ThemeColour.readable((Double(r), Double(g), Double(b)), dark: true)
            return UIColor(red: x.r, green: x.g, blue: x.b, alpha: 1)
        })
    }
    #endif
}
