import Foundation

/// A place on the body that can be measured. Stored by `rawValue`, so a site added later still loads on an older build.
enum BodySite: String, CaseIterable, Identifiable, Sendable {
    case waist, hips, chest, neck, arm, thigh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .waist: "Waist"
        case .hips: "Hips"
        case .chest: "Chest"
        case .neck: "Neck"
        case .arm: "Upper arm"
        case .thigh: "Thigh"
        }
    }
}

/// Tape measurements taken on one day. Any subset of sites, in centimetres.
struct BodyMeasurement: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var date: Date
    var values: [String: Double]
    /// Unknown site names are allowed, so a backup from a newer version still loads.
    var isValid: Bool { !values.isEmpty && values.values.allSatisfy { $0.isFinite && (5...300).contains($0) } }
}

enum BodyMeasurements {
    struct Reading: Hashable, Sendable {
        var date: Date
        var cm: Double
    }

    /// What a site has done: the latest reading, the one before it and the first ever.
    struct Change: Equatable, Sendable {
        var latest: Reading
        var previous: Reading?
        var first: Reading?
        /// Latest less previous, and latest less first, in centimetres. Nil with only one reading.
        var sinceLast: Double? { previous.map { latest.cm - $0.cm } }
        var sinceFirst: Double? { first.map { latest.cm - $0.cm } }
    }

    /// One reading a day for a site (the day's last), oldest first.
    static func readings(_ entries: [BodyMeasurement], site: String, calendar: Calendar = .current) -> [Reading] {
        var byDay: [Date: Reading] = [:]
        for entry in entries where entry.isValid {
            guard let cm = entry.values[site] else { continue }
            let day = calendar.startOfDay(for: entry.date)
            if let existing = byDay[day], existing.date >= entry.date { continue }
            byDay[day] = Reading(date: entry.date, cm: cm)
        }
        return byDay.keys.sorted().compactMap { byDay[$0] }
    }

    static func change(_ readings: [Reading]) -> Change? {
        guard let latest = readings.last else { return nil }
        guard readings.count >= 2 else { return Change(latest: latest, previous: nil, first: nil) }
        return Change(latest: latest, previous: readings[readings.count - 2], first: readings[0])
    }

    /// Sites with at least one reading: the standard ones in their usual order, then any others.
    static func sites(in entries: [BodyMeasurement]) -> [String] {
        let present = Set(entries.filter(\.isValid).flatMap { $0.values.keys })
        let standard = BodySite.allCases.map(\.rawValue).filter(present.contains)
        return standard + present.subtracting(standard).sorted()
    }

    static func title(_ site: String) -> String { BodySite(rawValue: site)?.title ?? site.capitalized }

    /// "−3.5 cm", "+1 cm", "no change".
    static func signed(_ cm: Double) -> String {
        let rounded = (cm * 10).rounded() / 10
        guard rounded != 0 else { return "no change" }
        return (rounded > 0 ? "+" : "−") + abs(rounded).number + " cm"
    }
}
