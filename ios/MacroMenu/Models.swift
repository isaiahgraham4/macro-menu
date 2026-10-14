import Foundation

struct Chain: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    var url: String?
    var src: String?
    var psrc: String?
    /// How the nutrition figures were collected, e.g. "Official nutrition guide".
    var how: String?
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
        // Grill'd: one bun and one patty at a time.
        if key.hasPrefix("s:bun-") { return "bun" }
        if key.hasPrefix("s:patty-") { return "patty" }
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
    /// For restaurant items: the meats and allergens in it, where the restaurant's own words say (see `DietInfo`).
    var diet: DietInfo?
    var isAnchor: Bool { chain == "mine" || cat == "main" || cat == "breakfast" }
    /// Everyday foods such as bananas and chicken breast, from USDA FoodData Central. Searchable everywhere, but not a restaurant.
    static let everyday = "generic"
    var isEveryday: Bool { chain == Food.everyday }
    /// The USDA page for an everyday food.
    var everydaySource: URL? {
        guard isEveryday, id.hasPrefix("usda-") else { return nil }
        return URL(string: "https://fdc.nal.usda.gov/food-details/\(id.dropFirst(5))/nutrients")
    }
    var isValid: Bool {
        !id.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [kj, cal, p, c, f, price].compactMap { $0 }.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (nut ?? [:]).values.allSatisfy { $0.isFinite && $0 >= 0 } &&
        (ingredients ?? []).allSatisfy(\.isValid) && (recipeYield.map { $0.isFinite && $0 > 0 } ?? true)
    }
    var mismatch: Bool {
        // Everyday foods are lab averages; beer and wine get most of their energy from alcohol, which isn't a macro.
        guard !isEveryday, let c, let f, cal > 40 else { return false }
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

extension Food {
    /// This food with modifiers applied (how many of each, by key) and optionally something else added or taken off.
    /// Energy and macros change by each part's figures, and it's renamed "Big Mac · No Big Mac Sauce".
    /// Unchanged when nothing is selected.
    func customised(_ changes: [String: Double], adding own: Food? = nil, subtract: Bool = false, name custom: String = "") -> Food {
        var result = self
        let selected = (modifiers ?? []).filter { (changes[$0.key] ?? 0) > 0 }
        var names: [String] = []
        for mod in selected {
            let q = changes[mod.key] ?? 0
            result.kj += mod.kj * q; result.p += mod.p * q
            if let c = result.c, let delta = mod.c { result.c = c + delta * q } else { result.c = nil }
            if let f = result.f, let delta = mod.f { result.f = f + delta * q } else { result.f = nil }
            for key in Array((result.nut ?? [:]).keys) {
                if let delta = mod.nut?[key] { result.nut?[key, default: 0] += delta * q }
                // Estimated removals leave other nutrients as listed rather than hiding them.
                else if mod.est != true { result.nut?.removeValue(forKey: key) }
            }
            if let price = result.price, let delta = mod.price { result.price = max(0, price + delta * q) } else { result.price = nil }
            names.append("\(q > 1 ? q.number + " × " : "")\(mod.name)")
        }
        if let ownAdjustment = own {
            let sign = subtract ? -1.0 : 1.0
            result.kj += ownAdjustment.kj * sign; result.p += ownAdjustment.p * sign
            if let c = result.c, let delta = ownAdjustment.c { result.c = c + delta * sign } else { result.c = nil }
            if let f = result.f, let delta = ownAdjustment.f { result.f = f + delta * sign } else { result.f = nil }
            for key in Array((result.nut ?? [:]).keys) {
                if let delta = ownAdjustment.nut?[key] { result.nut?[key, default: 0] += delta * sign }
                else { result.nut?.removeValue(forKey: key) }
            }
            if let price = result.price, let delta = ownAdjustment.price { result.price = max(0,price + delta * sign) } else { result.price = nil }
            names.append((subtract ? "Without " : "Extra ") + ownAdjustment.name)
        }
        if !names.isEmpty {
            result.kj = max(0,result.kj); result.cal = (result.kj / 4.184).rounded(); result.p = max(0,result.p)
            result.c = result.c.map { max(0,$0) }; result.f = result.f.map { max(0,$0) }
            result.nut = result.nut?.mapValues { max(0,$0) }
            result.name = custom.isEmpty ? name + " · " + names.joined(separator: ", ") : custom
            result.note = "Based on \(name). " + names.joined(separator: ", ")
            result.modifiers = nil
        }
        return result
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
    /// By the clock, using the same hours as the Log again widget.
    static func suggested(at date: Date = Date()) -> MealTime { MealTime(rawValue: MealSlot.at(date)) ?? .snacks }
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
    /// The weight being aimed for. Optional so saved data and backups from before goals still load.
    var weightGoal: WeightGoal? = nil
    /// Tape measurements. Optional so saved data and backups from before measurements still load.
    var measurements: [BodyMeasurement]? = nil
    var measurementLog: [BodyMeasurement] { measurements ?? [] }
    /// Millilitres of water by day, with the daily target and glass size (see `Water`). All optional for the same reason.
    var water: [String: Double]? = nil
    var waterTarget: Double? = nil
    var waterGlass: Double? = nil
    /// The daily step goal (see `Steps`). The step counts themselves stay in Apple Health.
    var stepGoal: Double? = nil
    /// Weekly check-ins and the pace they aim for (see `CheckIn`). Optional so saved data and backups from before check-ins still load.
    var checkIns: [CheckInRecord]? = nil
    var checkInPace: Double? = nil
    /// Meals planned ahead, by day (see `MealPlan`). They count towards nothing until they're logged.
    var plans: [String: [LogEntry]]? = nil
    /// Foods pinned to the top of the "+" menu and the Log again widget. Copies, so a pin still works if the item leaves the menu.
    /// Optional so saved data and backups from before pinning still load.
    var pinned: [Food]? = nil
    var isValid: Bool {
        guard version == 2, !goalSets.isEmpty else { return false }
        let contents = foods.allSatisfy(\.isValid) && meals.allSatisfy(\.isValid) && tray.allSatisfy(\.isValid) && (pinned ?? []).allSatisfy(\.isValid)
        let history = logs.values.flatMap { $0 }.allSatisfy(\.isValid)
            && logs.keys.allSatisfy { $0.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
        let targets = goalSets.allSatisfy(\.isValid) && dayGoals.values.allSatisfy(\.isValid)
        let body = weightLog.allSatisfy(\.isValid) && (weightGoal?.isValid ?? true)
            && measurementLog.allSatisfy(\.isValid) && Water.isValid(self) && Steps.isValid(self)
        let ahead = CheckIn.isValid(self) && MealPlan.isValid(self)
        let unique = Set(foods.map(\.id)).count == foods.count && Set(meals.map(\.id)).count == meals.count
            && Set(goalSets.map(\.id)).count == goalSets.count && Set(measurementLog.map(\.id)).count == measurementLog.count
        return contents && history && targets && body && ahead && unique
    }
}
struct MenuCatalog: Codable, Sendable {
    /// Which layout this file uses, a fingerprint of its contents, and when it was published (ISO 8601).
    /// Optional so older menu files still load.
    var format: Int?
    var revision: String?
    var published: String?
    var chains: [Chain]
    var foods: [Food]
    init(format: Int? = nil, revision: String? = nil, published: String? = nil, chains: [Chain], foods: [Food]) {
        self.format = format; self.revision = revision; self.published = published; self.chains = chains; self.foods = foods
    }
}

let nutrientNames: [(key: String, label: String, unit: String)] = [
    ("cal","Calories","Cal"),("p","Protein","g"),("c","Carbs","g"),("f","Fat","g"),
    ("sat","Saturated fat","g"),("trans","Trans fat","g"),("sugar","Sugars","g"),("fibre","Fibre","g"),
    ("sodium","Sodium","mg"),("potassium","Potassium","mg"),("calcium","Calcium","mg"),
    ("iron","Iron","mg"),("chol","Cholesterol","mg"),("caffeine","Caffeine","mg")]

extension Double {
    var number: String { formatted(.number.precision(.fractionLength(0...1))) }
    /// Rounded to one decimal place.
    var tenth: Double { (self * 10).rounded() / 10 }
    /// Rounded to two decimal places, for body weight from scales that read to 10 g.
    var hundredth: Double { (self * 100).rounded() / 100 }
    /// A weight in kg as typed: up to two decimal places, no trailing zeros ("81.75", "82.4", "82").
    var kgText: String { formatted(.number.precision(.fractionLength(0...2))) }
}
func dayKey(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}
func mealText(_ name: String, _ items: [Portion]) -> String {
    name + "\n" + items.map { "\($0.quantity.number) × \($0.food.name)" }.joined(separator: "\n") + "\n" + Nutrition(items).text
}

/// Past meals to log again in one tap.
enum QuickLog {
    /// Copies of logged items with new IDs, so a new entry is independent of the old one.
    static func copies(_ items: [Portion]) -> [Portion] { items.map { var copy = $0; copy.id = UUID(); return copy } }

    /// What was logged to `mealTime` the day before `date`.
    static func previous(_ mealTime: MealTime, before date: Date, logs: [String: [LogEntry]], calendar: Calendar = .current) -> [LogEntry] {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return [] }
        return (logs[dayKey(yesterday)] ?? []).filter { $0.mealTime == mealTime }
    }

    /// How many servings of a food were logged most recently, if it's been logged at all.
    static func lastQuantity(of foodID: String, logs: [String: [LogEntry]]) -> Double? {
        for day in logs.keys.sorted(by: >) {
            for entry in (logs[day] ?? []).sorted(by: { $0.time > $1.time }) {
                if let item = entry.items.first(where: { $0.food.id == foodID }) { return item.quantity }
            }
        }
        return nil
    }

    /// Foods logged in the last `days` days, newest first, each listed once.
    static func recentFoods(logs: [String: [LogEntry]], now: Date = Date(), days: Int = 30, limit: Int = 8, calendar: Calendar = .current) -> [Food] {
        guard let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) else { return [] }
        let startKey = dayKey(start)
        var seen = Set<String>(), foods: [Food] = []
        for day in logs.keys.filter({ $0 >= startKey }).sorted(by: >) {
            for entry in (logs[day] ?? []).sorted(by: { $0.time > $1.time }) {
                for item in entry.items where seen.insert(item.food.chain + "|" + item.food.name.lowercased()).inserted {
                    foods.append(item.food)
                    if foods.count == limit { return foods }
                }
            }
        }
        return foods
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
