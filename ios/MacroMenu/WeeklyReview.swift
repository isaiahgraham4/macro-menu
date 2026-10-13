import Foundation

/// A look back over the seven days ending on a given day: how much you logged, averages against target,
/// how many days hit protein, the weight trend and your most-logged meals.
struct WeeklyReview: Equatable, Sendable {
    struct Meal: Equatable, Sendable { var name: String; var count: Int }
    var start: Date
    var end: Date
    var loggedDays: Int
    /// Everything logged in the week, and the targets of the logged days added up.
    var totalCalories: Double
    var totalCalorieTarget: Double?
    /// Averages over the days you logged, not all seven.
    var averageCalories: Double?
    var averageProtein: Double?
    var calorieTarget: Double?
    var proteinTarget: Double?
    /// Logged days with protein at or above target, and with calories at or under target.
    var proteinDays: Int
    var calorieDays: Int
    /// Change in the smoothed weight trend across the week, in kg.
    var weightChange: Double?
    var trendWeight: Double?
    var topMeals: [Meal]
    /// Fibre and sodium over the week; see `NutrientWeek`.
    var fibre: NutrientWeek
    var sodium: NutrientWeek

    /// One nutrient across the week. Only days where every food logged lists the nutrient are counted, because a total with
    /// gaps in it would read as lower than it was.
    struct NutrientWeek: Equatable, Sendable {
        /// Average over the counted days.
        var average: Double?
        var target: Double
        /// True when the person hasn't set a target, so `target` is the general guide.
        var targetIsGuide: Bool
        /// True for a goal to reach (fibre), false for a limit to stay under (sodium).
        var isMinimum: Bool
        /// Counted days, and how many of those met the target.
        var countedDays: Int
        var daysMet: Int
        /// Days logged this week, counted or not.
        var loggedDays: Int
        /// How far the average is from the target as a fraction of it: positive is on the good side.
        var margin: Double? { average.map { isMinimum ? $0 / target - 1 : 1 - $0 / target } }
        var onTarget: Bool { (margin ?? -1) >= 0 }
    }

    /// Reference amounts used when no target is set: about 25 g of fibre and no more than 2,000 mg of sodium a day,
    /// which are the Australian adult guides.
    static let fibreGuide = 25.0
    static let sodiumGuide = 2000.0

    static func make(_ data: AppData, goals: Goals, ending end: Date = Date(), calendar: Calendar = .current) -> WeeklyReview {
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -6, to: last) ?? last
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }.map(dayKey)
        var calories: [Double] = [], protein: [Double] = [], calorieTargets: [Double] = [], proteinTargets: [Double] = []
        var proteinDays = 0, calorieDays = 0
        var counts: [String: (name: String, count: Int)] = [:]
        var fibreDays: [Double] = [], sodiumDays: [Double] = []
        var fibreTargets: [Double] = [], sodiumTargets: [Double] = []
        var fibreMinimum = true, sodiumMinimum = false
        var fibreMet = 0, sodiumMet = 0
        for key in days {
            let entries = data.logs[key] ?? []
            guard !entries.isEmpty else { continue }
            let total = Nutrition(entries.flatMap(\.items)), target = data.dayGoals[key] ?? goals
            calories.append(total.cal); protein.append(total.p)
            if let cal = target.values["cal"] { calorieTargets.append(cal); if total.cal <= cal { calorieDays += 1 } }
            if let p = target.values["p"] { proteinTargets.append(p); if total.p >= p { proteinDays += 1 } }
            for entry in entries { counts[entry.name.lowercased(), default: (entry.name, 0)].count += 1 }
            // Fibre and sodium count only when every food that day lists them.
            func counted(_ nutrient: String) -> Double? {
                guard let value = total.nut[nutrient], !total.isPartial(nutrient) else { return nil }
                return value
            }
            if let fibre = counted("fibre") {
                fibreDays.append(fibre)
                let wanted = target.values["fibre"]
                if let wanted { fibreTargets.append(wanted); fibreMinimum = target.minimums.contains("fibre") }
                let goal = wanted ?? fibreGuide
                if target.values["fibre"] == nil || target.minimums.contains("fibre") ? fibre >= goal : fibre <= goal { fibreMet += 1 }
            }
            if let sodium = counted("sodium") {
                sodiumDays.append(sodium)
                let wanted = target.values["sodium"]
                if let wanted { sodiumTargets.append(wanted); sodiumMinimum = target.minimums.contains("sodium") }
                let goal = wanted ?? sodiumGuide
                if target.values["sodium"] == nil || !target.minimums.contains("sodium") ? sodium <= goal : sodium >= goal { sodiumMet += 1 }
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }

        // The trend on the last weigh-in before the week, against the last one in it.
        let points = WeightTrend.points(data.weightLog, calendar: calendar)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let inWeek = points.last { $0.date >= first && $0.date < dayAfter }
        let before = points.last { $0.date < first }
        let meals = counts.values.filter { $0.count >= 2 }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }.prefix(3).map { Meal(name: $0.name, count: $0.count) }

        return WeeklyReview(start: first, end: last, loggedDays: calories.count,
                            totalCalories: calories.reduce(0, +),
                            totalCalorieTarget: calorieTargets.isEmpty ? nil : calorieTargets.reduce(0, +),
                            averageCalories: average(calories), averageProtein: average(protein),
                            calorieTarget: average(calorieTargets), proteinTarget: average(proteinTargets),
                            proteinDays: proteinDays, calorieDays: calorieDays,
                            weightChange: inWeek.flatMap { now in before.map { now.trend - $0.trend } }, trendWeight: inWeek?.trend,
                            topMeals: Array(meals),
                            fibre: NutrientWeek(average: average(fibreDays), target: average(fibreTargets) ?? fibreGuide,
                                                targetIsGuide: fibreTargets.isEmpty, isMinimum: fibreTargets.isEmpty || fibreMinimum,
                                                countedDays: fibreDays.count, daysMet: fibreMet, loggedDays: calories.count),
                            sodium: NutrientWeek(average: average(sodiumDays), target: average(sodiumTargets) ?? sodiumGuide,
                                                 targetIsGuide: sodiumTargets.isEmpty, isMinimum: !sodiumTargets.isEmpty && sodiumMinimum,
                                                 countedDays: sodiumDays.count, daysMet: sodiumMet, loggedDays: calories.count))
    }

    /// One line for the Sunday notification.
    var summary: String {
        guard loggedDays > 0 else { return "Nothing logged this week yet." }
        var parts = ["Logged \(loggedDays) of 7 days"]
        parts.append("\(totalCalories.rounded().number) Cal in total")
        if let averageCalories { parts.append("avg \(averageCalories.rounded().number)") }
        if proteinTarget != nil { parts.append("protein target hit \(proteinDays) \(proteinDays == 1 ? "day" : "days")") }
        if let weightChange { parts.append("trend \(Self.signed(weightChange)) kg") }
        return parts.joined(separator: " · ") + "."
    }

    /// Gentle notes on fibre and sodium. Nothing is said until at least two days have complete figures, because one day is noise.
    var nudges: [String] {
        var notes: [String] = []
        if let average = fibre.average, fibre.countedDays >= 2 {
            let target = fibre.target.rounded().number, got = average.rounded().number
            if fibre.onTarget {
                notes.append("Fibre averaged \(got) g a day, at or above \(fibre.targetIsGuide ? "the \(target) g guide" : "your \(target) g target"). Keep it up.")
            } else if (fibre.margin ?? -1) >= -0.2 {
                notes.append("Fibre averaged \(got) g a day, a little under \(fibre.targetIsGuide ? "the \(target) g guide" : "your \(target) g target"). Beans, lentils, oats or an extra piece of fruit would close the gap.")
            } else {
                notes.append("Fibre averaged \(got) g a day against \(fibre.targetIsGuide ? "a guide of" : "your target of") \(target) g. Beans, lentils, oats, wholegrain bread, vegetables and fruit with the skin on are the easy additions.")
            }
        }
        if let average = sodium.average, sodium.countedDays >= 2 {
            let target = sodium.target.rounded().number, got = average.rounded().number
            let limit = sodium.targetIsGuide ? "the \(target) mg guide" : "your \(target) mg target"
            if sodium.onTarget {
                notes.append("Sodium averaged \(got) mg a day, \(sodium.isMinimum ? "at or above" : "within") \(limit).")
            } else if sodium.isMinimum {
                notes.append("Sodium averaged \(got) mg a day, under \(limit).")
            } else {
                let over = sodium.countedDays - sodium.daysMet
                notes.append("Sodium averaged \(got) mg a day, above \(limit), and over it on \(over) of \(sodium.countedDays) days. Sauces, processed meats, bread and takeaway are the usual sources, so a lower-salt swap or smaller portion of those is the easy place to start.")
            }
        }
        return notes
    }

    static func signed(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return (rounded > 0 ? "+" : rounded < 0 ? "−" : "") + abs(rounded).number
    }
}
