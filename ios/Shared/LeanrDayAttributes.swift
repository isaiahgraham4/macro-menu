#if canImport(ActivityKit)
import ActivityKit
import SwiftUI

/// Today's calories on the Lock Screen and in the Dynamic Island. Shared by the app, which starts and updates it, and the widget, which draws it.
struct LeanrDayAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var eaten: Double
        var target: Double
        var protein: Double
        var proteinTarget: Double?
        var accent: String

        var over: Bool { eaten > target }
        var figure: String { abs(target - eaten).rounded().formatted(.number.precision(.fractionLength(0))) }
        var caption: String { over ? "Cal over" : "Cal left" }
        var progress: Double { target > 0 ? min(1, max(0, eaten / target)) : 0 }
        var color: Color { over ? .orange : (AppAccent(rawValue: accent) ?? .standard).color }
    }
    /// The day it's for, so tomorrow gets a new one.
    var day: String
}
#endif
