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
    var color: Color {
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
    }
}
