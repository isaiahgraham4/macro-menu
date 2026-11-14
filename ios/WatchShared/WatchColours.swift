import SwiftUI

/// The iPhone's colours on the watch. The snapshot carries them as "#RRGGBB" already shaded for a dark screen, so they're
/// used as they come; one that's missing or unreadable falls back to the defaults.
extension WatchSnapshot {
    /// Counter Emerald in dark mode, the same as the watch app's AccentColor asset.
    static let defaultAccent = Color(red: 0x2B / 255, green: 0xC4 / 255, blue: 0x7A / 255)

    var accentColour: Color { Self.colour(accent) ?? Self.defaultAccent }
    var proteinTint: Color { Self.colour(proteinColour) ?? .blue }

    static func colour(_ hex: String?) -> Color? {
        guard let hex, hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
