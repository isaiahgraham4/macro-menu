import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct AppChecks {
    @MainActor static func main() throws {
        try barcodeChecks()
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let catalog = try JSONDecoder().decode(MenuCatalog.self,from: Data(contentsOf: catalogURL))
        assert(catalog.foods.count == 1307)
        assert(Set(catalog.foods.map(\.chain)).isSubset(of: Set(catalog.chains.map(\.id))))
        // A juice bar has no mains, so its drinks are the order.
        let juice = MealFinder.find(catalog.foods, query: FindQuery(chains: ["boost"], calories: 700, protein: 25, maxItems: 1))
        assert(!juice.isEmpty && juice.allSatisfy { $0.chain == "boost" && $0.total.cal <= 700 } && juice[0].total.p >= 20)
        let burrito = MealFinder.find(catalog.foods, query: FindQuery(chains: ["zam"], calories: 900, protein: 40, maxItems: 2))
        assert(!burrito.isEmpty && burrito.allSatisfy { $0.items[0].food.cat == "main" })
        assert(catalog.foods.allSatisfy(\.isValid))
        assert(Set(catalog.foods.map(\.id)).count == catalog.foods.count)
        assert(catalog.foods.contains { !($0.modifiers ?? []).isEmpty })
        // Adding a patty or taking off a sauce: McDonald's from its ingredient energy, Hungry Jack's and KFC from pairs of burgers.
        func mod(_ food: String, _ name: String) -> Modifier? { catalog.foods.first { $0.id == food }?.modifiers?.first { $0.name == name } }
        assert(mod("mcd:big-mac", "Extra Beef Patty")?.kj == 446 && mod("mcd:big-mac", "Extra Beef Patty")?.est == true)
        assert(mod("mcd:big-mac", "No Big Mac Sauce")?.kj == -376 && mod("mcd:big-mac", "No Big Mac Sauce")?.est == nil)
        assert(mod("mcd:nashville-mccrispy", "Add Cheese") != nil && mod("mcd:bacon-egg-mcmuffin", "Add Bacon") == nil)
        assert(mod("hj:whopper", "Extra Whopper Patty")?.kj == 1106 && mod("hj:whopper", "Extra Whopper Patty")?.kind == "f")
        assert(mod("kfc:zinger-burger", "Add Bacon & Cheese")?.kj == 424 && mod("kfc:zinger-bacon-cheese-burger", "No Bacon & Cheese")?.kj == -424)
        assert(catalog.foods.flatMap { $0.modifiers ?? [] }.allSatisfy { [$0.kj, $0.p, $0.c ?? 0, $0.f ?? 0].allSatisfy(\.isFinite) })
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
        // A zero read as the letter O still counts as a column, so the next value isn't taken for it.
        let misread = LabelParser.suggestions("Trans fat Og 0.1g\nProtein O.5g 2g\nSodium 5mg Omg", column: 0)
        assert(misread["trans"] == 0 && misread["p"] == 0.5 && misread["sodium"] == 5)
        assert(LabelParser.suggestions("Sodium 5mg Omg\nProtein 3 g 6 g", column: 1) == ["sodium": 0, "p": 6])
        // Per-100 figures with a serving size on the label are converted to that serving.
        let perHundred = "Serving size: 30g\nAvg qty per 100g\nEnergy 1500 kJ\nProtein 10g\nFat, total 20g"
        let converted = LabelParser.servingSuggestions(perHundred, column: 0)
        assert(converted["p"] == 3 && converted["f"] == 6 && abs(converted["cal"]! - 450 / 4.184) < 0.01)
        // Prices are off for now, so the bundled menu has none.
        assert(catalog.foods.allSatisfy { $0.price == nil && $0.pf == nil && ($0.modifiers ?? []).allSatisfy { $0.price == nil } })
        assert(catalog.chains.allSatisfy { $0.psrc == nil })
        var query = FindQuery(); query.calories = 700; query.protein = 35; query.maxItems = 3
        let start = Date()
        let matches = MealFinder.find(catalog.foods,query: query)
        assert(!matches.isEmpty)
        for match in matches {
            assert(match.items.count <= 3 && match.total.cal <= 700)
            assert(Set(match.items.map { $0.food.chain }).count == 1)
        }
        query.chains = ["spud"]; query.carbs = 100
        assert(MealFinder.find(catalog.foods,query: query).isEmpty)
        let tiny = [Food(id:"main",chain:"test",name:"Main",kj: 800,cal: 200,p: 20,c: 10,f: 5,price: 5),Food(id:"side",chain:"test",name:"Side",cat:"side",kj:400,cal:100,p:5,c:10,f:3,price:2)]
        query = FindQuery(); query.calories = 300; query.protein = 25; query.maxItems = 2
        let simple = MealFinder.find(tiny,query: query)
        assert(simple.first?.total.cal == 300 && simple.first?.total.p == 25)
        print("Finder with customising: \(Date().timeIntervalSince(start).formatted())s")

        // Customised orders: sauce and cheese come off, another patty goes on, the bun and meat always stay.
        let bigMac = catalog.foods.first { $0.id == "mcd:big-mac" }!
        let custom = MealFinder.variants(of: bigMac)
        let changes = custom.map { $0.name.replacingOccurrences(of: "Big Mac · ", with: "") }
        assert(changes.contains("No Big Mac Sauce") && changes.contains("Extra Beef Patty") && changes.contains("No Big Mac Sauce, Extra Beef Patty"))
        assert(!changes.contains { $0.contains("Bun") || $0.contains("No Beef") || $0.contains("Lettuce") || $0.contains("Pickles") })
        assert(custom.allSatisfy { MealFinder.isVariant($0) && MealFinder.baseID($0) == "mcd:big-mac" && $0.modifiers == nil && $0.isValid })
        let noSauce = custom.first { $0.name == "Big Mac · No Big Mac Sauce" }!
        assert(abs(noSauce.kj - (bigMac.kj - 376)) < 0.01 && noSauce.cal == ((bigMac.kj - 376) / 4.184).rounded() && noSauce.note == "Based on Big Mac. No Big Mac Sauce")
        assert(Set(custom.map(\.id)).count == custom.count && MealFinder.variants(of: tiny[0]).isEmpty)
        // Nothing an item is named after comes off it.
        for id in ["mcd:cheeseburger", "mcd:bacon-egg-mcmuffin"] {
            if let item = catalog.foods.first(where: { $0.id == id }) {
                let names = MealFinder.variants(of: item).map(\.name)
                assert(!names.contains { $0.contains("No Cheese") && id.contains("cheese") || $0.contains("No Bacon") && id.contains("bacon") }, "\(id): \(names)")
            }
        }
        // A Big Mac is 621 Cal; without its sauce it fits a 540 Cal limit, and the finder suggests that.
        var bigMacQuery = FindQuery(chains: ["mcd"], calories: 540, protein: 25, maxItems: 1)
        assert(MealFinder.find([bigMac], query: bigMacQuery).first?.items.map(\.food.id) == [noSauce.id])
        bigMacQuery.customise = false
        assert(MealFinder.find([bigMac], query: bigMacQuery).isEmpty)
        // An order that already fits comes first as it's sold; with more room, another patty adds protein.
        let fitsAsSold = MealFinder.find([bigMac], query: FindQuery(chains: ["mcd"], calories: 650, protein: 20, maxItems: 1))
        assert(fitsAsSold.first?.items[0].food.id == bigMac.id)
        let moreProtein = MealFinder.find([bigMac], query: FindQuery(chains: ["mcd"], calories: 800, protein: 38, maxItems: 1))
        assert(moreProtein.first?.items[0].food.name == "Big Mac · Extra Beef Patty")
        // New options from pairs of items and fillets sold on their own.
        let zingerBurger = catalog.foods.first { $0.id == "kfc:zinger-burger" }!
        assert(zingerBurger.modifiers?.contains { $0.name == "Add a Zinger Fillet" && $0.kj == 936 && $0.p == 20.4 } == true)
        let angus = catalog.foods.first { $0.id == "hj:grill-masters-bbq-smokehouse-angus" }!
        assert(angus.modifiers?.contains { $0.name == "Make it a Double" && $0.kj == 1765 } == true)
        assert(catalog.foods.first { $0.id == "oporto:chicken-bacon-egg-burger" }!.modifiers?.contains { $0.name == "No Chicken Fillet" && $0.kj == -1090 } == true)
        assert(catalog.foods.first { $0.id == "hj:grill-masters-chicago-angus" }!.modifiers?.contains { $0.name == "Make it a Double" } != true)
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

        // Siri: the usual meal, what's left today, and what fits.
        let wrap = Food(id: "wrap", name: "Chicken wrap", kj: 2000, cal: 480, p: 35)
        let toast = Food(id: "toast", name: "Toast", kj: 1000, cal: 240, p: 8)
        var usualLogs: [String: [LogEntry]] = [:]
        for n in 1...3 { usualLogs[dayKey(day(n))] = [LogEntry(name: "Wrap", items: [Portion(food: wrap)], time: day(n), mealTime: .lunch)] }
        usualLogs[dayKey(day(4))] = [LogEntry(name: "Toast", items: [Portion(food: toast)], time: day(4), mealTime: .lunch),
                                     LogEntry(name: "Toast", items: [Portion(food: toast)], time: day(4), mealTime: .breakfast)]
        assert(Assistant.usual(.lunch, logs: usualLogs, now: day(5), calendar: calendar)?.name == "Wrap")
        assert(Assistant.usual(.breakfast, logs: usualLogs, now: day(5), calendar: calendar)?.name == "Toast")
        assert(Assistant.usual(.dinner, logs: usualLogs, now: day(5), calendar: calendar) == nil)
        let copied = QuickLog.copies(usualLogs[dayKey(day(1))]![0].items)
        assert(copied[0].food == wrap && copied[0].id != usualLogs[dayKey(day(1))]![0].items[0].id)
        var siriData = AppData(); siriData.logs[dayKey(day(5))] = [LogEntry(name: "Wrap", items: [Portion(food: wrap)], time: day(5), mealTime: .lunch)]
        let siriGoals = Goals()  // 2,200 Cal and 150 g protein; a typical meal is 500 Cal with 40 g protein.
        let left = Assistant.remaining(siriData, goals: siriGoals, now: day(5))
        assert(left.calories == 1720 && left.protein == 115)
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day(5))!
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day(5))!
        let lunchBudget = Assistant.budget(siriData, goals: siriGoals, chain: "kfc", now: noon, calendar: calendar)!
        assert(lunchBudget.calories == 500 && lunchBudget.protein == 40 && lunchBudget.chains == ["kfc"])
        let dinnerBudget = Assistant.budget(siriData, goals: siriGoals, chain: "kfc", now: evening, calendar: calendar)!
        assert(dinnerBudget.calories == 1720 && dinnerBudget.protein == 115)
        var fullDay = siriData; fullDay.logs[dayKey(day(5))]! += [LogEntry(name: "Big", items: [Portion(food: steadyFood)], time: day(5))]
        assert(Assistant.budget(fullDay, goals: siriGoals, chain: "kfc", now: evening, calendar: calendar) == nil)
        assert(Assistant.fitsAnswer(restaurant: "KFC", query: nil, matches: [], caloriesLeft: -280) == "You've used today's calories, so nothing at KFC fits. You're 280 Cal over today's target.")
        let pair = [Portion(food: wrap), Portion(food: wrap), Portion(food: toast)]
        assert(Assistant.describe(pair) == "2 × Chicken wrap + Toast")
        let answer = Assistant.fitsAnswer(restaurant: "KFC", query: lunchBudget, matches: [MealMatch(items: [Portion(food: wrap)], total: Nutrition([Portion(food: wrap)]))], caloriesLeft: 1720)
        assert(answer == "At KFC, for up to 500 Cal with 40 g protein:\n• Chicken wrap: 480 Cal, 35 g protein")
        assert(Assistant.fitsAnswer(restaurant: "KFC", query: lunchBudget, matches: [], caloriesLeft: 1720) == "Nothing at KFC fits in 500 Cal.")
        // Siri's restaurant names match the menu.
        for id in Set(Assistant.nicknames.values) { assert(catalog.chains.contains { $0.id == id }, "unknown chain \(id)") }

        // Meal reminders: two weeks ahead, none for meals already logged, none in the past.
        let reminderNow = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day(5))!
        let planned = MealReminders.plan([(meal: .breakfast, minutes: 9 * 60), (meal: .lunch, minutes: 13 * 60), (meal: .dinner, minutes: 19 * 60)],
                                         logs: siriData.logs, now: reminderNow, calendar: calendar)
        assert(!planned.contains { $0.id == "reminder.breakfast.\(dayKey(day(5)))" })
        assert(!planned.contains { $0.id == "reminder.lunch.\(dayKey(day(5)))" })
        assert(planned.contains { $0.id == "reminder.dinner.\(dayKey(day(5)))" && calendar.component(.hour, from: $0.date) == 19 })
        assert(planned.count == 1 + 13 * 3 && planned.allSatisfy { $0.date > reminderNow })

        // The late-night reminder checks the whole day: any entry at all cancels it, while a logged meal cancels only its own.
        let night = [(meal: MealTime.dinner, minutes: 19 * 60), (meal: MealTime.snacks, minutes: 21 * 60 + 30)]
        let nightPlan = MealReminders.plan(night, logs: siriData.logs, now: reminderNow, calendar: calendar)
        assert(!nightPlan.contains { $0.id == "reminder.snacks.\(dayKey(day(5)))" }, "something was logged that day, so no late-night nudge")
        assert(nightPlan.contains { $0.id == "reminder.snacks.\(dayKey(day(6)))" && calendar.component(.hour, from: $0.date) == 21 && calendar.component(.minute, from: $0.date) == 30 })
        assert(MealReminders.meals == [.breakfast, .lunch, .dinner, .snacks] && MealReminders.title(.snacks) == "Late night" && MealReminders.defaultMinutes(.snacks) == 21 * 60 + 30)
        // Wording varies by day, repeats only after a full cycle, and is the same every time it's worked out.
        for meal in MealReminders.meals {
            let words = (0..<6).map { MealReminders.message(meal, on: calendar.date(byAdding: .day, value: $0, to: day(0))!, calendar: calendar) }
            assert(Set(words.map(\.body)).count == 6 && words.allSatisfy { !$0.title.isEmpty && !$0.body.isEmpty })
            assert(MealReminders.message(meal, on: day(0), calendar: calendar) == MealReminders.message(meal, on: day(0), calendar: calendar))
            assert(MealReminders.message(meal, on: day(0), calendar: calendar).title != MealReminders.message(meal, on: day(1), calendar: calendar).title)
        }
        assert(MealReminders.message(.snacks, on: day(0), calendar: calendar).body != MealReminders.message(.dinner, on: day(0), calendar: calendar).body)
        // Turning log reminders off (Premium locked) counts as a change, so the booked ones are cleared.
        assert(MealReminders.inputs(siriData, goals: siriGoals, now: noon, calendar: calendar, logReminders: false) != MealReminders.inputs(siriData, goals: siriGoals, now: noon, calendar: calendar))

        // Daylight saving: Melbourne's clocks go forward on 4 Oct 2026, and a 1:30 pm reminder stays at 1:30 pm.
        var victoria = Calendar(identifier: .gregorian); victoria.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        let changeover = victoria.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 20))!
        let dstPlan = MealReminders.plan([(meal: .lunch, minutes: 13 * 60 + 30)], logs: [:], now: changeover, calendar: victoria)
        assert(dstPlan.allSatisfy { victoria.component(.hour, from: $0.date) == 13 && victoria.component(.minute, from: $0.date) == 30 })
        // Reminders are rebooked when anything they depend on changes, and not for unrelated saves.
        let before = MealReminders.inputs(siriData, goals: siriGoals, now: noon, calendar: calendar)
        var trayOnly = siriData; trayOnly.tray = [Portion(food: toast)]
        assert(MealReminders.inputs(trayOnly, goals: siriGoals, now: noon, calendar: calendar) == before)
        var weighed = siriData; weighed.weights = [WeightEntry(date: noon, kg: 80)]
        assert(MealReminders.inputs(weighed, goals: siriGoals, now: noon, calendar: calendar) != before)
        var newTarget = siriGoals; newTarget.values["p"] = 170
        assert(MealReminders.inputs(siriData, goals: newTarget, now: noon, calendar: calendar) != before)
        var lunchLogged = siriData; lunchLogged.logs[dayKey(day(6))] = [LogEntry(name: "Wrap", items: [Portion(food: wrap)], time: day(6), mealTime: .lunch)]
        assert(MealReminders.inputs(lunchLogged, goals: siriGoals, now: noon, calendar: calendar) != before)

        // CSV exports: blanks for missing figures, quoting, and no spreadsheet formulas.
        assert(LogExport.field("Wrap, large") == "\"Wrap, large\"" && LogExport.field("Say \"hi\"") == "\"Say \"\"hi\"\"\"")
        assert(LogExport.field("=HYPERLINK(1)") == "'=HYPERLINK(1)" && LogExport.field("-5") == "-5")
        var csvData = AppData()
        let partial = Food(id: "p1", name: "Mystery, bowl", kj: 1000, cal: 240, p: 20, c: nil, f: 9, nut: ["fibre": 4])
        let plain = Food(id: "p2", name: "Apple", kj: 400, cal: 95, p: 0.5, c: 25, f: 0.3)
        csvData.logs[dayKey(day(1))] = [LogEntry(name: "Lunch", items: [Portion(food: partial, quantity: 2), Portion(food: plain)], time: day(1), mealTime: .lunch)]
        let itemRows = LogExport.items(csvData) { $0 == "mine" ? "My foods" : $0 }.components(separatedBy: "\r\n")
        assert(itemRows.count == 4 && itemRows[0].hasPrefix("Date,Time,Meal time,Meal,Food,Restaurant,Serving,Quantity,Calories,kJ,Protein (g),Carbs (g),Fat (g)"))
        assert(itemRows[1].hasPrefix("\(dayKey(day(1))),08:00,Lunch,Lunch,\"Mystery, bowl\",My foods,1 serving,2,480,2000,40,,18,"))
        let dayRows = LogExport.days(csvData).components(separatedBy: "\r\n")
        assert(dayRows.count == 3 && dayRows[1].hasPrefix("\(dayKey(day(1))),1,575,40.5,25,18.3,,,,8,"))
        assert(dayRows[1].contains(",Carbs; Fibre,") && dayRows[1].hasSuffix(",2200,150,,,,,,,,,,,,"))
        // A day where no food listed carbs exports a blank, not 0.
        var noCarbs = AppData(); noCarbs.logs[dayKey(day(2))] = [LogEntry(name: "Spud", items: [Portion(food: partial)], time: day(2))]
        assert(LogExport.days(noCarbs).components(separatedBy: "\r\n")[1].hasPrefix("\(dayKey(day(2))),1,240,20,,9,"))

        // Weekly review: averages over logged days only, protein days, weight trend and repeat meals.
        var week = AppData()
        for n in 0...1 { week.logs[dayKey(day(n))] = [LogEntry(name: "Wrap", items: [Portion(food: wrap)], time: day(n)), LogEntry(name: "wrap", items: [Portion(food: wrap)], time: day(n))] }
        week.logs[dayKey(day(2))] = [LogEntry(name: "Toast", items: [Portion(food: toast)], time: day(2))]
        week.logs[dayKey(day(8))] = [LogEntry(name: "Next week", items: [Portion(food: steadyFood)], time: day(8))]
        week.weights = [WeightEntry(date: day(-3), kg: 80), WeightEntry(date: day(5), kg: 79)]
        let review = WeeklyReview.make(week, goals: Goals(), ending: day(6), calendar: calendar)
        assert(review.loggedDays == 3 && review.averageCalories == 720 && abs(review.averageProtein! - 148.0 / 3) < 0.001)
        assert(review.calorieTarget == 2200 && review.proteinTarget == 150 && review.proteinDays == 0 && review.calorieDays == 3)
        assert(abs(review.weightChange! + (1 - pow(0.9, 8))) < 0.0001 && review.topMeals == [WeeklyReview.Meal(name: "Wrap", count: 4)])
        assert(review.totalCalories == 2160 && review.totalCalorieTarget == 6600)
        assert(review.summary == "Logged 3 of 7 days · 2,160 Cal in total · avg 720 · protein target hit 0 days · trend −0.6 kg.")
        // Recently logged foods: newest first, each once, and nothing from before the window.
        let recentFoods = QuickLog.recentFoods(logs: week.logs, now: day(8), days: 30, calendar: calendar)
        assert(recentFoods.first?.id == steadyFood.id && Set(recentFoods.map { $0.chain + $0.name }).count == recentFoods.count)
        assert(QuickLog.recentFoods(logs: week.logs, now: day(60), days: 30, calendar: calendar).isEmpty)
        assert(WeeklyReview.make(AppData(), goals: Goals(), ending: day(6), calendar: calendar).summary == "Nothing logged this week yet.")
        let wednesday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day(2))!
        assert(MealReminders.nextReview(after: wednesday, calendar: calendar) == calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day(6)))
        let sundayNight = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day(6))!
        assert(MealReminders.nextReview(after: sundayNight, calendar: calendar) == calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day(13)))

        // Menu updates: only a newer menu in a known format, with every item valid, replaces the one in use.
        assert(catalog.format == MenuUpdates.format && catalog.published != nil && catalog.revision != nil)
        assert(MenuUpdates.url?.scheme == "https" && MenuUpdates.url?.host == "gist.githubusercontent.com" && MenuUpdates.url?.lastPathComponent == "MenuData.json")
        var newer = catalog; newer.published = "2099-01-01T00:00:00.000Z"
        assert(MenuUpdates.acceptable(newer, over: catalog))
        assert(!MenuUpdates.acceptable(catalog, over: catalog))
        assert(!MenuUpdates.acceptable(catalog, over: newer))
        var future = newer; future.format = 2; assert(!MenuUpdates.acceptable(future, over: catalog))
        var orphan = newer; orphan.foods[0].chain = "nowhere"; assert(!MenuUpdates.acceptable(orphan, over: catalog))
        var twin = newer; twin.foods[1].id = twin.foods[0].id; assert(!MenuUpdates.acceptable(twin, over: catalog))
        var negativeMenu = newer; negativeMenu.foods[0].cal = -1; assert(!MenuUpdates.acceptable(negativeMenu, over: catalog))
        var shrunk = newer; shrunk.foods = Array(shrunk.foods.prefix(10)); assert(!MenuUpdates.acceptable(shrunk, over: catalog))
        let cachedMenu = root.appending(path: "cached-menu.json")
        try JSONEncoder().encode(newer).write(to: cachedMenu)
        assert(MenuUpdates.best(bundled: catalog, cachedAt: cachedMenu).published == newer.published)
        try Data("not json".utf8).write(to: cachedMenu)
        assert(MenuUpdates.best(bundled: catalog, cachedAt: cachedMenu).published == catalog.published)
        assert(MenuUpdates.best(bundled: catalog, cachedAt: root.appending(path: "missing.json")).published == catalog.published)

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
        // Delivery estimate: by distance from the nearest restaurant of the chain.
        assert(Delivery.estimate(metres: 1_200) == .likely(metres: 1_200))
        assert(Delivery.estimate(metres: 6_500) == .maybe(metres: 6_500))
        assert(Delivery.estimate(metres: 9_000) == .tooFar && Delivery.estimate(metres: nil) == .tooFar)
        assert(!Delivery.tooFar.available && Delivery.maybe(metres: 6_000).available)
        assert(DeliveryApp.all.map(\.name) == ["Uber Eats", "DoorDash", "Menulog"])
        assert(DeliveryApp.all[0].search("Hungry Jack's")?.absoluteString == "https://www.ubereats.com/au/search?q=Hungry%20Jack's")
        assert(DeliveryApp.all[1].search("Hungry Jack's")?.absoluteString == "https://www.doordash.com/search/store/Hungry%20Jack's/")

        // Weights keep two decimal places, shown without trailing zeros.
        assert(81.75.hundredth == 81.75 && 81.754.hundredth == 81.75 && 81.756.hundredth == 81.76)
        assert(81.75.kgText == "81.75" && 82.4.kgText == "82.4" && 82.0.kgText == "82" && 81.756.hundredth.kgText == "81.76")

        // Pinned foods and the Log again widget.
        let pinURL = root.appending(path: "pins.json")
        let pinStore = AppStore(url: pinURL, catalogURL: catalogURL, legacyURL: nil)
        let zinger = pinStore.foods.first { $0.id == "kfc:zinger-burger" }!
        pinStore.togglePin(zinger)
        assert(pinStore.isPinned(zinger) && pinStore.pinnedFoods.map(\.id) == [zinger.id] && pinStore.notice == "Pinned Zinger Burger")
        assert(AppStore(url: pinURL, catalogURL: catalogURL, legacyURL: nil).isPinned(zinger))
        assert(pinStore.pinnedFoods[0].modifiers != nil, "a pinned menu item shows the current menu version")
        assert(pinStore.quickLogOptions().contains { $0.id == "pin:kfc:zinger-burger" && $0.lastLogged == nil && $0.calories == zinger.cal })
        assert(pinStore.logAgain("pin:kfc:zinger-burger") && !pinStore.logAgain("pin:missing") && !pinStore.logAgain("usual:nonsense"))
        let now = Date(), slot = MealTime.suggested(at: now)
        assert(pinStore.data.logs[dayKey(now)]?.last?.mealTime == slot)
        let afterLog = pinStore.quickLogOptions(now: now)
        assert(afterLog.first { $0.id == "pin:kfc:zinger-burger" }?.lastLogged == dayKey(now))
        assert(afterLog.contains { $0.id == "usual:\(slot.rawValue)" && $0.name == "Zinger Burger" && $0.lastLogged == dayKey(now) })
        var snapshot = WidgetCalories(target: 2000, dailyCalories: [:]); snapshot.quickLogOptions = afterLog
        assert(snapshot.quickLogs(at: now).first?.id == "usual:\(slot.rawValue)", "the usual meal for now comes first")
        assert(snapshot.quickLogs(at: now).filter { $0.name == "Zinger Burger" }.count == 1, "a pin that is also the usual meal shows once")
        assert(!pinStore.logAgain("usual:\(slot.rawValue)", at: now.addingTimeInterval(3)), "a double tap logs once")
        assert(pinStore.logAgain("usual:\(slot.rawValue)", at: now.addingTimeInterval(20)) && pinStore.data.logs[dayKey(now)]?.count == 2)
        let queuedAt = calendar.date(byAdding: .day, value: -1, to: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: now)!)!
        assert(pinStore.applyQueuedQuickLogs([.init(option: "pin:kfc:zinger-burger", date: queuedAt), .init(option: "pin:gone", date: queuedAt)]) == 1)
        assert(pinStore.data.logs[dayKey(queuedAt)]?.last?.mealTime == .lunch, "a queued log keeps its own time")
        assert(["breakfast", "lunch", "dinner", "snacks"].allSatisfy { MealTime(rawValue: $0) != nil })
        for food in pinStore.foods.filter({ $0.chain == "kfc" }).prefix(AppStore.pinLimit) where !pinStore.isPinned(food) { pinStore.togglePin(food) }
        assert(pinStore.data.pinned?.count == AppStore.pinLimit)
        pinStore.togglePin(pinStore.foods.first { $0.chain == "hj" }!)
        assert(pinStore.data.pinned?.count == AppStore.pinLimit && pinStore.notice?.hasPrefix("You can pin up to") == true)
        pinStore.togglePin(zinger)
        assert(!pinStore.isPinned(zinger) && pinStore.notice == "Unpinned Zinger Burger")
        var pinsFromBackup = AppData(); pinsFromBackup.pinned = [zinger]
        assert(AppStore.merged(AppData(), pinsFromBackup).pinned?.map(\.id) == [zinger.id])

        // Saving a scanned product to My foods: rounded like the editor, and the same barcode updates rather than duplicates.
        let scanStore = AppStore(url: root.appending(path: "scans.json"), catalogURL: catalogURL, legacyURL: nil)
        var scanned = Food(name: "Greek yoghurt", kj: 123.456 * 4.184, cal: 123.456, p: 10.04, c: 5.55, f: 2.06, serve: "100 g")
        scanned.barcode = "9300601000017"
        let kept = scanStore.saveToMyFoods(scanned)!
        assert(kept.chain == "mine" && kept.cal == 123.5 && kept.p == 10 && scanStore.data.foods.count == 1)
        var rescanned = scanned; rescanned.id = UUID().uuidString; rescanned.name = "Greek yoghurt (new label)"; rescanned.barcode = "09300601000017"
        assert(scanStore.saveToMyFoods(rescanned)?.id == kept.id && scanStore.data.foods.count == 1 && scanStore.data.foods[0].name == "Greek yoghurt (new label)")
        assert(BarcodeLookup.match("9300601000017", in: scanStore.data.foods)?.id == kept.id)
        assert(QuickLog.lastQuantity(of: kept.id, logs: scanStore.data.logs) == nil)
        assert(scanStore.log([Portion(food: kept, quantity: 0.2)], name: kept.name, date: day0))
        assert(scanStore.log([Portion(food: kept, quantity: 0.35)], name: kept.name, date: day(2)))
        assert(QuickLog.lastQuantity(of: kept.id, logs: scanStore.data.logs) == 0.35, "the most recent amount is offered next time")

        // Saved meals can be edited in place (rename, add, remove), with undo, and never saved empty.
        let mealStore = AppStore(url: root.appending(path: "meals.json"), catalogURL: catalogURL, legacyURL: nil)
        let mealMain = mealStore.catalog.foods[0], mealSide = mealStore.catalog.foods[1]
        var saved = SavedMeal(name: "Lunch", items: [Portion(food: mealMain, quantity: 1), Portion(food: mealSide, quantity: 1)])
        assert(mealStore.change { $0.meals = [saved] })
        saved.name = "Light lunch"; saved.items.removeFirst(); saved.items[0].quantity = 2
        assert(mealStore.updateMeal(saved) && mealStore.data.meals.count == 1)
        assert(mealStore.data.meals[0].name == "Light lunch" && mealStore.data.meals[0].items.count == 1 && mealStore.data.meals[0].items[0].quantity == 2)
        var emptied = saved; emptied.items = []
        assert(!mealStore.updateMeal(emptied) && mealStore.data.meals[0].items.count == 1, "an empty meal isn't saved")
        assert(!mealStore.updateMeal(SavedMeal(name: "Other", items: saved.items)), "only existing meals are updated")
        mealStore.undoLast()
        assert(mealStore.data.meals[0].name == "Lunch" && mealStore.data.meals[0].items.count == 2)

        // A logged meal can be edited in place or moved to another day, with undo.
        let logStore = AppStore(url: root.appending(path: "logs-edit.json"), catalogURL: catalogURL, legacyURL: nil)
        assert(logStore.log([Portion(food: mealMain, quantity: 1)], name: "Lunch", date: day0, mealTime: .lunch))
        var logged = logStore.data.logs[dayKey(day0)]![0]
        logged.items.append(Portion(food: mealSide, quantity: 2)); logged.name = "Big lunch"
        assert(logStore.updateLog(logged, day: dayKey(day0), to: dayKey(day0)))
        assert(logStore.data.logs[dayKey(day0)]!.count == 1 && logStore.data.logs[dayKey(day0)]![0].items.count == 2)
        assert(logStore.updateLog(logged, day: dayKey(day0), to: dayKey(day(1))))
        assert(logStore.data.logs[dayKey(day0)]!.isEmpty && logStore.data.logs[dayKey(day(1))]!.map(\.name) == ["Big lunch"])
        assert(logStore.data.dayGoals[dayKey(day(1))] != nil, "a meal moved to a new day brings that day's targets")
        var emptyLog = logged; emptyLog.items = []
        assert(!logStore.updateLog(emptyLog, day: dayKey(day(1)), to: dayKey(day(1))), "an empty meal isn't saved")
        logStore.undoLast()
        assert(logStore.data.logs[dayKey(day0)]!.count == 1 && (logStore.data.logs[dayKey(day(1))] ?? []).isEmpty)

        // Weights read from Apple Health never go to iCloud, and come back from this device after a sync.
        var withHealth = AppData()
        withHealth.weights = [WeightEntry(date: day0, kg: 80), WeightEntry(date: day(1), kg: 79.5, healthID: UUID())]
        assert(withHealth.forICloud.weightLog.count == 1 && withHealth.forICloud.weightLog[0].healthID == nil)
        let fromCloud = withHealth.forICloud.keepingHealthWeights(from: withHealth)
        assert(fromCloud.weightLog.count == 2 && fromCloud.weightLog.contains { $0.healthID != nil })
        assert(AppData().keepingHealthWeights(from: AppData()).weights == nil)

        // Delete all my data: nothing saved survives, on disk or in memory, and there's no undo back to it.
        let eraseURL = root.appending(path: "erase.json")
        let eraseStore = AppStore(url: eraseURL, catalogURL: catalogURL, legacyURL: nil)
        assert(eraseStore.log([Portion(food: kept, quantity: 1)], name: kept.name, date: day0))
        func blank(_ data: AppData) -> Bool { data.logs.isEmpty && data.foods.isEmpty && data.meals.isEmpty && data.weightLog.isEmpty && data.tray.isEmpty && (data.pinned ?? []).isEmpty }
        assert(eraseStore.eraseEverything() && blank(eraseStore.data) && eraseStore.undo == nil)
        assert(blank(AppStore(url: eraseURL, catalogURL: catalogURL, legacyURL: nil).data))

        // The policies ship with a contact placeholder the app fills in, and the font licences ship beside them.
        let legal = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appending(path: "Legal")
        for name in ["PrivacyPolicy.md", "Terms.md"] {
            let text = try String(contentsOf: legal.appending(path: name), encoding: .utf8)
            assert(text.contains("{{CONTACT}}") && text.contains("Effective "), "\(name) has its contact and date")
        }
        for name in ["Apache-2.0.txt", "OFL-BebasNeue.txt"] { assert(FileManager.default.fileExists(atPath: legal.appending(path: name).path)) }

        // Everyday foods (USDA) are searchable and loggable, but never treated as a restaurant.
        let everydayURL = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appending(path: "GenericFoods.json")
        let everydayStore = AppStore(url: root.appending(path: "everyday.json"), catalogURL: catalogURL, legacyURL: nil, everydayURL: everydayURL)
        let everyday = everydayStore.everyday
        assert(everyday.count >= 150 && Set(everyday.map(\.id)).count == everyday.count && Set(everyday.map(\.name)).count == everyday.count)
        assert(everyday.allSatisfy { $0.isValid && $0.isEveryday && $0.id.hasPrefix("usda-") && $0.servingWeight != nil && $0.cal <= 1000 })
        let banana = everyday.first { $0.name == "Banana" }!, breast = everyday.first { $0.name == "Chicken breast, cooked" }!
        assert(abs(banana.cal - 105) < 1 && banana.serve == "1 medium (118 g)" && abs(breast.p - 31) < 0.1 && breast.serve == "100 g")
        assert(everyday.first { $0.name == "Beer" }?.mismatch == false)
        assert(breast.everydaySource?.absoluteString == "https://fdc.nal.usda.gov/food-details/171477/nutrients")
        assert(everydayStore.chainName(Food.everyday) == "Everyday foods")
        assert(everydayStore.foods.contains { $0.id == banana.id } && !everydayStore.orderFoods.contains { $0.isEveryday })
        let searched = FoodSearch.browse(everydayStore.foods, chainNames: [Food.everyday: "Everyday foods"], request: .init(search: "chicken breast", chain: Food.everyday))
        assert(Set(searched.map(\.name)) == ["Chicken breast, raw", "Chicken breast, cooked", "Chicken breast, skin on, roasted", "Roast chicken, breast meat only"])
        assert(MealSwaps.options(for: Portion(food: breast), foods: everydayStore.foods).isEmpty)
        assert(FoodSearch.browse(everydayStore.foods, chainNames: [:], request: .init(search: "banana")).first?.name == "Banana")
        // "rice" finds rice itself before things made with it ("Rice pudding").
        let rice = FoodSearch.browse(everydayStore.foods, chainNames: [:], request: .init(search: "rice", chain: Food.everyday)).map(\.name)
        assert(rice.prefix(4).allSatisfy { !$0.hasPrefix("Rice ") } && rice.contains("Rice pudding") && everyday.count >= 330)

        // Photos and Visual Intelligence: what's seen is matched to Leanr's own foods, exactly, everyday foods first.
        let photoNames = Dictionary(everydayStore.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: "Everyday foods"]) { a, _ in a }
        func seen(_ name: String, _ others: [String] = [], brand: String? = nil) -> [String] {
            MealPhoto.matches(for: SeenFood(name: name, alternatives: others, brand: brand, count: 1), in: everydayStore.foods, chainNames: photoNames).map(\.name)
        }
        assert(seen("banana").first == "Banana")
        assert(seen("rice").prefix(2).allSatisfy { $0.hasSuffix("rice, cooked") })
        assert(seen("rice").first == "White rice, cooked" && seen("chicken breast").first == "Chicken breast, cooked")
        assert(seen("egg").first == "Egg" && seen("potato").first == "Potato, baked")
        assert(seen("chicken leg", ["chicken drumstick"]) == ["Chicken drumstick, cooked"])
        assert(seen("chair").isEmpty && seen("bananna").isEmpty)
        // Apple's image classifier: its chain of labels becomes one food, and a dish's parts aren't foods of their own.
        func labels(_ pairs: [(String, Double)]) -> [VisionFoodLabels.Reading] { pairs.map { VisionFoodLabels.Reading(identifier: $0.0, confidence: $0.1) } }
        func visionNames(_ whole: [(String, Double)], tiles: [[(String, Double)]] = []) -> [String] {
            VisionFoodLabels.foods(whole: labels(whole), tiles: tiles.map(labels)).map(\.name)
        }
        assert(visionNames([("food", 0.89), ("hamburger", 0.89), ("meat", 0.89), ("seed", 0.08), ("sesame", 0.08), ("cheese", 0.07)]) == ["hamburger"])
        assert(visionNames([("food", 0.21), ("banana", 0.21), ("fruit", 0.21), ("pacifier", 0.13), ("toy", 0.13)]) == ["banana"])
        assert(visionNames([("food", 0.41), ("dessert", 0.34), ("baked_goods", 0.34), ("cake", 0.34), ("pancake", 0.34)]) == ["pancakes"])
        assert(visionNames([("food", 0.57), ("cake", 0.57), ("dessert", 0.57)]) == ["cake"])
        assert(visionNames([("food", 0.18), ("meat", 0.18), ("pepperoni", 0.18), ("cheese", 0.08), ("pizza", 0.06)]) == ["pepperoni pizza"])
        assert(visionNames([("food", 0.8), ("pizza", 0.8), ("cheese", 0.5), ("pepperoni", 0.4)]) == ["pizza"])
        assert(visionNames([("cookware", 0.71), ("food", 0.6), ("egg", 0.56), ("yolk", 0.56), ("fried_egg", 0.43)]) == ["egg, fried"])
        assert(visionNames([("food", 0.7), ("egg", 0.7), ("yolk", 0.7)]) == ["egg"])
        assert(visionNames([("dog", 0.9), ("animal", 0.9), ("food", 0.03)]).isEmpty && visionNames([("banana", 0.06)]).isEmpty)
        assert(visionNames([("tableware", 0.7), ("plate", 0.7)]).isEmpty)
        // A plate is read a part at a time: separate foods stay separate, the parts of the dish don't.
        assert(visionNames([("hamburger", 0.5)], tiles: [[("fries", 0.7)], [("soda", 0.5)], [("lettuce", 0.5)], [("banana", 0.2)]])
            == ["french fries", "hamburger", "cola"])
        assert(visionNames([], tiles: [[("banana", 0.8)], [("banana", 0.6)]]) == ["banana"])
        assert(VisionFoodLabels.foods(whole: labels([("hamburger", 0.9)])).allSatisfy { $0.count == 1 && $0.brand == nil })
        // Singular and plural are the same food: "strawberry" is Strawberries, not a smoothie with strawberry in its name.
        assert(seen("strawberry").first == "Strawberries" && seen("eggs").first == "Egg" && seen("tomatoes").first == "Tomato")
        assert(MealPhoto.stem("strawberries") == MealPhoto.stem("strawberry") && MealPhoto.stem("peas") != MealPhoto.stem("peach"))
        // Two engines: what both saw counts once, the classifier's foods lead, and a food only the model named is not
        // ticked when the classifier was sure of something else.
        func item(_ name: String, _ alternatives: [String] = [], count: Int = 1) -> SeenFood { SeenFood(name: name, alternatives: alternatives, brand: nil, count: count) }
        let plate = [(food: item("avocado"), score: 0.8), (food: item("broccoli"), score: 0.88), (food: item("carrot"), score: 0.92)]
        let merged = MealPhoto.merge(named: [item("strawberry")], classified: plate)
        assert(merged.engine == .both && merged.foods.map(\.name) == ["avocado", "broccoli", "carrot", "strawberry"])
        assert(merged.foods.prefix(3).allSatisfy(\.agreed) && merged.foods.last?.agreed == false)
        let agreed = MealPhoto.merge(named: [item("burger", count: 2)], classified: [(food: item("hamburger", ["cheeseburger"]), score: 0.9)])
        assert(agreed.foods.count == 1 && agreed.foods[0].count == 2 && agreed.foods[0].agreed)
        let unsure = MealPhoto.merge(named: [item("rice")], classified: [(food: item("banana"), score: 0.2)])
        assert(unsure.foods.count == 2 && unsure.foods.allSatisfy(\.agreed))
        assert(MealPhoto.merge(named: [], classified: plate).engine == .imageRecognition && MealPhoto.merge(named: [item("rice")], classified: []).engine == .appleIntelligence)
        assert(ticked("strawberry") != nil && ticked("rice") != nil)
        var untrusted = item("strawberry"); untrusted.agreed = false
        assert(MealPhoto.preselected(from: MealPhoto.matches(for: untrusted, in: everydayStore.foods, chainNames: photoNames), for: untrusted, chainNames: photoNames) == nil)
        // Nearly every label looks up a food that exists, so a recognised "banana" can't turn up empty-handed.
        let unmatched = VisionFoodLabels.names.filter { _, words in
            MealPhoto.matches(for: SeenFood(name: words[0], alternatives: Array(words.dropFirst()), brand: nil, count: 1),
                              in: everydayStore.foods, chainNames: photoNames).isEmpty
        }.keys.sorted()
        // These dishes have no everyday food yet: the row says so and offers a search.
        assert(Set(unmatched).isSubset(of: ["casserole", "curry", "dumpling", "gyoza", "kebab"]))
        // Only everyday foods, or the restaurant a visible brand names, are ticked by default.
        func ticked(_ name: String, _ others: [String] = [], brand: String? = nil) -> Food? {
            let item = SeenFood(name: name, alternatives: others, brand: brand, count: 1)
            return MealPhoto.preselected(from: MealPhoto.matches(for: item, in: everydayStore.foods, chainNames: photoNames), for: item, chainNames: photoNames)
        }
        assert(MealPhoto.chain(for: "Macca's", chainNames: photoNames) == "mcd" && MealPhoto.chain(for: "McDonald's", chainNames: photoNames) == "mcd"
            && MealPhoto.chain(for: "Burger King", chainNames: photoNames) == "hj" && MealPhoto.chain(for: "Guzman y Gomez", chainNames: photoNames) == "gyg"
            && MealPhoto.chain(for: "", chainNames: photoNames) == nil && MealPhoto.chain(for: "Acme Burgers", chainNames: photoNames) == nil)
        assert(ticked("banana")?.isEveryday == true)
        assert(ticked("Big Mac") == nil && !seen("Big Mac").isEmpty)
        assert(ticked("Big Mac", brand: "McDonald's")?.name == "Big Mac" && ticked("Big Mac", brand: "McDonald's")?.isEveryday == false)
        assert(ticked("fries")?.isEveryday != false)
        assert(seen("Big Mac", brand: "McDonald's").first == "Big Mac" && seen("fries", brand: "macca's").first?.contains("Fries") == true)
        let visual = Assistant.visualMatches(labels: ["Food", "Fruit", "Banana"], foods: everydayStore.foods, chainNames: photoNames)
        assert(visual.first?.name == "Banana" && Set(visual.map(\.id)).count == visual.count && visual.count <= 10)
        assert(Assistant.visualSearchText(["Food", "Banana"]) == "Banana" && Assistant.visualSearchText(["Food"]) == "Food")
        assert(Assistant.macrosAnswer(banana, place: "Everyday foods") == "Banana (1 medium (118 g)) from Everyday foods has 105 Cal, 1.3 g protein, 27 g carbs and 0.4 g fat.")
        assert(FoodSearch.startsWith("Chicken breast, raw", ["chicken", "bre"]) && !FoodSearch.startsWith("Raw chicken", ["chicken"]))

        // Widget text: protein turns green at its goal, carbs and fat turn orange once over their target.
        assert(TargetStatus.of("p", value: 149.9, target: 150) == .none && TargetStatus.of("p", value: 150, target: 150) == .reached)
        assert(TargetStatus.of("p", value: 149.96, target: 150) == .reached, "shown as 150, so it's reached")
        assert(TargetStatus.of("p", value: 220, target: 150) == .reached)
        assert(TargetStatus.of("c", value: 250, target: 250) == .none && TargetStatus.of("c", value: 250.04, target: 250) == .none)
        assert(TargetStatus.of("c", value: 251, target: 250) == .over && TargetStatus.of("f", value: 70.5, target: 70) == .over)
        assert(TargetStatus.of("f", value: 10, target: 70) == .none && TargetStatus.of("p", value: 0, target: 150) == .none)
        assert(TargetStatus.of("p", value: 200, target: nil) == .none && TargetStatus.of("p", value: 200, target: 0) == .none)
        assert(TargetStatus.of("fibre", value: 99, target: 30) == .none && TargetStatus.of("sodium", value: 5000, target: 2000) == .none)
        assert(TargetStatus.none.colour == nil && TargetStatus.reached.colour != nil && TargetStatus.over.colour != nil)
        assert(TargetStatus.reached.spoken.contains("reached") && TargetStatus.over.spoken.contains("Over") && TargetStatus.none.spoken.isEmpty)

        // Premium: only Leanr's own subscriptions count, until they end, and never once refunded.
        let soon = Date().addingTimeInterval(3600), earlier = Date().addingTimeInterval(-3600), premiumNow = Date()
        assert(PremiumAccess.isActive(productID: PremiumAccess.monthly, expires: soon, revoked: false, now: premiumNow))
        assert(PremiumAccess.isActive(productID: PremiumAccess.yearly, expires: nil, revoked: false, now: premiumNow))
        assert(!PremiumAccess.isActive(productID: PremiumAccess.monthly, expires: earlier, revoked: false, now: premiumNow))
        assert(!PremiumAccess.isActive(productID: PremiumAccess.monthly, expires: soon, revoked: true, now: premiumNow))
        assert(!PremiumAccess.isActive(productID: "com.example.other", expires: soon, revoked: false, now: premiumNow))
        assert(PremiumAccess.productIDs == [PremiumAccess.yearly, PremiumAccess.monthly])
        // A remembered subscription is trusted a few days past its end (renewals land late), not forever.
        let ended = PremiumAccess.Entitlement(productID: PremiumAccess.monthly, expires: premiumNow.addingTimeInterval(-86400), renews: true)
        assert(PremiumAccess.isRemembered(ended, now: premiumNow))
        assert(!PremiumAccess.isRemembered(PremiumAccess.Entitlement(productID: PremiumAccess.monthly, expires: premiumNow.addingTimeInterval(-5 * 86400), renews: nil), now: premiumNow))
        assert(!PremiumAccess.isRemembered(nil, now: premiumNow))
        assert(!PremiumAccess.isRemembered(PremiumAccess.Entitlement(productID: "other", expires: nil, renews: nil), now: premiumNow))
        let monthlyEntitlement = PremiumAccess.Entitlement(productID: PremiumAccess.monthly, expires: premiumNow.addingTimeInterval(86400 * 20), renews: true)
        let yearlyEntitlement = PremiumAccess.Entitlement(productID: PremiumAccess.yearly, expires: premiumNow.addingTimeInterval(86400 * 300), renews: true)
        assert(PremiumAccess.best([monthlyEntitlement, yearlyEntitlement]) == yearlyEntitlement && PremiumAccess.best([]) == nil)
        let premiumDefaults = UserDefaults(suiteName: "leanr.checks.premium.\(UUID().uuidString)")!
        assert(PremiumAccess.load(from: premiumDefaults) == nil)
        PremiumAccess.save(monthlyEntitlement, to: premiumDefaults)
        assert(PremiumAccess.load(from: premiumDefaults) == monthlyEntitlement)
        PremiumAccess.save(nil, to: premiumDefaults)
        assert(PremiumAccess.load(from: premiumDefaults) == nil)
        assert(PremiumAccess.statusText(nil) == "Active" && PremiumAccess.statusText(PremiumAccess.Entitlement(productID: PremiumAccess.yearly, expires: nil, renews: nil)) == "Active")
        assert(PremiumAccess.statusText(monthlyEntitlement).hasPrefix("Renews ") && PremiumAccess.statusText(.init(productID: PremiumAccess.monthly, expires: soon, renews: false)).hasPrefix("Ends "))
        assert(PremiumAccess.statusText(.init(productID: PremiumAccess.yearly, expires: soon, renews: true, trial: true)).hasPrefix("Free trial ends "))
        assert(PremiumAccess.statusText(.init(productID: PremiumAccess.yearly, expires: soon, renews: false, trial: true)) .hasSuffix(soon.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_AU")))))

        // "Log banana in Leanr": an exact name wins alone, an amount in grams uses the serving weight, bad amounts are refused.
        let spokenNames = Dictionary(everydayStore.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: "Everyday foods"]) { a, _ in a }
        let spokenBanana = Assistant.spokenMatches(everydayStore.foods, query: "banana", chainNames: spokenNames)
        assert(spokenBanana.map(\.name) == ["Banana"], "\(spokenBanana.map(\.name))")
        assert(Assistant.spokenMatches(everydayStore.foods, query: "chicken", chainNames: spokenNames).count > 1)
        assert(Assistant.spokenMatches(everydayStore.foods, query: "qzxv", chainNames: spokenNames).isEmpty)
        let spokenBreast = everydayStore.foods.first { $0.name == "Chicken breast, cooked" }!, spokenEgg = everydayStore.foods.first { $0.name == "Egg" }!
        assert(Assistant.servings(nil, grams: nil, of: banana) == 1 && Assistant.servings(2.5, grams: nil, of: banana) == 2.5)
        assert(Assistant.servings(1, grams: 250, of: spokenBreast) == 2.5, "100 g serving, so 250 g is 2.5")
        assert(Assistant.servings(nil, grams: 59, of: spokenEgg) == 59.0 / 50.0)
        assert(Assistant.servings(0, grams: nil, of: banana) == nil && Assistant.servings(500, grams: nil, of: banana) == nil)
        assert(Assistant.servings(nil, grams: -5, of: banana) == nil && Assistant.servings(nil, grams: 0, of: spokenBreast) == nil)
        assert(Assistant.servings(nil, grams: 50, of: Food(name: "No weight", kj: 100, cal: 24, p: 1, serve: "1 piece")) == nil)
        assert(Assistant.loggedAnswer(food: banana, quantity: 1, mealTime: .snacks, caloriesLeft: 1200) == "Logged Banana to snacks: 105 Cal, 1.3 g protein. 1,200 Cal left today.")
        assert(Assistant.loggedAnswer(food: banana, quantity: 2, mealTime: .lunch, caloriesLeft: -50) == "Logged 2 × Banana to lunch: 210 Cal, 2.6 g protein. That's 50 Cal over today's target.")
        assert(Assistant.loggedAnswer(food: banana, quantity: 1, mealTime: .dinner, caloriesLeft: nil) == "Logged Banana to dinner: 105 Cal, 1.3 g protein.")

        let oldFormat = try JSONEncoder().encode(AppData())
        let reloadedOld = try JSONDecoder().decode(AppData.self, from: oldFormat)
        assert(reloadedOld.weights == nil && reloadedOld.isValid)

        // Weight goals: how far off, how far along, and when at the current pace.
        do {
            let cal = Calendar(identifier: .gregorian)
            let today = cal.startOfDay(for: Date())
            func weighIns(from start: Double, perWeek: Double, weeks: Int) -> [WeightEntry] {
                (0...(weeks * 7)).map { day in
                    WeightEntry(date: cal.date(byAdding: .day, value: day - weeks * 7, to: today)!, kg: start + perWeek / 7 * Double(day))
                }
            }
            let losing = WeightTrend.points(weighIns(from: 90, perWeek: -0.5, weeks: 4), calendar: cal)
            let goal = WeightGoal(kg: 80, startKg: 90, set: today)
            let status = WeightTrend.goalStatus(goal, points: losing, now: today, calendar: cal)!
            assert(status.direction == .lose && status.pace == .towards && status.projected != nil)
            assert(status.remaining > 7 && status.remaining < 9 && status.progress > 0.05 && status.progress < 0.3)
            let weeks = cal.dateComponents([.day], from: today, to: status.projected!).day! / 7
            assert((14...30).contains(weeks))   // about 8.6 kg to go; the trend lags a new history, so it reads a little under 0.5 kg a week
            // Gaining towards a higher goal, and a flat or wrong-way trend gives no date.
            let gaining = WeightTrend.points(weighIns(from: 60, perWeek: 0.4, weeks: 4), calendar: cal)
            let gainStatus = WeightTrend.goalStatus(WeightGoal(kg: 66, startKg: 60, set: today), points: gaining, now: today, calendar: cal)!
            assert(gainStatus.direction == .gain && gainStatus.pace == .towards && gainStatus.projected != nil)
            let wrong = WeightTrend.goalStatus(WeightGoal(kg: 85, startKg: 90, set: today), points: losing, now: today, calendar: cal)!
            assert(wrong.direction == .lose && wrong.pace == .towards)   // 85 is still below the trend
            let away = WeightTrend.goalStatus(WeightGoal(kg: 95, startKg: 90, set: today), points: losing, now: today, calendar: cal)!
            assert(away.direction == .gain && away.pace == .away && away.projected == nil)
            let flat = WeightTrend.points(weighIns(from: 80, perWeek: 0, weeks: 4), calendar: cal)
            assert(WeightTrend.goalStatus(WeightGoal(kg: 75, startKg: 80, set: today), points: flat, now: today, calendar: cal)!.pace == .flat)
            // Reached, not enough data, and nothing logged.
            let reached = WeightTrend.goalStatus(WeightGoal(kg: 79.95, startKg: 90, set: today), points: flat, now: today, calendar: cal)!
            assert(reached.direction == .reached && reached.progress == 1 && reached.projected == nil)
            let fewDays = WeightTrend.points(weighIns(from: 90, perWeek: -0.5, weeks: 0), calendar: cal)
            assert(WeightTrend.goalStatus(goal, points: fewDays, now: today, calendar: cal)!.pace == .unknown)
            assert(WeightTrend.goalStatus(goal, points: [], now: today, calendar: cal) == nil)
            // A pace you choose, and what it asks of your day.
            let aimed = WeightTrend.date(toCover: 5, kgPerWeek: 0.5, now: today, calendar: cal)!
            assert(cal.dateComponents([.day], from: today, to: aimed).day == 70)
            assert(WeightTrend.date(toCover: 5, kgPerWeek: 0, now: today, calendar: cal) == nil)
            assert(WeightTrend.date(toCover: 50, kgPerWeek: 0.1, now: today, calendar: cal) == nil)   // beyond five years
            assert(abs(WeightTrend.dailyCalorieDifference(kgPerWeek: 0.5) - 550) < 0.01)
            // Saved data from before goals loads, a goal survives a round trip, and the newest goal wins a merge.
            var data = AppData(); data.weightGoal = goal
            let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data))
            assert(decoded.weightGoal == goal && decoded.isValid)
            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppData())) as! [String: Any]
            legacyJSON["weightGoal"] = nil
            let legacy = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            assert(legacy.weightGoal == nil)
            var older = AppData(); older.weightGoal = WeightGoal(kg: 70, startKg: 80, set: today.addingTimeInterval(-86400))
            var newer = AppData(); newer.weightGoal = goal
            assert(AppStore.merged(older, newer).weightGoal == goal && AppStore.merged(newer, older).weightGoal == goal)
            var invalid = AppData(); invalid.weightGoal = WeightGoal(kg: 5, startKg: 80, set: today)
            assert(!invalid.isValid)
        }


        // Water: per-day totals, never below nothing, a daily limit, merges that only go up, and old data still loading.
        do {
            var water = AppData()
            Water.adding(250, on: "2026-10-13", to: &water)
            Water.adding(500, on: "2026-10-13", to: &water)
            assert(Water.total(water, on: "2026-10-13") == 750 && Water.target(water) == 2000 && Water.glass(water) == 250)
            Water.adding(-1000, on: "2026-10-13", to: &water)
            assert(water.water == nil && Water.total(water, on: "2026-10-13") == 0)
            Water.adding(99_999, on: "2026-10-13", to: &water)
            assert(Water.total(water, on: "2026-10-13") == Water.dayLimit && water.isValid)
            Water.adding(10, on: "not-a-day", to: &water); Water.adding(.nan, on: "2026-10-14", to: &water)
            assert(water.water?.count == 1)
            assert(Water.text(750) == "750 mL" && Water.text(1250) == "1.25 L" && Water.text(2000) == "2 L")
            assert(Water.progress(total: 500, target: 2000) == 0.25 && Water.progress(total: 3000, target: 2000) == 1 && Water.progress(total: 5, target: 0) == 0)
            var bad = AppData(); bad.water = ["2026-10-13": -5]; assert(!bad.isValid)
            bad.water = ["yesterday": 100]; assert(!bad.isValid)
            bad = AppData(); bad.waterTarget = 50; assert(!bad.isValid)
            bad = AppData(); bad.waterGlass = .infinity; assert(!bad.isValid)
            let store = AppStore(url: root.appending(path: "water.json"), catalogURL: nil, legacyURL: nil, everydayURL: nil)
            assert(store.addWater(250, on: day(1)) && store.addWater(250, on: day(1)) && Water.total(store.data, on: dayKey(day(1))) == 500)
            assert(!store.addWater(0) && !store.addWater(.nan) && !store.addWater(50_000))
            assert(store.setWater(target: 2500, glass: 300) && Water.target(store.data) == 2500 && Water.glass(store.data) == 300)
            assert(!store.setWater(target: 10, glass: 300) && Water.target(store.data) == 2500)
            // A merge keeps the larger total for a day, fills a missing target, and a copy from before water existed loads.
            var mine = AppData(); mine.water = ["2026-10-13": 500, "2026-10-12": 1500]
            var theirs = AppData(); theirs.water = ["2026-10-13": 750]; theirs.waterTarget = 3000
            let combined = AppStore.merged(mine, theirs)
            assert(combined.water == ["2026-10-13": 750, "2026-10-12": 1500] && combined.waterTarget == 3000)
            assert(AppStore.merged(theirs, mine).water?["2026-10-13"] == 750)
            let copy = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(combined))
            assert(copy.water == combined.water && copy.waterTarget == 3000 && copy.isValid)
            var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppData())) as! [String: Any]
            for key in ["water", "waterTarget", "waterGlass", "measurements"] { legacyJSON[key] = nil }
            let legacy = try JSONDecoder().decode(AppData.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
            assert(legacy.water == nil && legacy.measurementLog.isEmpty && legacy.isValid)
            assert(Water.date(of: "2026-10-13") != nil && Water.date(of: "nope") == nil)
            // Siri and Shortcuts: a glass is your glass, a bottle 500 mL, a litre a litre, and the answers read naturally.
            assert(Water.millilitres(.glass, glass: 300) == 300 && Water.millilitres(.bottle, glass: 300) == 500 && Water.millilitres(.litre, glass: 300) == 1000)
            assert(Water.Size(rawValue: "glass") == .glass && Water.singleLimit == 5000)
            assert(Water.loggedAnswer(added: 250, total: 1250, target: 2000) == "Logged 250 mL of water. 1.25 L of 2 L today.")
            assert(Water.loggedAnswer(added: 500, total: 2250, target: 2000) == "Logged 500 mL of water. 2.25 L of 2 L today. That's your 2 L target.")
            assert(Water.todayAnswer(total: 0, target: 2000) == "You haven't logged any water today. Your target is 2 L.")
            assert(Water.todayAnswer(total: 1250, target: 2000) == "You've had 1.25 L of water today, 750 mL to go.")
            assert(Water.todayAnswer(total: 2000, target: 2000) == "You've had 2 L of water today, which reaches your 2 L target.")
        }

        // Body measurements: one reading a day, changes against the last and first, sites in order, and sync merges by ID.
        do {
            let entries = [
                BodyMeasurement(date: day(0), values: ["waist": 90, "hips": 100]),
                BodyMeasurement(date: day(7), values: ["waist": 88.5]),
                BodyMeasurement(date: day(14).addingTimeInterval(60), values: ["waist": 87.9]),
                BodyMeasurement(date: day(14), values: ["waist": 91, "wrist": 17]),   // earlier the same day: the later one wins
            ]
            let waist = BodyMeasurements.readings(entries, site: "waist", calendar: calendar)
            assert(waist.map(\.cm) == [90, 88.5, 87.9])
            let change = BodyMeasurements.change(waist)!
            assert(abs(change.sinceLast! + 0.6) < 0.0001 && abs(change.sinceFirst! + 2.1) < 0.0001 && change.latest.cm == 87.9)
            assert(BodyMeasurements.change(BodyMeasurements.readings(entries, site: "hips", calendar: calendar))!.sinceLast == nil)
            assert(BodyMeasurements.change([]) == nil)
            assert(BodyMeasurements.sites(in: entries) == ["waist", "hips", "wrist"])
            assert(BodyMeasurements.title("arm") == "Upper arm" && BodyMeasurements.title("wrist") == "Wrist")
            assert(BodyMeasurements.signed(-3.54) == "−3.5 cm" && BodyMeasurements.signed(1) == "+1 cm" && BodyMeasurements.signed(0.01) == "no change")
            assert(BodyMeasurement(date: day(0), values: ["waist": 90]).isValid && BodyMeasurement(date: day(0), values: ["future": 20]).isValid)
            assert(!BodyMeasurement(date: day(0), values: [:]).isValid && !BodyMeasurement(date: day(0), values: ["waist": 2]).isValid)
            var data = AppData(); data.measurements = entries
            assert(data.isValid)
            data.measurements?.append(BodyMeasurement(date: day(1), values: ["waist": .nan])); assert(!data.isValid)
            var one = AppData(); one.measurements = [entries[0]]
            var two = AppData(); var edited = entries[0]; edited.values["waist"] = 89; two.measurements = [edited, entries[1]]
            let merged = AppStore.merged(one, two).measurementLog
            assert(merged.count == 2 && merged.first { $0.id == entries[0].id }?.values["waist"] == 89)
            let decoded = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(data.measurements == nil ? AppData() : { var d = AppData(); d.measurements = entries; return d }()))
            assert(decoded.measurementLog == entries && decoded.isValid)
        }

        // Progress photos: files on this device only, shrunk and upright, and deleted with everything else.
        do {
            func picture(_ width: Int, _ height: Int) -> Data {
                let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                let output = NSMutableData()
                let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
                CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
                return output as Data
            }
            func size(of data: Data) -> (Int, Int) {
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
                return (image.width, image.height)
            }
            let files = ProgressPhotoFiles(directory: root.appending(path: "photos"))
            assert(files.load().isEmpty)
            let big = ProgressPhotoFiles.prepared(picture(3200, 2400))!
            assert(size(of: big) == (1600, 1200) && big.count < picture(3200, 2400).count)
            assert(size(of: ProgressPhotoFiles.prepared(picture(800, 600))!).0 <= 1600)
            assert(ProgressPhotoFiles.prepared(Data("not a picture".utf8)) == nil)
            let first = try files.add(jpeg: big, date: day(0), note: "Start")
            let second = try files.add(jpeg: big, date: day(14))
            assert(files.load().map(\.id) == [second.id, first.id] && files.load().last?.note == "Start")
            assert(files.thumbnail(first.id, longestSide: 200).map { max($0.width, $0.height) } == 200)
            assert(files.data(first.id) == big)
            var renamed = first; renamed.note = nil; renamed.date = day(3)
            try files.update(renamed)
            assert(files.load().map(\.id) == [second.id, first.id] && files.load().last?.note == nil && files.load().last?.date == day(3))
            try files.remove(first.id)
            assert(files.load().map(\.id) == [second.id] && files.data(first.id) == nil)
            // A record whose picture is gone is dropped rather than shown empty.
            try FileManager.default.removeItem(at: root.appending(path: "photos/\(second.id.uuidString).jpg"))
            assert(files.load().isEmpty)
            let third = try files.add(jpeg: big, date: day(1))
            files.removeAll()
            assert(files.load().isEmpty && files.data(third.id) == nil)
            // Photos aren't part of the app data, so they can't reach backups, iCloud or exports.
            let json = String(decoding: try JSONEncoder().encode(AppData()), as: UTF8.self)
            assert(!json.lowercased().contains("photo"))
        }

        // Weekly review: fibre and sodium count only days where every food lists them, against a target or the guide.
        do {
            let oats = Food(id: "oats", name: "Oats", kj: 1200, cal: 300, p: 10, nut: ["fibre": 10, "sodium": 100])
            let sausage = Food(id: "sausage", name: "Sausage roll", kj: 1500, cal: 360, p: 12, nut: ["fibre": 2, "sodium": 1500])
            let plainToast = Food(id: "plain", name: "Plain toast", kj: 1000, cal: 240, p: 8)   // lists neither
            var data = AppData()
            data.logs[dayKey(day(0))] = [LogEntry(name: "Mix", items: [Portion(food: oats), Portion(food: sausage)], time: day(0))]               // 12 g, 1,600 mg
            data.logs[dayKey(day(1))] = [LogEntry(name: "Mix", items: [Portion(food: oats, quantity: 2), Portion(food: sausage, quantity: 2)], time: day(1))]   // 24 g, 3,200 mg
            data.logs[dayKey(day(2))] = [LogEntry(name: "Mix", items: [Portion(food: oats), Portion(food: plainToast)], time: day(2))]            // gaps: not counted
            let review = WeeklyReview.make(data, goals: Goals(), ending: day(6), calendar: calendar)
            assert(review.loggedDays == 3 && review.fibre.countedDays == 2 && review.sodium.countedDays == 2)
            assert(review.fibre.average == 18 && review.sodium.average == 2400)
            assert(review.fibre.targetIsGuide && review.fibre.target == 25 && review.fibre.isMinimum && review.fibre.daysMet == 0)
            assert(review.sodium.targetIsGuide && review.sodium.target == 2000 && !review.sodium.isMinimum && review.sodium.daysMet == 1)
            assert(!review.fibre.onTarget && !review.sodium.onTarget)
            assert(review.nudges.count == 2 && review.nudges[0].contains("18 g") && review.nudges[0].contains("guide of 25 g"))
            assert(review.nudges[1].contains("2,400 mg") && review.nudges[1].contains("over it on 1 of 2 days"))
            // Your own targets replace the guide, and being close reads differently from being far off.
            var goals = Goals(); goals.values["fibre"] = 20; goals.values["sodium"] = 3000
            let own = WeeklyReview.make(data, goals: goals, ending: day(6), calendar: calendar)
            assert(!own.fibre.targetIsGuide && own.fibre.target == 20 && own.fibre.isMinimum && own.fibre.daysMet == 1)
            assert(own.nudges[0].contains("a little under your 20 g target") && own.sodium.onTarget && own.nudges[1].contains("within your 3,000 mg target"))
            // One counted day, or none, says nothing.
            var single = AppData(); single.logs[dayKey(day(0))] = data.logs[dayKey(day(0))]
            assert(WeeklyReview.make(single, goals: Goals(), ending: day(6), calendar: calendar).nudges.isEmpty)
            var gaps = AppData(); gaps.logs[dayKey(day(0))] = [LogEntry(name: "Toast", items: [Portion(food: plainToast)], time: day(0))]
            let none = WeeklyReview.make(gaps, goals: Goals(), ending: day(6), calendar: calendar)
            assert(none.fibre.average == nil && none.sodium.average == nil && none.nudges.isEmpty)
        }

        // What fits what's left: your own foods first, a restaurant you use, everyday foods to fill, and nothing when there's nothing to close.
        do {
            let shake = Food(id: "shake", name: "Protein shake", kj: 670, cal: 160, p: 30)
            let yoghurt = Food(id: "yoghurt", name: "Greek yoghurt", kj: 500, cal: 120, p: 17)
            let bar = Food(id: "bar", name: "Muesli bar", kj: 630, cal: 150, p: 3)
            let feast = Food(id: "feast", name: "Burger feast", kj: 2900, cal: 700, p: 45)
            let noonNow = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day(5))!
            let eveningNow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day(5))!
            var data = AppData()
            data.logs[dayKey(day(4))] = [LogEntry(name: "Snacks", items: [shake, yoghurt, bar, feast].map { Portion(food: $0) }, time: day(4), mealTime: .snacks)]
            data.logs[dayKey(day(5))] = [LogEntry(name: "Toast", items: [Portion(food: toast)], time: day(5), mealTime: .breakfast)]
            let names = ["kfc": "KFC"]
            let found = Assistant.suggestions(data, goals: Goals(), pinned: [], everyday: everyday, restaurantFoods: [], chainNames: names, now: noonNow, calendar: calendar)
            assert(found.count == 3)
            // Protein per calorie decides it: the shake, then the yoghurt. The bar has too little protein; the feast doesn't fit a meal.
            assert(found.map(\.name).prefix(2) == ["Protein shake", "Greek yoghurt"])
            assert(!found.map(\.name).contains("Muesli bar") && !found.map(\.name).contains("Burger feast"))
            // One meal's worth: no suggestion is bigger than a typical meal, however much is left in the day.
            assert(found.allSatisfy { $0.calories <= Goals().mealCal })
            assert(found[2].source == .everyday && found[2].calories <= 500 && !found[2].name.lowercased().contains("raw"))
            assert(found.allSatisfy { $0.calories <= 500 && $0.protein >= 10 && !$0.items.isEmpty })
            // After 4 pm fewer meals are left to come, so a meal can be half as big again: 700 Cal fits then, not at noon.
            let late = Assistant.suggestions(data, goals: Goals(), pinned: [], everyday: [], restaurantFoods: [], chainNames: names, now: eveningNow, calendar: calendar)
            assert(late.map(\.name).contains("Burger feast"))
            // A pinned food is labelled as pinned and listed once.
            let pinnedFirst = Assistant.suggestions(data, goals: Goals(), pinned: [yoghurt], everyday: [], restaurantFoods: [], chainNames: names, now: noonNow, calendar: calendar)
            assert(pinnedFirst.filter { $0.name == "Greek yoghurt" }.count == 1 && pinnedFirst.first { $0.name == "Greek yoghurt" }?.source == .pinned)
            // A saved meal is offered as the meal, with fresh item IDs.
            var withMeal = data; let chickenSalad = Food(id: "salad", name: "Chicken salad", kj: 1250, cal: 300, p: 40)
            withMeal.meals = [SavedMeal(name: "Chicken salad", items: [Portion(food: chickenSalad)])]
            let mealFound = Assistant.suggestions(withMeal, goals: Goals(), pinned: [], everyday: [], restaurantFoods: [], chainNames: names, now: noonNow, calendar: calendar)
            let offered = mealFound.first { $0.name == "Chicken salad" }
            assert(offered?.source == .savedMeal && offered?.items.first?.id != withMeal.meals[0].items[0].id)
            // The restaurant you've been logging most turns up as an order there.
            let kfcFood = catalog.foods.first { $0.chain == "kfc" && $0.cat == "main" }!
            var atKFC = data
            atKFC.logs[dayKey(day(3))] = [LogEntry(name: kfcFood.name, items: [Portion(food: kfcFood)], time: day(3), mealTime: .dinner)]
            assert(Assistant.usualChain(logs: atKFC.logs, now: noonNow, calendar: calendar) == "kfc")
            assert(Assistant.usualChain(logs: data.logs, now: noonNow, calendar: calendar) == nil)
            let restaurantFound = Assistant.suggestions(atKFC, goals: Goals(), pinned: [], everyday: everyday, restaurantFoods: catalog.foods, chainNames: names, now: noonNow, calendar: calendar)
            assert(restaurantFound.count == 3 && restaurantFound.contains { $0.source == .restaurant("KFC") })
            assert(restaurantFound.first { $0.source == .restaurant("KFC") }.map { $0.calories <= 500 && $0.protein >= 10 } == true)
            // Nothing when the protein target is met or the calories are used up.
            var proteinMet = data
            proteinMet.logs[dayKey(day(5))] = [LogEntry(name: "Lots", items: [Portion(food: Food(id: "lots", name: "Lots", kj: 4000, cal: 800, p: 160))], time: day(5))]
            assert(Assistant.suggestions(proteinMet, goals: Goals(), pinned: [], everyday: everyday, restaurantFoods: [], chainNames: names, now: noonNow, calendar: calendar).isEmpty)
            var caloriesUsed = data
            caloriesUsed.logs[dayKey(day(5))] = [LogEntry(name: "Big", items: [Portion(food: Food(id: "big", name: "Big", kj: 9200, cal: 2150, p: 20))], time: day(5))]
            assert(Assistant.suggestions(caloriesUsed, goals: Goals(), pinned: [], everyday: everyday, restaurantFoods: [], chainNames: names, now: noonNow, calendar: calendar).isEmpty)
            assert(Assistant.leftText(data, goals: Goals(), now: noonNow) == "142 g protein · 1,960 Cal")
            assert(Assistant.leftText(proteinMet, goals: Goals(), now: noonNow) == "1,400 Cal")
            var noTargets = Goals(); noTargets.values = [:]
            assert(Assistant.leftText(data, goals: noTargets, now: noonNow) == nil)
        }


        // Progress breakdown: averages over logged days, a macro split, meal times, contributors, water and weight change.
        do {
            let oats = Food(id: "oats", name: "Oats", kj: 1200, cal: 400, p: 20, c: 60, f: 10, nut: ["fibre": 8, "sodium": 100])
            let chicken = Food(id: "chicken", name: "Chicken wrap", kj: 2000, cal: 600, p: 40, c: 50, f: 20, nut: ["fibre": 4, "sodium": 1200])
            let mystery = Food(id: "mystery", name: "Mystery bowl", kj: 1000, cal: 240, p: 10, c: nil, f: nil)
            var data = AppData()
            data.logs[dayKey(day(0))] = [LogEntry(name: "Oats", items: [Portion(food: oats)], time: day(0), mealTime: .breakfast),
                                         LogEntry(name: "Wrap", items: [Portion(food: chicken)], time: day(0), mealTime: .lunch)]       // 1,000 Cal, 60 g
            data.logs[dayKey(day(1))] = [LogEntry(name: "Wrap", items: [Portion(food: chicken, quantity: 2)], time: day(1), mealTime: .dinner)]   // 1,200 Cal, 80 g
            data.logs[dayKey(day(3))] = [LogEntry(name: "Bowl", items: [Portion(food: mystery)], time: day(3))]                                   // 240 Cal, no carbs/fat
            data.water = [dayKey(day(0)): 1000, dayKey(day(1)): 2000]
            data.weights = [WeightEntry(date: day(-5), kg: 82), WeightEntry(date: day(2), kg: 81)]
            let result = ProgressBreakdown.make(data, goals: Goals(), days: 7, ending: day(6), calendar: calendar)
            assert(result.days == 7 && result.points.count == 7 && result.loggedDays == 3)
            assert(result.points[0].calories == 1000 && result.points[2].calories == nil && result.points[3].calories == 240)
            assert(abs(result.averageCalories! - 813.333) < 0.01 && result.calorieTarget == 2200 && result.calorieDays == 3 && result.proteinDays == 0)
            // Carbs and fat skip the day with gaps; fibre and sodium too, since that food lists neither.
            assert(result.carbs.countedDays == 2 && result.carbs.value == 105 && result.fat.value == 35)
            assert(result.fibre.countedDays == 2 && result.fibre.value == 10 && result.sodium.value == 1850)
            // 4 × 110 + ... : the split is of calories from the three macros, and says it's approximate.
            let share = result.share!
            assert(abs(share.protein + share.carbs + share.fat - 1) < 0.0001 && !result.shareComplete)
            assert(result.mealTimes.map(\.mealTime) == [.breakfast, .lunch, .dinner, nil])
            assert(abs(result.mealTimes[0].averageCalories - 400.0 / 3) < 0.01 && result.mealTimes.last?.title == "Unassigned")
            assert(result.topFoods.first?.name == "Chicken wrap" && result.topFoods.first?.servings == 3 && result.topFoods.first?.calories == 1800)
            assert(result.water.value == 1500 && result.water.countedDays == 2)
            assert(result.startTrend == 82 && result.endTrend.map { abs($0 - (82 + 0.0)) > 0 } == true && result.weightChange! < 0)
            // A longer range reaches further back; nothing logged gives empty averages, not zeros.
            assert(ProgressBreakdown.make(data, goals: Goals(), days: 30, ending: day(6), calendar: calendar).points.count == 30)
            let empty = ProgressBreakdown.make(AppData(), goals: Goals(), days: 30, ending: day(6), calendar: calendar)
            assert(empty.loggedDays == 0 && empty.averageCalories == nil && empty.share == nil && empty.topFoods.isEmpty && empty.weightChange == nil)
            // A day's own target is used for "on target", not today's.
            var strict = data; var tight = Goals(); tight.values["cal"] = 900
            strict.dayGoals[dayKey(day(0))] = tight
            assert(ProgressBreakdown.make(strict, goals: Goals(), days: 7, ending: day(6), calendar: calendar).calorieDays == 2)
        }

        print("App checks passed: catalogue, migration, persistence, backups, recipes, history, label parsing, finder, weight trend, quick log, search, Siri answers, reminders, weekly review, CSV export, menu updates, undo, pinned foods, the Log again widget, saving scans, late-night reminders, delivery, iCloud health rules, deleting all data, the policies, everyday foods, customised orders, photo and Visual Intelligence matching, widget goal colours, Premium access rules, Siri logging and editing saved and logged meals, water, measurements, progress photos, fibre and sodium nudges, the progress breakdown, what fits what's left and no prices (\(Date().timeIntervalSince(start).formatted())s).")
    }
}
