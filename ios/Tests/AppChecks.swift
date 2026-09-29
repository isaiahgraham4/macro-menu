import Foundation

@main struct AppChecks {
    @MainActor static func main() throws {
        try barcodeChecks()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try JSONDecoder().decode(MenuCatalog.self,from: Data(contentsOf: catalogURL))
        assert(catalog.foods.count == 1026)
        assert(catalog.foods.allSatisfy(\.isValid))
        assert(Set(catalog.foods.map(\.id)).count == catalog.foods.count)
        assert(catalog.foods.contains { !($0.modifiers ?? []).isEmpty })
        let original = Food(id: "original", chain: "kfc", name: "Burger", kj: 2500, cal: 600, p: 30)
        let retained = Food(id: "retained", chain: "kfc", name: "Alternative", kj: 2000, cal: 480, p: 26)
        var lowProtein = retained; lowProtein.id = "low"; lowProtein.cal = 300; lowProtein.p = 10
        var otherChain = retained; otherChain.id = "other"; otherChain.chain = "mcd"
        var side = retained; side.id = "side"; side.cat = "side"
        var invalid = retained; invalid.id = "invalid"; invalid.cal = .nan
        let swapFoods = [original, lowProtein, otherChain, side, invalid, retained]
        assert(MealSwaps.options(for: Portion(food: original, quantity: 2), foods: swapFoods).map(\.id) == ["retained", "low"])
        assert(MealSwaps.options(for: Portion(food: original, quantity: 0), foods: swapFoods).isEmpty)
        assert(MealSwaps.options(for: Portion(food: original, quantity: 0.01), foods: swapFoods).isEmpty)
        // Widgets mirror today's active target and logged portions, never the unlogged tray.
        let widgetNow = Date()
        var widgetState = AppData()
        widgetState.tray = [Portion(food: original, quantity: 10)]
        widgetState.logs[dayKey(widgetNow)] = [LogEntry(name: "Lunch", items: [Portion(food: original, quantity: 2)])]
        widgetState.dayGoals[dayKey(widgetNow)] = Goals(values: ["cal": 999])
        assert(widgetState.widgetCalories.eaten(on: widgetNow) == 1200)
        assert(widgetState.widgetCalories.remaining(on: widgetNow) == 1000)
        let alternateGoal = Goals(values: ["cal": 1000])
        widgetState.goalSets.append(alternateGoal); widgetState.activeGoal = alternateGoal.id
        assert(widgetState.widgetCalories.remaining(on: widgetNow) == -200)
        // The medium macro widget keeps actual intake even without macro goals.
        assert(widgetState.widgetCalories.nutrientTargets?.isEmpty == true)
        assert(widgetState.widgetCalories.dailyNutrients?[dayKey(widgetNow)]?["p"] == 60)
        widgetState.goalSets[1].values.removeValue(forKey: "cal")
        assert(widgetState.widgetCalories.remaining(on: widgetNow) == nil)
        widgetState.logs.removeAll()
        assert(widgetState.widgetCalories.eaten(on: widgetNow) == 0)
        assert(!WidgetCalories(target: 0, dailyCalories: [:]).isValid)
        assert(!WidgetCalories(target: 2200, dailyCalories: ["bad": .infinity]).isValid)
        var melbourne = Calendar(identifier: .gregorian)
        melbourne.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let beforeDST = melbourne.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 0, minute: 30))!
        let dates = WidgetCalories.timelineDates(from: beforeDST, calendar: melbourne)
        assert(dates.count == 8 && dates[0] == beforeDST)
        assert(dates[1].timeIntervalSince(melbourne.startOfDay(for: beforeDST)) == 23 * 3600)
        // Streaks cross DST and month boundaries, preserve yesterday until today ends,
        // and depend on logging rather than calorie targets.
        let streakDays: Set<String> = ["2026-09-30", "2026-10-01", "2026-10-02", "2026-10-03"]
        assert(TrackingStreak.count(days: streakDays, on: beforeDST, calendar: melbourne) == 4)
        assert(TrackingStreak.count(days: streakDays.union(["2026-10-04"]), on: beforeDST, calendar: melbourne) == 5)
        assert(TrackingStreak.count(days: streakDays.subtracting(["2026-10-02"]), on: beforeDST, calendar: melbourne) == 1)
        assert(TrackingStreak.count(days: streakDays, on: dates[1], calendar: melbourne) == 0)
        assert(TrackingStreak.count(days: ["2026-10-05"], on: beforeDST, calendar: melbourne) == 0)
        var trackedState = AppData()
        trackedState.logs["2026-10-03"] = [LogEntry(name: "Meal", items: [Portion(food: original, quantity: 10)])]
        trackedState.logs["2026-10-04"] = []
        assert(trackedState.widgetCalories.streak(on: beforeDST, calendar: melbourne) == 1)
        trackedState.logs["2026-10-03"] = []
        assert(trackedState.widgetCalories.streak(on: beforeDST, calendar: melbourne) == 0)
        assert(dates.dropFirst().allSatisfy { melbourne.component(.hour, from: $0) == 0 })
        let dated = WidgetCalories(target: 2200, dailyCalories: [WidgetCalories.dayKey(beforeDST, timeZone: melbourne.timeZone): 1200])
        assert(dated.remaining(on: dates[1], timeZone: melbourne.timeZone) == 2200)
        let widgetRoundTrip = try JSONDecoder().decode(WidgetCalories.self, from: JSONEncoder().encode(dated))
        assert(widgetRoundTrip == dated)
        let oldWidget = try JSONDecoder().decode(WidgetCalories.self, from: Data(#"{"target":2200,"dailyCalories":{}}"#.utf8))
        assert(oldWidget.selectedAccent == .green)
        for accent in AppAccent.allCases {
            var coloured = oldWidget; coloured.accent = accent.rawValue
            let decoded = try JSONDecoder().decode(WidgetCalories.self, from: JSONEncoder().encode(coloured))
            assert(decoded.selectedAccent == accent && decoded != oldWidget)
        }
        var unknownAccent = oldWidget; unknownAccent.accent = "unrecognised"
        assert(unknownAccent.selectedAccent == .standard)
        let legacyURL = root.appending(path: "foods.json")
        let oldFood = SavedFood(name: "Existing breakfast", calories: 300, protein: 20, carbs: 30, fat: 8)
        let oldBytes = try FoodBackup(foods: [oldFood]).encoded()
        try oldBytes.write(to: legacyURL)
        let url = root.appending(path: "state.json")
        let store = AppStore(url: url,catalogURL: catalogURL,legacyURL: legacyURL)
        let estimatedURL = root.appending(path: "estimated-targets.json")
        let estimatedStore = AppStore(url: estimatedURL, catalogURL: catalogURL, legacyURL: nil)
        let estimatedID = estimatedStore.goals.id
        let estimate = ["cal": 2400.0, "p": 140.0, "c": 300.0, "f": 70.0]
        assert(estimatedStore.applyEstimatedTargets(estimate))
        assert(estimatedStore.goals.id == estimatedID && estimatedStore.goals.values == estimate)
        assert(estimatedStore.data.dayGoals[dayKey(Date())]?.values == estimate)
        let estimatedReloaded = AppStore(url: estimatedURL, catalogURL: catalogURL, legacyURL: nil)
        assert(estimatedReloaded.goals.values == estimate)
        assert(estimatedReloaded.data.widgetCalories.target == 2400)
        assert(store.loadError == nil && store.data.foods.count == 1)
        assert(store.data.foods[0].id == oldFood.id.uuidString)
        let unchangedLegacy = try Data(contentsOf: legacyURL)
        assert(unchangedLegacy == oldBytes)
        let oats = Food(name: "Oats",kj: 800,cal: 200,p: 10,c: 25,f: 5,serve: "100 g",nut: ["fibre":8],price: 2)
        let mealTimesURL = root.appending(path: "meal-times.json")
        let mealTimesStore = AppStore(url: mealTimesURL, catalogURL: catalogURL, legacyURL: nil)
        let mealDate = Date()
        let mealDay = dayKey(mealDate)
        for mealTime in MealTime.allCases {
            assert(mealTimesStore.log([Portion(food: oats, quantity: 2)], name: mealTime.title, date: mealDate, mealTime: mealTime))
        }
        let mealReloaded = AppStore(url: mealTimesURL, catalogURL: catalogURL, legacyURL: nil)
        assert(mealReloaded.data.logs[mealDay]?.compactMap(\.mealTime) == MealTime.allCases)
        let beforeReassignment = mealReloaded.data.widgetCalories
        assert(mealReloaded.change { $0.logs[mealDay]?[0].mealTime = .snacks })
        assert(mealReloaded.data.widgetCalories == beforeReassignment)
        let mealBackup = try mealReloaded.decodeBackup(mealReloaded.export())
        assert(mealBackup.logs[mealDay]?.first?.mealTime == .snacks)
        // Backups from older app versions have no mealTime field.
        let oldEntry = LogEntry(name: "Old breakfast", items: [Portion(food: oats)])
        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldEntry)) as! [String: Any]
        oldJSON.removeValue(forKey: "mealTime")
        let oldDecoded = try JSONDecoder().decode(LogEntry.self, from: JSONSerialization.data(withJSONObject: oldJSON))
        assert(oldDecoded.id == oldEntry.id && oldDecoded.mealTime == nil && oldDecoded.items == oldEntry.items)
        let missing = Food(name: "Partial data",kj: 400,cal: 100,p: 20,c: nil,f: nil)
        let items = [Portion(food: oats,quantity: 1.5),Portion(food: missing)]
        let nutrition = Nutrition(items)
        assert(nutrition.cal == 400 && nutrition.p == 35)
        assert(nutrition.missingCarbs && nutrition.missingPrice && nutrition.partial.contains("fibre"))
        var macroWidgetState = AppData()
        macroWidgetState.goalSets[0].values = ["cal": 2200, "p": 150, "c": 250, "f": 70, "fibre": 30, "sodium": 2300]
        macroWidgetState.logs[dayKey(Date())] = [LogEntry(name: "Test meal", items: items)]
        let macroSnapshot = macroWidgetState.widgetCalories
        assert(macroSnapshot.nutrientTargets?.map(\.id) == ["p", "c", "f", "fibre", "sodium"])
        assert(macroSnapshot.dailyNutrients?[dayKey(Date())]?["p"] == 35)
        assert(Set(macroSnapshot.dailyPartialNutrients?[dayKey(Date())] ?? []) == Set(["c", "f", "fibre", "sodium"]))
        assert(macroSnapshot.isValid)
        var premiumSnapshot = macroSnapshot; premiumSnapshot.premiumUnlocked = true
        let decodedPremium = try JSONDecoder().decode(WidgetCalories.self, from: JSONEncoder().encode(premiumSnapshot))
        assert(decodedPremium == premiumSnapshot && decodedPremium.premiumUnlocked == true)
        macroWidgetState.goalSets[0].values.removeValue(forKey: "fibre")
        assert(macroWidgetState.widgetCalories.nutrientTargets?.contains { $0.id == "fibre" } == false)
        let recipe = nutrition.food(name: "Recipe",servings: 2,ingredients: items)
        assert(recipe.cal == 200 && recipe.c == nil && recipe.nut?["fibre"] == nil)
        assert(oats.servingWeight?.0 == 100)
        assert(store.saveFood(recipe))
        store.add(items)
        assert(store.data.tray.count == 2)
        let yesterday = Calendar.current.date(byAdding: .day,value: -1,to: Date())!
        assert(store.log(items,name: "Lunch",date: yesterday))
        let originalTarget = store.data.dayGoals[dayKey(yesterday)]!.values["cal"]
        store.change { $0.goalSets[0].values["cal"] = 2400 }
        assert(store.data.dayGoals[dayKey(yesterday)]!.values["cal"] == originalTarget)
        let backup = try store.decodeBackup(store.export())
        assert(store.log(store.data.tray,name: "Atomic meal",date: Date(),clearTray: true))
        assert(store.data.tray.isEmpty && store.data.logs[dayKey(Date())]?.count == 1)
        let second = AppStore(url: root.appending(path: "second.json"),catalogURL: catalogURL,legacyURL: nil)
        assert(second.merge(backup)); assert(second.merge(backup))
        assert(second.data.foods.count == 2 && second.data.logs[dayKey(yesterday)]?.count == 1)
        let reloaded = AppStore(url: root.appending(path: "second.json"),catalogURL: catalogURL,legacyURL: nil)
        assert(reloaded.data.tray.count == 2 && reloaded.data.foods.count == 2)
        var bad = oats; bad.cal = -1
        assert(!second.saveFood(bad))
        let corrupt = Data("broken".utf8); try corrupt.write(to: url)
        let broken = AppStore(url: url,catalogURL: catalogURL,legacyURL: nil)
        assert(broken.loadError != nil && !broken.saveFood(oats))
        let preserved = try Data(contentsOf: url); assert(preserved == corrupt)
        let web = Data(#"{"app":"macro-menu","v":1,"foods":[{"id":"web1","name":"Toast","cal":100,"p":5,"c":15,"f":2,"other":[{"name":"Vitamin C","amt":5,"unit":"mg"}]}],"meals":[{"id":"m1","name":"Breakfast","items":[{"id":"web1","qty":2}]}],"goalSets":[{"id":"g1","name":"Training","goals":{"cal":2500,"p":180}}]}"#.utf8)
        let imported = try second.decodeBackup(web)
        assert(imported.foods[0].nut?["Vitamin C (mg)"] == 5 && imported.meals[0].items[0].quantity == 2)
        assert(second.merge(imported)); assert(second.merge(imported))
        assert(second.data.meals.count == 1)
        let label = "Energy 840 kJ 1680 kJ\nProtein 10 g 20 g\nTotal Fat 5 g 10 g\nSaturated fat 1 g 2 g\nSodium 100 mg 200 mg\nSugars <1 g"
        let suggestions = LabelParser.suggestions(label,column: 1)
        assert(suggestions["p"] == 20 && suggestions["f"] == 10 && suggestions["sat"] == 2 && suggestions["sodium"] == 200 && suggestions["sugar"] == nil)
        assert(abs(suggestions["cal"]! - 1680 / 4.184) < 0.01)
        let scan = LabelParser.suggestions("Energy (kJ) 1,200 2,400\nTotal carbohydrate 12g 4% 24g 8%\nDietary fibre 2g 4g\n– Saturated fat 1g 2g", column: 1)
        assert(abs(scan["cal"]! - 2400 / 4.184) < 0.01)
        assert(scan["c"] == 24 && scan["fibre"] == 4 && scan["sat"] == 2)
        assert(abs(LabelParser.suggestions("Energy 836.8 kJ", column: 0)["cal"]! - 200) < 0.01)
        assert(LabelParser.suggestions("Calories 205\nEnergy 836.8 kJ", column: 0)["cal"] == 205)
        assert(LabelParser.suggestions("Energy 836.8 kJ\nCalories 205", column: 0)["cal"] == 205)
        assert(abs(LabelParser.suggestions("Kilojoules 836.8 1673.6", column: 1)["cal"]! - 400) < 0.01)
        assert(abs(LabelParser.suggestions("836.8 kJ 1673.6 kJ", column: 0)["cal"]! - 200) < 0.01)
        assert(abs(LabelParser.suggestions("Energy (kJ)\n836.8 1673.6", column: 1)["cal"]! - 400) < 0.01)
        assert(abs(LabelParser.suggestions("Energy 836.8 k J", column: 0)["cal"]! - 200) < 0.01)
        var query = FindQuery(); query.calories = 700; query.protein = 35; query.budget = 20; query.maxItems = 3
        let start = Date()
        let matches = MealFinder.find(catalog.foods,query: query)
        assert(!matches.isEmpty)
        for match in matches {
            assert(match.items.count <= 3 && match.total.cal <= 700 && match.total.price <= 20 && !match.total.missingPrice)
            assert(Set(match.items.map { $0.food.chain }).count == 1)
        }
        query.chains = ["spud"]; query.carbs = 100
        assert(MealFinder.find(catalog.foods,query: query).isEmpty)
        let tiny = [Food(id:"main",chain:"test",name:"Main",kj: 800,cal: 200,p: 20,c: 10,f: 5,price: 5),Food(id:"side",chain:"test",name:"Side",cat:"side",kj:400,cal:100,p:5,c:10,f:3,price:2)]
        query = FindQuery(); query.calories = 300; query.protein = 25; query.maxItems = 2
        let simple = MealFinder.find(tiny,query: query)
        assert(simple.first?.total.cal == 300 && simple.first?.total.p == 25)
        // Weight trend, maintenance and quick re-log.
        let calendar = Calendar(identifier: .gregorian)
        let day0 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1, hour: 8))!
        func day(_ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: day0)! }
        let flat = WeightTrend.points((0..<10).map { WeightEntry(date: day($0), kg: 80) }, calendar: calendar)
        assert(flat.count == 10 && flat.allSatisfy { abs($0.trend - 80) < 0.0001 })
        let jump = WeightTrend.points([WeightEntry(date: day(0), kg: 80), WeightEntry(date: day(1), kg: 82)], calendar: calendar)
        assert(abs(jump[1].trend - 80.2) < 0.0001)
        let gap = WeightTrend.points([WeightEntry(date: day(0), kg: 80), WeightEntry(date: day(3), kg: 82)], calendar: calendar)
        assert(abs(gap[1].trend - (80 + 2 * (1 - pow(0.9, 3)))) < 0.0001)
        let sameDay = WeightTrend.points([WeightEntry(date: day(0), kg: 80), WeightEntry(date: day(0).addingTimeInterval(3600), kg: 81)], calendar: calendar)
        assert(sameDay.count == 1 && sameDay[0].kg == 81)
        assert(WeightTrend.points([WeightEntry(date: day(0), kg: 5)], calendar: calendar).isEmpty)
        // Losing 0.1 kg a day while eating 2,000 Cal means maintenance is about 2,000 + 770.
        let losing = WeightTrend.points((0..<60).map { WeightEntry(date: day($0), kg: 90 - Double($0) * 0.1) }, calendar: calendar)
        assert(abs(WeightTrend.weeklyChange(losing, now: day(60), calendar: calendar)! + 0.7) < 0.05)
        let steadyFood = Food(id: "steady", name: "Steady", kj: 2000 * 4.184, cal: 2000, p: 100, c: 200, f: 70)
        var dietLogs: [String: [LogEntry]] = [:]
        for n in 30..<60 { dietLogs[dayKey(day(n))] = [LogEntry(name: "Day", items: [Portion(food: steadyFood)], time: day(n))] }
        let maintenance = WeightTrend.maintenance(logs: dietLogs, points: losing, now: day(60), calendar: calendar)!
        assert(abs(maintenance.calories - 2770) < 60 && maintenance.loggedDays == 28)
        assert(WeightTrend.maintenance(logs: [:], points: losing, now: day(60), calendar: calendar) == nil)
        let lunch = LogEntry(name: "Wrap", items: [Portion(food: steadyFood)], time: day(1), mealTime: .lunch)
        let quickLogs = [dayKey(day(1)): [lunch, LogEntry(name: "Toast", items: [Portion(food: steadyFood)], time: day(1), mealTime: .breakfast)],
                         dayKey(day(2)): [LogEntry(name: "Wrap", items: [Portion(food: steadyFood)], time: day(2), mealTime: .lunch)]]
        assert(QuickLog.previous(.lunch, before: day(2), logs: quickLogs, calendar: calendar).map(\.name) == ["Wrap"])
        assert(QuickLog.previous(.dinner, before: day(2), logs: quickLogs, calendar: calendar).isEmpty)
        let frequent = QuickLog.frequent(logs: quickLogs, now: day(3), calendar: calendar)
        assert(frequent.map(\.name) == ["Wrap", "Toast"] && frequent[0].time == day(2))

        // Forgiving search.
        assert(FoodSearch.score("McChicken", query: "mchicken") != nil)
        assert(FoodSearch.score("McChicken", query: "mc chicken") == 0)
        assert(FoodSearch.score("Chicken Nuggets 10 pack", query: "nugets") != nil)
        assert(FoodSearch.score("Big Mac", query: "whopper") == nil)
        assert(FoodSearch.score("Hungry Jack’s Whopper", query: "hungry jacks") == 0)
        assert(FoodSearch.score("Fries", query: "frz") == nil)
        let found = FoodSearch.filter(["Double McChicken", "McChicken", "Big Mac"], query: "mcchicken") { $0 }
        assert(found == ["Double McChicken", "McChicken"])
        let typo = FoodSearch.filter(["Big Mac", "McChicken"], query: "mchiken") { $0 }
        assert(typo == ["McChicken"])
        assert(FoodSearch.score("Chicken McWings 3 pc", query: "mchiken") == nil)
        assert(RecentSearches.list(RecentSearches.adding("Wrap", to: RecentSearches.adding("wrap", to: "fries"))) == ["Wrap", "fries"])
        // The quick typo check stops early but must agree with a full edit distance against the word and the candidate's starts.
        func editDistance(_ a: [Int], _ b: [Int]) -> Int {
            var row = Array(0...b.count)
            for i in a.indices {
                var previous = row[0]; row[0] = i + 1
                for j in b.indices {
                    let current = row[j + 1]
                    row[j + 1] = a[i] == b[j] ? previous : min(previous, row[j + 1], row[j]) + 1
                    previous = current
                }
            }
            return row[b.count]
        }
        struct SplitMix: RandomNumberGenerator {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E3779B97F4A7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
                return z ^ (z >> 31)
            }
        }
        var generator = SplitMix(state: 42)
        func randomWord() -> [Int] { (0..<Int.random(in: 1...9, using: &generator)).map { _ in Int.random(in: 97...100, using: &generator) } }
        for _ in 0..<3000 {
            let word = randomWord(), candidate = randomWord(), limit = Int.random(in: 0...2, using: &generator)
            let lengths = (max(1, word.count - 1)...(word.count + 1)).map { min($0, candidate.count) } + [candidate.count]
            let expected = lengths.map { editDistance(word, Array(candidate.prefix($0))) }.min()!
            assert(FoodSearch.closeness(word, candidate, limit: limit) == (expected <= limit ? expected : nil))
        }
        // Characters, not code units: an emoji is one letter.
        assert(FoodSearch.letters("b🍔rger").count == 6 && FoodSearch.letters("é").count == 1)
        // Best choices: a renamed food is found by its new name, and "Protein per dollar" leaves out unpriced foods.
        var renamed = Food(id: "mine-1", name: "Protein shake", kj: 800, cal: 190, p: 30, price: 4)
        let unpriced = Food(id: "mine-2", name: "Protein bar", kj: 800, cal: 190, p: 20)
        assert(FoodSearch.browse([renamed, unpriced], chainNames: [:], request: .init(search: "shake")).map(\.id) == ["mine-1"])
        renamed.name = "Whey drink"
        assert(FoodSearch.browse([renamed, unpriced], chainNames: [:], request: .init(search: "shake")).isEmpty)
        assert(FoodSearch.browse([renamed, unpriced], chainNames: [:], request: .init(search: "whey")).map(\.id) == ["mine-1"])
        assert(FoodSearch.browse([renamed, unpriced], chainNames: [:], request: .init(sort: "value")).map(\.id) == ["mine-1"])
        assert(FoodSearch.browse([renamed, unpriced], chainNames: [:], request: .init(sort: "protein")).map(\.id) == ["mine-1", "mine-2"])

        // Undo and merging weights.
        let undoURL = root.appending(path: "undo.json")
        let undoStore = AppStore(url: undoURL, catalogURL: catalogURL, legacyURL: nil)
        assert(undoStore.log([Portion(food: steadyFood)], name: "Snack", date: day0))
        assert(undoStore.undo?.label == "Logged Snack")
        undoStore.undoLast()
        assert(undoStore.data.logs[dayKey(day0)]?.isEmpty ?? true && undoStore.undo == nil)
        assert(AppStore(url: undoURL, catalogURL: catalogURL, legacyURL: nil).data.logs[dayKey(day0)]?.isEmpty ?? true)
        assert(undoStore.change { $0.weights = [WeightEntry(date: day0, kg: 80)] } && undoStore.undo == nil)
        var other = AppData(); other.weights = [WeightEntry(date: day(1), kg: 79)]
        assert(AppStore.merged(undoStore.data, other).weightLog.count == 2)
        let oldFormat = try JSONEncoder().encode(AppData())
        let reloadedOld = try JSONDecoder().decode(AppData.self, from: oldFormat)
        assert(reloadedOld.weights == nil && reloadedOld.isValid)

        print("App checks passed: catalogue, migration, persistence, backups, recipes, history, label parsing, finder, weight trend, quick log, search and undo (\(Date().timeIntervalSince(start).formatted())s).")
    }
}
