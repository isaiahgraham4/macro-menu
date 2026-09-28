import SwiftUI

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
    var id: Self { self }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .green: .green
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
