import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    private(set) var data = AppData()
    private(set) var catalog = MenuCatalog(chains: [], foods: [])
    private(set) var loadError: String?
    var errorMessage: String?
    var notice: String?
    private let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "MacroMenu/app-state.json"), catalogURL: URL? = Bundle.main.url(forResource: "MenuData", withExtension: "json"), legacyURL: URL? = URL.applicationSupportDirectory.appending(path: "MacroMenu/foods.json")) {
        self.url = url
        if let catalogURL {
            do { catalog = try JSONDecoder().decode(MenuCatalog.self, from: Data(contentsOf: catalogURL)) }
            catch { errorMessage = "Could not load restaurant menu: \(error.localizedDescription)" }
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let loaded = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: url))
                guard loaded.isValid else { throw CocoaError(.fileReadCorruptFile) }
                data = loaded
            } else if let legacyURL, FileManager.default.fileExists(atPath: legacyURL.path) {
                data.foods = try FoodBackup.decode(Data(contentsOf: legacyURL)).foods.map(Food.legacy)
                try write(data)
            }
        } catch { loadError = "Saved data could not be read. The original file has been preserved. \(error.localizedDescription)" }
        refreshWidgets()
    }
    var foods: [Food] { catalog.foods + data.foods }
    var goals: Goals { data.goalSets.first { $0.id == data.activeGoal } ?? data.goalSets[0] }
    @discardableResult func applyEstimatedTargets(_ values: [String: Double]) -> Bool {
        let activeID = goals.id
        return change { state in
            guard let index = state.goalSets.firstIndex(where: { $0.id == activeID }) else { return }
            state.goalSets[index].values.merge(values) { _, new in new }
            state.activeGoal = activeID
            state.dayGoals[dayKey(Date())] = state.goalSets[index]
        }
    }
    func chainName(_ id: String) -> String { catalog.chains.first { $0.id == id }?.name ?? "My foods" }
    private func write(_ updated: AppData) throws {
        guard loadError == nil, updated.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    @discardableResult func change(_ action: (inout AppData) -> Void) -> Bool {
        var updated = data; action(&updated)
        do { try write(updated); data = updated; refreshWidgets(); return true }
        catch { errorMessage = "Couldn’t save: \(error.localizedDescription)"; return false }
    }
    @discardableResult func saveFood(_ food: Food) -> Bool {
        change { state in
            if let i = state.foods.firstIndex(where: { $0.id == food.id }) { state.foods[i] = food }
            else { state.foods.append(food) }
        }
    }
    func add(_ items: [Portion]) {
        if change({ state in
            for item in items {
                if let i = state.tray.firstIndex(where: { $0.food == item.food }) { state.tray[i].quantity += item.quantity }
                else { var fresh = item; fresh.id = UUID(); state.tray.append(fresh) }
            }
        }) { notice = "Added to your meal" }
    }
    @discardableResult func log(_ items: [Portion], name: String, date: Date, clearTray: Bool = false, mealTime: MealTime? = nil) -> Bool {
        let key = dayKey(date), currentGoals = goals
        return change {
            $0.logs[key, default: []].append(LogEntry(name: name, items: items, mealTime: mealTime))
            if $0.dayGoals[key] == nil { $0.dayGoals[key] = currentGoals }
            if clearTray { $0.tray = [] }
        }
    }
    func export() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(data)
    }
    func decodeBackup(_ bytes: Data) throws -> AppData {
        if let current = try? JSONDecoder().decode(AppData.self, from: bytes), current.isValid { return current }
        if let legacy = try? FoodBackup.decode(bytes) { var result = AppData(); result.foods = legacy.foods.map(Food.legacy); result.goalSets = data.goalSets; return result }
        return try WebBackup.decode(bytes, catalog: catalog)
    }
    func merge(_ backup: AppData) -> Bool {
        guard backup.isValid else { errorMessage = "This backup is invalid."; return false }
        return change { state in
            for food in backup.foods {
                if let i = state.foods.firstIndex(where: { $0.id == food.id }) { state.foods[i] = food }
                else { state.foods.append(food) }
            }
            for meal in backup.meals {
                if let i = state.meals.firstIndex(where: { $0.id == meal.id }) { state.meals[i] = meal }
                else { state.meals.append(meal) }
            }
            for (day, entries) in backup.logs {
                for entry in entries {
                    if let i = state.logs[day]?.firstIndex(where: { $0.id == entry.id }) { state.logs[day]?[i] = entry }
                    else { state.logs[day, default: []].append(entry) }
                }
            }
            for goal in backup.goalSets {
                if let i = state.goalSets.firstIndex(where: { $0.id == goal.id }) { state.goalSets[i] = goal }
                else { state.goalSets.append(goal) }
            }
            state.dayGoals.merge(backup.dayGoals) { _, incoming in incoming }
            if state.tray.isEmpty { state.tray = backup.tray }
        }
    }
}
