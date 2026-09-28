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
    func refreshWidgets() {
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
                }
                return
            }
            var snapshot = data.widgetCalories
            snapshot.accent = AppAccent.resolved(UserDefaults.standard.string(forKey: AppAccent.storageKey) ?? AppAccent.standard.rawValue).rawValue
            snapshot.premiumUnlocked = Premium.isUnlocked
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
        } catch {
            Logger(subsystem: "com.isaiahgraham.MacroMenu", category: "Widgets")
                .error("Couldn't share calorie totals: \(error.localizedDescription)")
        }
        #endif
    }
}
