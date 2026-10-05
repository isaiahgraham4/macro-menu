import Foundation

/// Spreadsheet exports of the food log. Missing figures stay blank rather than zero, so a total is never passed off as complete.
enum LogExport {
    /// One row per food logged.
    static func items(_ data: AppData, chainName: (String) -> String) -> String {
        let extras = nutrientNames.dropFirst(4)
        var rows = [["Date", "Time", "Meal time", "Meal", "Food", "Restaurant", "Serving", "Quantity", "Calories", "kJ", "Protein (g)", "Carbs (g)", "Fat (g)"]
                    + extras.map { "\($0.label) (\($0.unit))" }]
        for day in data.logs.keys.sorted() {
            for entry in (data.logs[day] ?? []).sorted(by: { $0.time < $1.time }) {
                for item in entry.items {
                    let food = item.food, q = item.quantity
                    rows.append([day, time(entry.time), entry.mealTime?.title ?? "", entry.name, food.name, chainName(food.chain), food.serve, number(q, places: 2),
                                 number(food.cal * q), number(food.kj * q), number(food.p * q), number(food.c.map { $0 * q }), number(food.f.map { $0 * q })]
                                + extras.map { n in number(food.nut?[n.key].map { $0 * q }) })
                }
            }
        }
        return csv(rows)
    }

    /// One row per logged day, with that day's targets. "Incomplete" names totals where some foods had no figure.
    static func days(_ data: AppData) -> String {
        let keys = nutrientNames.map(\.key)
        var rows = [["Date", "Meals"] + nutrientNames.map { "\($0.label) (\($0.unit))" } + ["Incomplete"]
                    + nutrientNames.map { "\($0.label) target (\($0.unit))" }]
        let current = data.goalSets.first { $0.id == data.activeGoal } ?? data.goalSets.first
        for day in data.logs.keys.sorted() {
            let entries = data.logs[day] ?? []
            guard !entries.isEmpty else { continue }
            let items = entries.flatMap(\.items), total = Nutrition(items)
            // Blank when no food that day listed the figure; a 0 would read as a real total.
            func listed(_ key: String) -> Bool {
                switch key {
                case "cal", "p": true
                case "c": items.contains { $0.food.c != nil }
                case "f": items.contains { $0.food.f != nil }
                default: total.nut[key] != nil
                }
            }
            let incomplete = nutrientNames.filter { total.isPartial($0.key) }.map(\.label).joined(separator: "; ")
            let goals = data.dayGoals[day] ?? current
            rows.append([day, String(entries.count)]
                        + keys.map { key in listed(key) ? number(total.value(key)) : "" }
                        + [incomplete] + keys.map { number(goals?.values[$0]) })
        }
        return csv(rows)
    }

    static func csv(_ rows: [[String]]) -> String {
        rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// Quotes a field when needed. Text that a spreadsheet would run as a formula gets a leading apostrophe.
    static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first), Double(text) == nil { text = "'" + text }
        guard text.contains(where: { ",\"\r\n".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double?, places: Int = 1) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...places)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
