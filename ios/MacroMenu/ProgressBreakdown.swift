import Foundation

/// A look back over the last 7, 30 or 90 days for the Progress tab: how much you logged, averages against target,
/// the macro split, where the day's calories go, what contributed most, water and weight change.
/// Averages count only the days you logged, and a nutrient only on days where every food listed it.
struct ProgressBreakdown: Equatable, Sendable {
    struct DayPoint: Equatable, Sendable, Identifiable {
        var key: String
        var date: Date
        /// Nil on a day with nothing logged.
        var calories: Double?
        var protein: Double?
        var calorieTarget: Double?
        var id: String { key }
    }
    /// An average over the days where the figure was complete.
    struct Average: Equatable, Sendable {
        var value: Double?
        var countedDays: Int
    }
    struct MacroShare: Equatable, Sendable {
        var protein: Double
        var carbs: Double
        var fat: Double
    }
    struct MealShare: Equatable, Sendable, Identifiable {
        var mealTime: MealTime?
        /// Average calories at this meal time, over the days you logged.
        var averageCalories: Double
        var id: String { mealTime?.rawValue ?? "unassigned" }
        var title: String { mealTime?.title ?? "Unassigned" }
    }
    struct FoodTotal: Equatable, Sendable, Identifiable {
        var name: String
        var servings: Double
        var calories: Double
        var protein: Double
        var id: String { name.lowercased() }
    }

    var days: Int
    var start: Date
    var end: Date
    var loggedDays: Int
    var points: [DayPoint]
    var averageCalories: Double?
    var averageProtein: Double?
    var calorieTarget: Double?
    var proteinTarget: Double?
    /// Logged days at or under the calorie target, and at or over the protein target.
    var calorieDays: Int
    var proteinDays: Int
    var carbs: Average
    var fat: Average
    var fibre: Average
    var sodium: Average
    /// Share of the calories from protein, carbs and fat, over everything logged. Nil with nothing logged.
    var share: MacroShare?
    /// False when some logged foods list no carbs or fat, which makes the shares approximate.
    var shareComplete: Bool
    var mealTimes: [MealShare]
    var topFoods: [FoodTotal]
    /// Average water on the days you logged any.
    var water: Average
    var startTrend: Double?
    var endTrend: Double?
    var weightChange: Double? { startTrend.flatMap { start in endTrend.map { $0 - start } } }

    static let ranges = [7, 30, 90]

    static func make(_ data: AppData, goals: Goals, days: Int, ending end: Date = Date(), calendar: Calendar = .current) -> ProgressBreakdown {
        let last = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: last) ?? last
        var points: [DayPoint] = []
        var calories: [Double] = [], protein: [Double] = []
        var calorieTargets: [Double] = [], proteinTargets: [Double] = []
        var calorieDays = 0, proteinDays = 0
        var carbs: [Double] = [], fat: [Double] = [], fibre: [Double] = [], sodium: [Double] = []
        var shareTotals = (p: 0.0, c: 0.0, f: 0.0), shareComplete = true
        var mealTotals: [MealTime?: Double] = [:]
        var foods: [String: FoodTotal] = [:]
        var water: [Double] = []

        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            let key = dayKey(date)
            let target = data.dayGoals[key] ?? goals
            if let ml = data.water?[key], ml > 0 { water.append(ml) }
            let entries = data.logs[key] ?? []
            guard !entries.isEmpty else {
                points.append(DayPoint(key: key, date: date, calories: nil, protein: nil, calorieTarget: target.values["cal"]))
                continue
            }
            let items = entries.flatMap(\.items), total = Nutrition(items)
            points.append(DayPoint(key: key, date: date, calories: total.cal, protein: total.p, calorieTarget: target.values["cal"]))
            calories.append(total.cal); protein.append(total.p)
            if let cal = target.values["cal"] { calorieTargets.append(cal); if total.cal <= cal { calorieDays += 1 } }
            if let p = target.values["p"] { proteinTargets.append(p); if total.p >= p { proteinDays += 1 } }
            if !total.missingCarbs { carbs.append(total.c) }
            if !total.missingFat { fat.append(total.f) }
            if let value = total.nut["fibre"], !total.isPartial("fibre") { fibre.append(value) }
            if let value = total.nut["sodium"], !total.isPartial("sodium") { sodium.append(value) }
            shareTotals.p += total.p * 4; shareTotals.c += total.c * 4; shareTotals.f += total.f * 9
            if total.missingCarbs || total.missingFat { shareComplete = false }
            for entry in entries { mealTotals[entry.mealTime, default: 0] += Nutrition(entry.items).cal }
            for item in items {
                let name = item.food.name, id = item.food.chain + "|" + name.lowercased()
                var row = foods[id] ?? FoodTotal(name: name, servings: 0, calories: 0, protein: 0)
                row.servings += item.quantity; row.calories += item.food.cal * item.quantity; row.protein += item.food.p * item.quantity
                foods[id] = row
            }
        }
        func average(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
        func counted(_ values: [Double]) -> Average { Average(value: average(values), countedDays: values.count) }

        let shareSum = shareTotals.p + shareTotals.c + shareTotals.f
        let share = shareSum > 0 ? MacroShare(protein: shareTotals.p / shareSum, carbs: shareTotals.c / shareSum, fat: shareTotals.f / shareSum) : nil
        let logged = Double(max(1, calories.count))
        let order: [MealTime?] = MealTime.allCases.map { Optional($0) } + [nil]
        let mealTimes = order.compactMap { time in mealTotals[time].map { MealShare(mealTime: time, averageCalories: $0 / logged) } }
        let top = foods.values.sorted { ($0.calories, $1.name) > ($1.calories, $0.name) }.prefix(5)

        // The trend on the last weigh-in before the range, or the first inside it, against the last inside it.
        let trend = WeightTrend.points(data.weightLog, calendar: calendar)
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        let inRange = trend.filter { $0.date >= first && $0.date < dayAfter }
        let baseline = trend.last { $0.date < first } ?? inRange.first
        let endPoint = inRange.last
        let usable = baseline != nil && endPoint != nil && baseline != endPoint

        return ProgressBreakdown(
            days: days, start: first, end: last, loggedDays: calories.count, points: points,
            averageCalories: average(calories), averageProtein: average(protein),
            calorieTarget: average(calorieTargets), proteinTarget: average(proteinTargets),
            calorieDays: calorieDays, proteinDays: proteinDays,
            carbs: counted(carbs), fat: counted(fat), fibre: counted(fibre), sodium: counted(sodium),
            share: share, shareComplete: shareComplete, mealTimes: mealTimes, topFoods: Array(top),
            water: counted(water),
            startTrend: usable ? baseline?.trend : nil, endTrend: endPoint?.trend)
    }
}
