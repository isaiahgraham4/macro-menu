import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MacroColours {
    static let proteinKey = "macroColour.protein"
    static let carbsKey = "macroColour.carbs"
    static let fatKey = "macroColour.fat"
    static func colour(_ key: String, choices: [String: String]) -> Color {
        let fallback: AppAccent = key == "p" ? .blue : key == "c" ? .orange : .red
        return (choices[key].flatMap(AppAccent.init(rawValue:)) ?? fallback).color
    }
}

/// One palette for both the app and its widget extension.
enum AppAccent: String, CaseIterable, Identifiable {
    case green, mint, teal, cyan, blue, indigo, purple, pink, red, orange, brown, graphite

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
        }
        #endif
    }

    #if canImport(UIKit)
    private static func readable(_ light: UInt32, dark: UIColor) -> Color {
        let shade = UIColor(red: CGFloat(light >> 16 & 0xFF) / 255, green: CGFloat(light >> 8 & 0xFF) / 255, blue: CGFloat(light & 0xFF) / 255, alpha: 1)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? dark.resolvedColor(with: $0) : shade })
    }
    #endif
}
