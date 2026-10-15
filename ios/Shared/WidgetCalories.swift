import Foundation

/// A small read-only projection of the food log shared with the widget extension.
struct WidgetCalories: Codable, Equatable, Sendable {
    static let groupID = "group.com.isaiahgraham.MacroMenu"
    static let kind = "LeanrCaloriesLeft"
    static let premiumKind = "LeanrAllTargets"
    static let macrosKind = "LeanrMacros"
    static let streakKind = "LeanrTrackingStreak"
    static let stepsKind = "LeanrSteps"
    static let burntKind = "LeanrCaloriesBurnt"
    var target: Double?
    var dailyCalories: [String: Double]
    // Optional so snapshots written before colour syncing still decode.
    var accent: String? = nil
    var nutrientTargets: [WidgetNutrientTarget]? = nil
    var dailyNutrients: [String: [String: Double]]? = nil
    var dailyPartialNutrients: [String: [String]]? = nil
    var premiumUnlocked: Bool? = nil
    var trackedDays: [String]? = nil
    var macroColours: [String: String]? = nil
    /// Usual meals and pinned foods for the Log again widget.
    var quickLogOptions: [WidgetQuickLog]? = nil
    /// Steps by day for the last week, from Apple Health, and the daily goal, for the Steps widget.
    var steps: [String: Double]? = nil
    var stepGoal: Double? = nil
    /// Active energy (calories burnt) by day for the last week, from Apple Health, for the Calories burnt widget.
    var activeEnergy: [String: Double]? = nil
    /// Today's planned meals that aren't logged yet, in meal order, for the Planned widget ("plan:<entry ID>"), and the day they're for.
    var planned: [WidgetQuickLog]? = nil
    var plannedDay: String? = nil
    /// Water by day for the last week in mL, the daily target and one glass, for the Water widget.
    var water: [String: Double]? = nil
    var waterTarget: Double? = nil
    var waterGlass: Double? = nil
    func waterDrunk(on date: Date) -> Double { water?[WidgetCalories.dayKey(date)] ?? 0 }
    /// The planned meals still to log on `date`; none once the day they were for has passed.
    func plannedMeals(on date: Date) -> [WidgetQuickLog] { plannedDay == WidgetCalories.dayKey(date) ? planned ?? [] : [] }
    var trackingDays: Set<String> { Set(trackedDays ?? Array(dailyCalories.filter { $0.value > 0 }.keys)) }
    func streak(on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        TrackingStreak.count(days: trackingDays, on: date, calendar: calendar)
    }
    var selectedAccent: AppAccent { accent.flatMap(AppAccent.init(rawValue:)) ?? .standard }

    var isValid: Bool {
        (target.map { $0.isFinite && $0 > 0 } ?? true) &&
        dailyCalories.values.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (nutrientTargets ?? []).allSatisfy { $0.target.isFinite && $0.target > 0 } &&
        (steps ?? [:]).values.allSatisfy { $0.isFinite && $0 >= 0 } && (stepGoal.map { $0.isFinite && $0 > 0 } ?? true) &&
        (activeEnergy ?? [:]).values.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (water ?? [:]).values.allSatisfy { $0.isFinite && $0 >= 0 } && (waterTarget.map { $0.isFinite && $0 > 0 } ?? true) &&
        (waterGlass.map { $0.isFinite && $0 > 0 } ?? true) &&
        (dailyNutrients ?? [:]).values.allSatisfy { $0.values.allSatisfy { $0.isFinite && $0 >= 0 } }
    }

    func eaten(on date: Date, timeZone: TimeZone = .current) -> Double {
        dailyCalories[Self.dayKey(date, timeZone: timeZone)] ?? 0
    }

    func remaining(on date: Date, timeZone: TimeZone = .current) -> Double? {
        target.map { $0 - eaten(on: date, timeZone: timeZone) }
    }

    static func dayKey(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Future entries reset the display even if the app isn't opened at midnight.
    static func timelineDates(from date: Date, calendar: Calendar = .current) -> [Date] {
        [date] + (1...7).compactMap {
            calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: date))
        }
    }

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("calories-widget.json")
    }

    static func read() -> WidgetCalories? {
        guard let url = fileURL, let bytes = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: bytes), value.isValid else { return nil }
        return value
    }
}

enum TrackingStreak {
    /// Today remains available to log; yesterday's streak stays active until tonight.
    static func count(days: Set<String>, on date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        var cursor = calendar.startOfDay(for: date)
        if !days.contains(WidgetCalories.dayKey(cursor, timeZone: calendar.timeZone)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(WidgetCalories.dayKey(cursor, timeZone: calendar.timeZone)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

struct WidgetNutrientTarget: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var unit: String
    var target: Double
    var minimum: Bool
}

/// Where a day's total stands against a target, so widgets can colour the text.
enum TargetStatus: Equatable, Sendable {
    case none
    /// Protein's goal is met.
    case reached
    /// Carbs or fat went past the target.
    case over

    /// Protein is a goal to reach, so it's `reached` at the target or beyond. Carbs and fat are limits, so they're `over` once past it.
    /// Totals are compared as the widget shows them (to a tenth), so "150 / 150 g" never reads as under.
    static func of(_ id: String, value: Double, target: Double?) -> TargetStatus {
        guard let target, target > 0, value.isFinite else { return .none }
        let shown = (value * 10).rounded() / 10, goal = (target * 10).rounded() / 10
        switch id {
        case "p": return shown >= goal ? .reached : .none
        case "c", "f": return shown > goal ? .over : .none
        default: return .none
        }
    }

    /// Said after a macro by VoiceOver, since the colour alone isn't enough.
    var spoken: String {
        switch self {
        case .none: ""
        case .reached: " Goal reached."
        case .over: " Over target."
        }
    }
}

/// One thing the Log again widget offers: your usual meal for a meal time, or a pinned food.
struct WidgetQuickLog: Codable, Equatable, Identifiable, Sendable {
    /// "usual:breakfast" or "pin:<food ID>".
    var id: String
    var name: String
    var calories: Double
    /// For a usual meal, the meal time it's for and logs to.
    var mealTime: String?
    /// The day it was last logged ("yyyy-MM-dd") when the snapshot was made, to show a tick once it's in today's log.
    var lastLogged: String?
    /// Its protein, carbs, fat and other targeted nutrients, so a tap can be shown in those widgets straight away.
    var nutrients: [String: Double]? = nil
    var isUsual: Bool { id.hasPrefix("usual:") }
}

/// Meal times by the clock, shared with the widget so it can switch to the next meal on its own.
enum MealSlot {
    static func at(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<11: "breakfast"
        case 11..<16: "lunch"
        case 16..<22: "dinner"
        default: "snacks"
        }
    }
    /// The next times the meal time changes, soonest first.
    static func changes(after date: Date, calendar: Calendar = .current) -> [Date] {
        [5, 11, 16, 22].compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime)
        }.sorted()
    }
}

extension WidgetCalories {
    /// Calories burnt (active energy) on a day, nil when none are known.
    func energyBurnt(on date: Date, timeZone: TimeZone = .current) -> Double? {
        activeEnergy?[Self.dayKey(date, timeZone: timeZone)].flatMap { $0 > 0 ? $0 : nil }
    }

    /// The average over the other days in the snapshot that have any recorded, to put today in context. Nil with none.
    func energyAverage(excluding date: Date, timeZone: TimeZone = .current) -> Double? {
        let today = Self.dayKey(date, timeZone: timeZone)
        let others = (activeEnergy ?? [:]).filter { $0.key != today && $0.value > 0 }.map(\.value)
        return others.isEmpty ? nil : others.reduce(0, +) / Double(others.count)
    }

    /// Steps on a day, nil when none are known.
    func stepCount(on date: Date, timeZone: TimeZone = .current) -> Double? {
        steps?[Self.dayKey(date, timeZone: timeZone)].flatMap { $0 > 0 ? $0 : nil }
    }
    static let logAgainKind = "LeanrLogAgain"
    static let plannedKind = "LeanrPlanned"
    static let waterKind = "LeanrWater"
    /// The Water widget's button: "water:250" adds 250 mL to the day it's tapped.
    static func waterOption(_ millilitres: Double) -> String { "water:\(Int(millilitres.rounded()))" }
    static func waterAmount(_ option: String) -> Double? {
        guard option.hasPrefix("water:"), let amount = Double(option.dropFirst(6)), amount > 0, amount <= 2000 else { return nil }
        return amount
    }
    /// What the Log again widget shows at `date`: the usual meal for that meal time first, then pinned foods.
    func quickLogs(at date: Date) -> [WidgetQuickLog] {
        let slot = MealSlot.at(date), options = quickLogOptions ?? []
        let usual = options.filter { $0.isUsual && $0.mealTime == slot }
        // A pinned food that is also the usual meal shows once.
        return usual + options.filter { pin in !pin.isUsual && !usual.contains { $0.name == pin.name } }
    }
}

extension WidgetCalories {
    static let allKinds = [waterKind, plannedKind, logAgainKind, stepsKind, burntKind, kind, premiumKind, macrosKind, streakKind]

    /// The widgets that a change from `old` to this affects, with the ones people tap first at the front: a tap on a widget shows its
    /// result as soon as that widget reloads, so water or a planned meal doesn't wait behind the calorie widgets.
    func kindsChanged(from old: WidgetCalories?) -> [String] {
        guard let old else { return Self.allKinds }
        // Colours and Premium change how every widget looks.
        if accent != old.accent || premiumUnlocked != old.premiumUnlocked || macroColours != old.macroColours { return Self.allKinds }
        var kinds: [String] = []
        func add(_ new: [String]) { for k in new where !kinds.contains(k) { kinds.append(k) } }
        if water != old.water || waterTarget != old.waterTarget || waterGlass != old.waterGlass { add([Self.waterKind]) }
        if planned != old.planned || plannedDay != old.plannedDay { add([Self.plannedKind]) }
        if quickLogOptions != old.quickLogOptions { add([Self.logAgainKind]) }
        if steps != old.steps || stepGoal != old.stepGoal { add([Self.stepsKind]) }
        if activeEnergy != old.activeEnergy { add([Self.burntKind]) }
        if dailyCalories != old.dailyCalories || target != old.target || nutrientTargets != old.nutrientTargets
            || dailyNutrients != old.dailyNutrients || dailyPartialNutrients != old.dailyPartialNutrients || trackedDays != old.trackedDays {
            // Log again and Planned show calories left, too.
            add([Self.logAgainKind, Self.plannedKind, Self.kind, Self.premiumKind, Self.macrosKind, Self.streakKind])
        }
        return kinds
    }
}

/// Requests from the widget that Leanr couldn't log straight away. The app logs them, with their original time, next time it runs.
enum QuickLogQueue {
    struct Request: Codable, Equatable, Sendable { var option: String; var date: Date }
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetCalories.groupID)?
            .appendingPathComponent("quick-log-queue.json")
    }
    static func read() -> [Request] {
        guard let url = fileURL, let bytes = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Request].self, from: bytes)) ?? []
    }
    static func write(_ requests: [Request]) {
        guard let url = fileURL else { return }
        if requests.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? JSONEncoder().encode(requests).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func add(_ option: String, at date: Date) { write(read() + [Request(option: option, date: date)]) }

    /// Shows a queued request on the widgets straight away: its calories and nutrients in today's totals, a tick on the option,
    /// a planned meal gone from the plan or the water added. Returns the widgets that changed, tapped-on one first, to reload.
    @discardableResult static func showQueued(_ option: String, at date: Date) -> [String] {
        guard let old = WidgetCalories.read(), let url = WidgetCalories.fileURL, let snapshot = old.applying(option, at: date) else { return [] }
        try? JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return snapshot.kindsChanged(from: old)
    }
}

extension WidgetCalories {
    /// This snapshot with a widget tap shown in it, or nil when the option isn't one it knows (so there's nothing to show).
    func applying(_ option: String, at date: Date) -> WidgetCalories? {
        var snapshot = self
        let day = WidgetCalories.dayKey(date)
        func addNutrients(_ item: WidgetQuickLog) {
            for (key, value) in item.nutrients ?? [:] where value.isFinite && value > 0 {
                snapshot.dailyNutrients?[day, default: [:]][key, default: 0] += value
            }
        }
        if let amount = WidgetCalories.waterAmount(option) {
            var water = snapshot.water ?? [:]
            water[day, default: 0] += amount
            snapshot.water = water
            return snapshot
        }
        // A planned meal leaves the Planned widget once it's logged.
        if let item = snapshot.planned?.first(where: { $0.id == option }) {
            snapshot.planned?.removeAll { $0.id == option }
            snapshot.dailyCalories[day, default: 0] += item.calories
            addNutrients(item)
        } else {
            guard let index = snapshot.quickLogOptions?.firstIndex(where: { $0.id == option }), let item = snapshot.quickLogOptions?[index] else { return nil }
            snapshot.dailyCalories[day, default: 0] += item.calories
            addNutrients(item)
            snapshot.quickLogOptions?[index].lastLogged = day
        }
        snapshot.trackedDays = Array(Set((snapshot.trackedDays ?? []) + [day])).sorted()
        return snapshot
    }
}