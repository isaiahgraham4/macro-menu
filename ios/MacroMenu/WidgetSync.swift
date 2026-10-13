import Foundation
#if os(iOS)
import WidgetKit
import OSLog
#endif

extension AppData {
    var widgetCalories: WidgetCalories {
        let goal = goalSets.first { $0.id == activeGoal } ?? goalSets.first
        var snapshot = WidgetCalories(target: goal?.values["cal"], dailyCalories: logs.mapValues {
            Nutrition($0.flatMap(\.items)).cal
        })
        let targets = nutrientNames.compactMap { nutrient -> WidgetNutrientTarget? in
            guard nutrient.key != "cal", let target = goal?.values[nutrient.key] else { return nil }
            return WidgetNutrientTarget(id: nutrient.key, name: nutrient.label, unit: nutrient.unit,
                                        target: target, minimum: goal?.minimums.contains(nutrient.key) == true)
        }
        snapshot.nutrientTargets = targets
        snapshot.trackedDays = logs.filter { !$0.value.flatMap(\.items).isEmpty }.keys.sorted()
        snapshot.dailyNutrients = logs.mapValues { entries in
            let total = Nutrition(entries.flatMap(\.items))
            let keys = Set(targets.map(\.id)).union(["p", "c", "f"])
            return Dictionary(uniqueKeysWithValues: keys.map { ($0, total.value($0)) })
        }
        snapshot.dailyPartialNutrients = logs.mapValues { entries in
            let total = Nutrition(entries.flatMap(\.items))
            let keys = Set(targets.map(\.id)).union(["p", "c", "f"])
            return keys.filter { key in
                !entries.isEmpty && (total.isPartial(key) || (!["p", "c", "f"].contains(key) && total.nut[key] == nil))
            }.sorted()
        }
        return snapshot
    }
}

extension AppStore {
    /// What the Log again widget can log: the usual meal for each meal time, then pinned foods.
    func quickLogOptions(now: Date = Date()) -> [WidgetQuickLog] {
        let today = data.logs[dayKey(now)] ?? []
        var options: [WidgetQuickLog] = MealTime.allCases.compactMap { meal in
            guard let usual = Assistant.usual(meal, logs: data.logs, now: now) else { return nil }
            let logged = today.contains { $0.mealTime == meal && $0.name == usual.name }
            return WidgetQuickLog(id: "usual:\(meal.rawValue)", name: usual.name, calories: Nutrition(usual.items).cal,
                                  mealTime: meal.rawValue, lastLogged: logged ? dayKey(now) : nil)
        }
        options += pinnedFoods.map { food in
            let logged = today.contains { $0.items.contains { $0.food.id == food.id } }
            return WidgetQuickLog(id: "pin:\(food.id)", name: food.name, calories: food.cal, lastLogged: logged ? dayKey(now) : nil)
        }
        return options
    }

    /// Today for Apple Watch: calories, protein and water against their targets, and the Log again widget's options.
    func watchSnapshot(now: Date = Date()) -> WatchSnapshot {
        let key = dayKey(now), eaten = Nutrition((data.logs[key] ?? []).flatMap(\.items))
        let target = data.dayGoals[key] ?? goals
        let options = quickLogOptions(now: now).map { option -> WatchSnapshot.Option in
            var protein = 0.0
            if option.isUsual, let meal = option.mealTime.flatMap(MealTime.init(rawValue:)), let usual = Assistant.usual(meal, logs: data.logs, now: now) {
                protein = Nutrition(usual.items).p
            } else if let food = pinnedFoods.first(where: { "pin:\($0.id)" == option.id }) {
                protein = food.p
            }
            return WatchSnapshot.Option(id: option.id, name: option.name, calories: option.calories, protein: protein, loggedToday: option.lastLogged == key)
        }
        return WatchSnapshot(day: key, calories: eaten.cal, calorieTarget: target.values["cal"], protein: eaten.p, proteinTarget: target.values["p"],
                             water: Water.total(data, on: key), waterTarget: Water.target(data), glass: Water.glass(data), options: options)
    }

    /// Logs one of the widget's options: a usual meal to its own meal time, or a serving of a pinned food to the meal time it is at `date`.
    /// The same thing logged in the last 10 seconds is taken as a double tap, since the widget can take a moment to show its tick.
    @discardableResult func logAgain(_ option: String, at date: Date = Date()) -> Bool {
        func justLogged(_ name: String) -> Bool {
            (data.logs[dayKey(date)] ?? []).contains { $0.name == name && abs($0.time.timeIntervalSince(date)) < 10 }
        }
        if option.hasPrefix("usual:"), let meal = MealTime(rawValue: String(option.dropFirst(6))),
           let usual = Assistant.usual(meal, logs: data.logs, now: date) {
            guard !justLogged(usual.name) else { return false }
            return log(QuickLog.copies(usual.items), name: usual.name, date: date, mealTime: meal)
        }
        if option.hasPrefix("pin:"), let food = pinnedFoods.first(where: { "pin:\($0.id)" == option }) {
            guard !justLogged(food.name) else { return false }
            return log([Portion(food: food)], name: food.name, date: date, mealTime: .suggested(at: date))
        }
        return false
    }

    /// Logs requests the widget had to queue, then clears them. Returns how many were logged.
    @discardableResult func applyQueuedQuickLogs(_ requests: [QuickLogQueue.Request]) -> Int {
        requests.filter { logAgain($0.option, at: $0.date) }.count
    }

    func refreshWidgets() {
        widgetsRefreshed?()
        #if os(iOS)
        guard let url = WidgetCalories.fileURL else { return }
        do {
            if loadError != nil {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.kind)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.premiumKind)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.macrosKind)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.streakKind)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.logAgainKind)
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.stepsKind)
                }
                return
            }
            var snapshot = data.widgetCalories
            snapshot.accent = AppAccent.resolved(UserDefaults.standard.string(forKey: AppAccent.storageKey) ?? AppAccent.standard.rawValue).rawValue
            snapshot.premiumUnlocked = Premium.isUnlocked
            snapshot.quickLogOptions = quickLogOptions()
            snapshot.steps = widgetSteps.isEmpty ? nil : widgetSteps
            snapshot.stepGoal = data.stepGoal ?? Steps.defaultGoal
            snapshot.macroColours = Premium.isUnlocked ? [
                "p": UserDefaults.standard.string(forKey: MacroColours.proteinKey) ?? "blue",
                "c": UserDefaults.standard.string(forKey: MacroColours.carbsKey) ?? "orange",
                "f": UserDefaults.standard.string(forKey: MacroColours.fatKey) ?? "red"
            ] : [:]
            guard snapshot.isValid, snapshot != WidgetCalories.read() else { return }
            try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.kind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.premiumKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.macrosKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.streakKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.logAgainKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetCalories.stepsKind)
        } catch {
            Logger(subsystem: "com.isaiahgraham.MacroMenu", category: "Widgets")
                .error("Couldn't share calorie totals: \(error.localizedDescription)")
        }
        #endif
    }
}
