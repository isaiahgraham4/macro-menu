import Foundation

/// Water drunk each day, in millilitres, against a daily target. Kept apart from food so it never touches calories or macros.
enum Water {
    static let defaultTarget = 2000.0
    static let defaultGlass = 250.0
    static let targetRange = 250.0...10000.0
    static let glassRange = 50.0...2000.0
    /// The most one day can hold, so a slip of the finger can't leave an absurd total.
    static let dayLimit = 20000.0

    static func target(_ data: AppData) -> Double { data.waterTarget ?? defaultTarget }
    static func glass(_ data: AppData) -> Double { data.waterGlass ?? defaultGlass }
    static func total(_ data: AppData, on day: String) -> Double { data.water?[day] ?? 0 }

    static func isDayKey(_ text: String) -> Bool { text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }

    /// The start of a day key like "2026-10-13", in the current time zone.
    static func date(of day: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    static func isValid(_ data: AppData) -> Bool {
        (data.water ?? [:]).allSatisfy { isDayKey($0.key) && $0.value.isFinite && (0...dayLimit).contains($0.value) }
            && (data.waterTarget.map { $0.isFinite && targetRange.contains($0) } ?? true)
            && (data.waterGlass.map { $0.isFinite && glassRange.contains($0) } ?? true)
    }

    /// Adds water to a day, or with a negative amount takes some off. A day never goes below nothing or above the limit,
    /// and a day back at nothing is removed rather than kept as a zero.
    static func adding(_ millilitres: Double, on day: String, to data: inout AppData) {
        guard millilitres.isFinite, isDayKey(day) else { return }
        let updated = min(dayLimit, max(0, total(data, on: day) + millilitres))
        var water = data.water ?? [:]
        if updated > 0 { water[day] = updated } else { water.removeValue(forKey: day) }
        data.water = water.isEmpty ? nil : water
    }

    /// "750 mL" or "1.25 L".
    static func text(_ millilitres: Double) -> String {
        if millilitres < 1000 { return "\(Int(millilitres.rounded())) mL" }
        return "\((millilitres / 1000).formatted(.number.precision(.fractionLength(0...2)))) L"
    }

    /// How full the day is against the target, from 0 to 1.
    static func progress(total: Double, target: Double) -> Double {
        target > 0 ? min(1, max(0, total / target)) : 0
    }

    /// The quick amounts offered besides a glass.
    static let bottleSizes: [Double] = [500, 750]

    /// What a spoken size means: a glass is whatever glass size is set, a bottle is 500 mL and a litre is a litre.
    enum Size: String, Sendable { case glass, bottle, litre }
    static func millilitres(_ size: Size, glass: Double) -> Double {
        switch size {
        case .glass: glass
        case .bottle: 500
        case .litre: 1000
        }
    }

    /// The most one spoken or shortcut amount may add at once.
    static let singleLimit = 5000.0

    /// "Logged 250 mL of water. 1.25 L of 2 L today." and, once the target is reached, "That's your 2 L target."
    static func loggedAnswer(added: Double, total: Double, target: Double) -> String {
        var text = "Logged \(Self.text(added)) of water. \(Self.text(total)) of \(Self.text(target)) today."
        if total >= target && target > 0 { text += " That's your \(Self.text(target)) target." }
        return text
    }

    /// "You've had 1.25 L of water today, 750 mL to go."
    static func todayAnswer(total: Double, target: Double) -> String {
        guard total > 0 else { return "You haven't logged any water today. Your target is \(text(target))." }
        if total >= target { return "You've had \(text(total)) of water today, which reaches your \(text(target)) target." }
        return "You've had \(text(total)) of water today, \(text(target - total)) to go."
    }
}
