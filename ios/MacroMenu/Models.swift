import Foundation

struct Chain: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    var url: String?
    var src: String?
    var psrc: String?
}

struct Modifier: Codable, Identifiable, Hashable, Sendable {
    var key: String
    var id: String
    var kind: String
    var name: String
    var kj: Double
    var p: Double
    var c: Double?
    var f: Double?
    var nut: [String: Double]?
    var price: Double?
    /// True when protein, carbs and fat are estimated (McDonald's publishes only each ingredient's energy).
    var est: Bool?
    var group: String? {
        guard kind == "r" || kind == "s" else { return nil }
        return ["rice", "beans", "cheese", "caesar-dressing", "fries", "sour-cream", "guacamole", "pico", "lettuce", "tomatillo", "corn-chips", "jalapeno"].first { id.contains($0) } ?? id
    }
}

struct Food: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var chain = "mine"
    var name: String
    var cat = "main"
    var kj: Double
    var cal: Double
    var p: Double
    var c: Double?
    var f: Double?
    var serve = "1 serving"
    var nut: [String: Double]?
    var price: Double?
    var pf: Bool?
    var modifiers: [Modifier]?
    var ingredients: [Portion]?
    var recipeYield: Double?
    var note: String?
    /// The product barcode, so scanning it again finds this food.
    var barcode: String?
    var isAnchor: Bool { chain == "mine" || cat == "main" || cat == "breakfast" }
    var isValid: Bool {
        !id.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [kj, cal, p, c, f, price].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (nut ?? [:]).values.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (ingredients ?? []).allSatisfy(\.isValid) && (recipeYield.map { $0.isFinite && $0 > 0 } ?? true)
    }
    var mismatch: Bool {
        guard let c, let f, cal > 40 else { return false }
        return abs(p * 4 + c * 4 + f * 9 - cal) > max(25, cal * 0.15)
    }
    var servingWeight: (Double, String)? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(ml|mL|kg|g|L|l)\b"#),
              let match = regex.matches(in: serve, range: NSRange(serve.startIndex..., in: serve)).last,
              let numberRange = Range(match.range(at: 1), in: serve),
              let unitRange = Range(match.range(at: 2), in: serve),
              let amount = Double(serve[numberRange]), amount > 0 else { return nil }
        let unit = String(serve[unitRange]).lowercased()
        return (amount * ((unit == "kg" || unit == "l") ? 1000 : 1), unit == "g" || unit == "kg" ? "g" : "mL")
    }
    static func legacy(_ value: SavedFood) -> Food {
        Food(id: value.id.uuidString, name: value.name, kj: value.calories * 4.184, cal: value.calories,
             p: value.protein, c: value.carbs, f: value.fat, serve: value.serving)
    }
}

struct Portion: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var food: Food
    var quantity: Double = 1
    var isValid: Bool { food.isValid && quantity.isFinite && quantity > 0 && quantity <= 10000 }
}

struct Nutrition: Sendable {
    var cal = 0.0, kj = 0.0, p = 0.0, c = 0.0, f = 0.0, price = 0.0
    var missingCarbs = false, missingFat = false, missingPrice = false, fromPrice = false
    var nut: [String: Double] = [:]
    var partial: Set<String> = []
    init(_ portions: [Portion]) {
        let keys = Set(portions.flatMap { ($0.food.nut ?? [:]).keys })
        for portion in portions {
            let food = portion.food, q = portion.quantity
            cal += food.cal * q; kj += food.kj * q; p += food.p * q
            c += (food.c ?? 0) * q; f += (food.f ?? 0) * q; price += (food.price ?? 0) * q
            missingCarbs = missingCarbs || food.c == nil
            missingFat = missingFat || food.f == nil
            missingPrice = missingPrice || food.price == nil
            fromPrice = fromPrice || food.pf == true
            for key in keys {
                if let value = food.nut?[key] { nut[key, default: 0] += value * q }
                else { partial.insert(key) }
            }
        }
    }
    func value(_ key: String) -> Double { ["cal":cal,"p":p,"c":c,"f":f][key] ?? nut[key] ?? 0 }
    func isPartial(_ key: String) -> Bool { key == "c" ? missingCarbs : key == "f" ? missingFat : partial.contains(key) }
    var text: String {
        "\(cal.number) Cal (\(kj.number) kJ) · Protein \(p.number) g · Carbs \(c.number)\(missingCarbs ? "+" : "") g · Fat \(f.number)\(missingFat ? "+" : "") g"
    }
    var priceText: String {
        if price == 0 && missingPrice { return "Price unavailable" }
        return (fromPrice ? "From " : "") + price.formatted(.currency(code: "AUD")) + (missingPrice ? "+ (partial)" : "")
    }
    func food(name: String, servings: Double, ingredients: [Portion]? = nil) -> Food {
        Food(name: name, kj: kj / servings, cal: cal / servings, p: p / servings,
             c: missingCarbs ? nil : c / servings, f: missingFat ? nil : f / servings,
             nut: nut.filter { !partial.contains($0.key) }.mapValues { $0 / servings },
             price: missingPrice ? nil : price / servings, pf: fromPrice,
             ingredients: ingredients, recipeYield: ingredients == nil ? nil : servings)
    }
}

struct SavedMeal: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var items: [Portion]
    var isValid: Bool { !name.isEmpty && !items.isEmpty && items.allSatisfy(\.isValid) }
}
enum MealTime: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snacks
    var id: Self { self }
    var title: String { rawValue.capitalized }
    static func suggested(at date: Date = Date()) -> MealTime {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snacks
        }
    }
}

struct LogEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var items: [Portion]
    var time = Date()
    // Optional keeps logs and backups created before meal times readable.
    var mealTime: MealTime? = nil
    var isValid: Bool { !name.isEmpty && !items.isEmpty && items.allSatisfy(\.isValid) }
}
struct Goals: Codable, Identifiable, Sendable {
    var id = UUID()
    var name = "Every day"
    var values: [String: Double] = ["cal":2200,"p":150]
    var minimums: Set<String> = ["p", "fibre"]
    var mealCal = 500.0
    var mealProtein = 40.0
    var isValid: Bool { !name.isEmpty && values.values.allSatisfy { $0.isFinite && $0 > 0 } && mealCal.isFinite && mealCal > 0 && mealProtein.isFinite && mealProtein >= 0 }
}
struct AppData: Codable, Sendable {
    var version = 2
    var foods: [Food] = []
    var meals: [SavedMeal] = []
    var tray: [Portion] = []
    var logs: [String: [LogEntry]] = [:]
    var goalSets: [Goals] = [Goals()]
    var activeGoal: UUID?
    var dayGoals: [String: Goals] = [:]
    /// Optional so saved data and backups from before the weight log still load.
    var weights: [WeightEntry]? = nil
    var weightLog: [WeightEntry] { weights ?? [] }
    var isValid: Bool {
        version == 2 && foods.allSatisfy(\.isValid) && meals.allSatisfy(\.isValid) && tray.allSatisfy(\.isValid) &&
        logs.values.flatMap { $0 }.allSatisfy(\.isValid) && !goalSets.isEmpty && goalSets.allSatisfy(\.isValid) &&
        dayGoals.values.allSatisfy(\.isValid) && weightLog.allSatisfy(\.isValid) && Set(foods.map(\.id)).count == foods.count &&
        Set(meals.map(\.id)).count == meals.count && Set(goalSets.map(\.id)).count == goalSets.count &&
        logs.keys.allSatisfy { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
    }
}
struct MenuCatalog: Codable, Sendable { var chains: [Chain]; var foods: [Food] }

let nutrientNames: [(key: String, label: String, unit: String)] = [
    ("cal","Calories","Cal"),("p","Protein","g"),("c","Carbs","g"),("f","Fat","g"),
    ("sat","Saturated fat","g"),("trans","Trans fat","g"),("sugar","Sugars","g"),("fibre","Fibre","g"),
    ("sodium","Sodium","mg"),("potassium","Potassium","mg"),("calcium","Calcium","mg"),
    ("iron","Iron","mg"),("chol","Cholesterol","mg"),("caffeine","Caffeine","mg")]

extension Double {
    var number: String { formatted(.number.precision(.fractionLength(0...1))) }
    /// Rounded to one decimal place.
    var tenth: Double { (self * 10).rounded() / 10 }
}
func dayKey(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
func mealText(_ name: String, _ items: [Portion]) -> String {
    name + "\n" + items.map { "\($0.quantity.number) × \($0.food.name)" }.joined(separator: "\n") + "\n" + Nutrition(items).text + "\n" + Nutrition(items).priceText
}

/// Past meals to log again in one tap.
enum QuickLog {
    /// What was logged to `mealTime` the day before `date`.
    static func previous(_ mealTime: MealTime, before date: Date, logs: [String: [LogEntry]], calendar: Calendar = .current) -> [LogEntry] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return [] }
        return (logs[dayKey(yesterday)] ?? []).filter { $0.mealTime == mealTime }
    }

    /// Meals logged most often in the last `days` days, newest copy of each; ties go to the most recent.
    static func frequent(logs: [String: [LogEntry]], now: Date = Date(), days: Int = 30, limit: Int = 6, calendar: Calendar = .current) -> [LogEntry] {
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return [] }
        let startKey = dayKey(start)
        var groups: [String: (count: Int, latest: LogEntry)] = [:]
        for (day, entries) in logs where day >= startKey {
            for entry in entries where !entry.items.isEmpty {
                let key = entry.name.lowercased() + "|" + entry.items.map { "\($0.food.id)×\($0.quantity)" }.sorted().joined(separator: ",")
                let current = groups[key]
                let latest = current.map { $0.latest.time > entry.time ? $0.latest : entry } ?? entry
                groups[key] = ((current?.count ?? 0) + 1, latest)
            }
        }
        return groups.values.sorted { ($0.count, $0.latest.time) > ($1.count, $1.latest.time) }.prefix(limit).map(\.latest)
    }
}
