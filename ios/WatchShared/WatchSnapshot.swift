import Foundation

/// What Leanr on iPhone tells Apple Watch: today's calories, protein and water, and a few things to log with a tap.
/// It goes over as the application context, so the watch has the latest whenever it next looks.
struct WatchSnapshot: Codable, Equatable, Sendable {
    struct Option: Codable, Equatable, Identifiable, Sendable {
        /// "usual:breakfast" or "pin:<food ID>", the same as the Log again widget.
        var id: String
        var name: String
        var calories: Double
        var protein: Double
        /// Already in today's log when the snapshot was made.
        var loggedToday: Bool
    }

    /// The day the totals are for, "yyyy-MM-dd".
    var day: String
    var calories: Double
    var calorieTarget: Double?
    var protein: Double
    var proteinTarget: Double?
    /// Millilitres.
    var water: Double
    var waterTarget: Double
    var glass: Double
    var options: [Option]
    /// The app colour, by name (see `AppAccent`).
    var accent: String?

    static let contextKey = "snapshot"

    var caloriesLeft: Double? { calorieTarget.map { $0 - calories } }

    var context: [String: Any] {
        guard let data = try? JSONEncoder().encode(self) else { return [:] }
        return [Self.contextKey: data]
    }

    init(day: String, calories: Double, calorieTarget: Double?, protein: Double, proteinTarget: Double?,
         water: Double, waterTarget: Double, glass: Double, options: [Option], accent: String? = nil) {
        self.day = day; self.calories = calories; self.calorieTarget = calorieTarget; self.protein = protein
        self.proteinTarget = proteinTarget; self.water = water; self.waterTarget = waterTarget; self.glass = glass
        self.options = options; self.accent = accent
    }

    init?(context: [String: Any]) {
        guard let data = context[Self.contextKey] as? Data, let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    /// The snapshot as of `date`: one from an earlier day keeps its targets and options but starts the day at nothing.
    func current(on date: Date = Date()) -> WatchSnapshot {
        guard day != Self.key(date) else { return self }
        var fresh = self
        fresh.day = Self.key(date); fresh.calories = 0; fresh.protein = 0; fresh.water = 0
        fresh.options = options.map { var option = $0; option.loggedToday = false; return option }
        return fresh
    }

    /// The same as logging `option` would make it, shown straight away while the iPhone catches up.
    func logging(_ option: Option) -> WatchSnapshot {
        var updated = self
        updated.calories += option.calories; updated.protein += option.protein
        if let index = updated.options.firstIndex(where: { $0.id == option.id }) { updated.options[index].loggedToday = true }
        return updated
    }

    func addingWater(_ millilitres: Double) -> WatchSnapshot {
        var updated = self
        updated.water = max(0, water + millilitres)
        return updated
    }

    static func key(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

/// Something the watch asks Leanr on iPhone to do.
enum WatchRequest: Equatable, Sendable {
    /// Log one of the snapshot's options.
    case log(String)
    /// Add (or with a negative amount, take off) millilitres of water today.
    case water(Double)

    var message: [String: Any] {
        switch self {
        case .log(let option): ["log": option]
        case .water(let millilitres): ["water": millilitres]
        }
    }

    init?(message: [String: Any]) {
        if let option = message["log"] as? String, !option.isEmpty { self = .log(option) }
        else if let millilitres = message["water"] as? Double, millilitres.isFinite, millilitres != 0, abs(millilitres) <= 5000 { self = .water(millilitres) }
        else { return nil }
    }
}
