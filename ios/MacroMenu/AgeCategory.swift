import Foundation

/// The age categories app store age laws use: Texas SB 2420 (in force for new Texas Apple Accounts since 4 June 2026),
/// and Utah and Louisiana from 2027: under 13, 13 to 15, 16 to 17, and 18 or over.
/// Apple's Declared Age Range API shares one of these where the law requires it (see `AgeCheck.swift`).
/// Leanrrr only uses it to apply its own minimum age of 13 from the terms, and keeps it only on this device.
nonisolated enum AgeCategory: String, Codable, Sendable, CaseIterable {
    case under13, from13to15, from16to17, adult

    /// The age gates to ask for, so the answer lands in exactly one category.
    static let gates = (13, 16, 18)
    /// Leanrrr's minimum age, from the terms of use.
    static let minimumAge = 13

    /// The category for an age range from the App Store. Either bound can be missing: under 13 comes back as only an upper bound,
    /// and 18 or over as only a lower bound. Nil when there's nothing to go on.
    init?(lower: Int?, upper: Int?) {
        if let lower, lower >= 18 { self = .adult }
        else if let lower, lower >= 16 { self = .from16to17 }
        else if let lower, lower >= 13 { self = .from13to15 }
        else if let upper, upper < 13 { self = .under13 }
        else if let upper, upper < 16 { self = .from13to15 }
        else if let upper, upper < 18 { self = .from16to17 }
        else { return nil }
    }

    /// Whether Leanrrr's terms allow this person to use it.
    var meetsMinimumAge: Bool { self != .under13 }

    /// How often to ask the App Store again, so a birthday is picked up.
    static let recheckEvery: TimeInterval = 24 * 3600
}
