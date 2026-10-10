import Foundation
import Observation

@MainActor @Observable
final class AppStore {
    private(set) var data = AppData()
    private(set) var catalog = MenuCatalog(chains: [], foods: [])
    /// Everyday foods (bananas, chicken breast, rice...), bundled with the app.
    private(set) var everyday: [Food] = []
    private(set) var loadError: String?
    var errorMessage: String?
    var notice: String?
    /// The state before the last undoable change, offered briefly as "Undo".
    struct UndoStep: Identifiable { let id = UUID(); var label: String; var snapshot: AppData }
    private(set) var undo: UndoStep?
    /// Called after local changes (not iCloud updates) so Apple Health can follow the log and weights.
    var logsChanged: ((_ old: AppData, _ new: AppData) -> Void)?
    /// Called after every local save, so iCloud sync knows there's something to upload.
    var saved: (() -> Void)?
    /// Called after data from another device is taken in.
    var synced: (() -> Void)?
    private let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "MacroMenu/app-state.json"), catalogURL: URL? = Bundle.main.url(forResource: "MenuData", withExtension: "json"), legacyURL: URL? = URL.applicationSupportDirectory.appending(path: "MacroMenu/foods.json"),
         everydayURL: URL? = Bundle.main.url(forResource: "GenericFoods", withExtension: "json")) {
        self.url = url
        if let everydayURL, let foods = try? JSONDecoder().decode([Food].self, from: Data(contentsOf: everydayURL)) {
            everyday = foods.filter { $0.isValid && $0.isEveryday }
        }
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
    var foods: [Food] { catalog.foods + everyday + data.foods }
    /// Foods that make up an order: restaurant menus and your own foods, without everyday foods.
    var orderFoods: [Food] { catalog.foods + data.foods }
    /// Switches to a newer restaurant menu. Logged meals keep the figures they were logged with.
    func useMenu(_ menu: MenuCatalog) { catalog = menu }
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
    func chain(_ id: String) -> Chain? { catalog.chains.first { $0.id == id } }
    /// When the restaurant menu in use was published.
    var menuDate: Date? {
        let precise = ISO8601DateFormatter(); precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let text = catalog.published else { return nil }
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
    func chainName(_ id: String) -> String {
        if id == Food.everyday { return "Everyday foods" }
        return catalog.chains.first { $0.id == id }?.name ?? "My foods"
    }
    private func write(_ updated: AppData) throws {
        guard loadError == nil, updated.isValid else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    /// Saves a change. With `undo`, the banner offers to reverse it; any other change clears that offer.
    @discardableResult func change(undo label: String? = nil, _ action: (inout AppData) -> Void) -> Bool {
        var updated = data; action(&updated)
        let old = data
        do { try write(updated) } catch { errorMessage = "Couldn’t save: \(error.localizedDescription)"; return false }
        data = updated
        undo = label.map { UndoStep(label: $0, snapshot: old) }
        refreshWidgets()
        logsChanged?(old, updated)
        saved?()
        return true
    }
    func undoLast() {
        guard let step = undo else { return }
        let old = data
        do { try write(step.snapshot) } catch { errorMessage = "Couldn’t undo: \(error.localizedDescription)"; return }
        data = step.snapshot; undo = nil; notice = nil
        refreshWidgets()
        logsChanged?(old, data)
        saved?()
    }
    /// Starts again with nothing saved: no foods, log, weights, targets or meal. Can't be undone.
    /// iCloud and Apple Health aren't touched here (see `DataDeletion`).
    @discardableResult func eraseEverything() -> Bool {
        let fresh = AppData()
        // Also works when the saved file couldn't be read: that file is replaced too.
        loadError = nil
        do { try write(fresh) } catch { errorMessage = "Couldn’t delete your data: \(error.localizedDescription)"; return false }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appending(path: "foods.json"))
        data = fresh; undo = nil; notice = nil
        refreshWidgets()
        return true
    }
    func dismissUndo(_ id: UndoStep.ID) { if undo?.id == id { undo = nil } }
    /// Takes data synced from another device. Doesn't touch Apple Health or trigger another upload.
    @discardableResult func applySynced(_ incoming: AppData) -> Bool {
        guard incoming.isValid else { return false }
        do { try write(incoming) } catch { return false }
        data = incoming; undo = nil; refreshWidgets()
        synced?()
        return true
    }
    @discardableResult func saveFood(_ food: Food) -> Bool {
        change { state in
            if let i = state.foods.firstIndex(where: { $0.id == food.id }) { state.foods[i] = food }
            else { state.foods.append(food) }
        }
    }
    /// Keeps a logged food (usually a scanned product) in My foods, so the "+" there or scanning it again logs it straight away.
    /// A food that already has this barcode is updated rather than added twice. Returns the saved food.
    @discardableResult func saveToMyFoods(_ food: Food) -> Food? {
        var value = food; value.chain = "mine"; value.modifiers = nil
        // One decimal place, like foods saved from the editor.
        value.cal = value.cal.tenth; value.kj = value.cal * 4.184; value.p = value.p.tenth
        value.c = value.c?.tenth; value.f = value.f?.tenth; value.nut = value.nut?.mapValues(\.tenth)
        if let code = food.barcode, let existing = BarcodeLookup.match(code, in: data.foods) { value.id = existing.id }
        return saveFood(value) ? value : nil
    }
    static let pinLimit = 8
    /// Pinned foods with today's figures where the item is still on the menu or in My foods.
    var pinnedFoods: [Food] {
        let pins = data.pinned ?? []
        guard !pins.isEmpty else { return [] }
        let ids = Set(pins.map(\.id))
        let current = Dictionary(foods.filter { ids.contains($0.id) }.map { ($0.id, $0) }) { a, _ in a }
        return pins.map { current[$0.id] ?? $0 }
    }
    func isPinned(_ food: Food) -> Bool { (data.pinned ?? []).contains { $0.id == food.id } }
    /// Pins or unpins a food. Pins past the limit are refused with a notice rather than pushing an older one out.
    func togglePin(_ food: Food) {
        if isPinned(food) {
            if change({ $0.pinned?.removeAll { $0.id == food.id } }) { notice = "Unpinned \(food.name)" }
        } else if (data.pinned ?? []).count >= Self.pinLimit {
            notice = "You can pin up to \(Self.pinLimit) foods. Unpin one first."
        } else {
            var copy = food; copy.modifiers = nil
            if change({ $0.pinned = ($0.pinned ?? []) + [copy] }) { notice = "Pinned \(food.name)" }
        }
    }
    /// Saves an edited logged meal, moving it to `newDay` when its date changed. Undo puts the old version back.
    @discardableResult func updateLog(_ entry: LogEntry, day: String, to newDay: String) -> Bool {
        guard entry.isValid, data.logs[day]?.contains(where: { $0.id == entry.id }) == true else { return false }
        let currentGoals = goals
        return change(undo: "Edited \(entry.name)") { state in
            if day == newDay, let i = state.logs[day]?.firstIndex(where: { $0.id == entry.id }) {
                state.logs[day]?[i] = entry
            } else {
                state.logs[day]?.removeAll { $0.id == entry.id }
                state.logs[newDay, default: []].append(entry)
                if state.dayGoals[newDay] == nil { state.dayGoals[newDay] = currentGoals }
            }
        }
    }
    /// Saves changes to a saved meal (its name and items). Undo puts the old version back.
    @discardableResult func updateMeal(_ meal: SavedMeal) -> Bool {
        guard meal.isValid, data.meals.contains(where: { $0.id == meal.id }) else { return false }
        return change(undo: "Edited \(meal.name)") { state in
            if let i = state.meals.firstIndex(where: { $0.id == meal.id }) { state.meals[i] = meal }
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
        return change(undo: "Logged \(name)") {
            $0.logs[key, default: []].append(LogEntry(name: name, items: items, mealTime: mealTime))
            if $0.dayGoals[key] == nil { $0.dayGoals[key] = currentGoals }
            if clearTray { $0.tray = [] }
        }
    }
    /// Logs straight to today, under the meal time that fits the clock unless one is given.
    /// With `yesterday`, it goes to the day before instead, for a meal that was forgotten.
    @discardableResult func logNow(_ items: [Portion], name: String, mealTime: MealTime = .suggested(), yesterday: Bool = false) -> Bool {
        let date = yesterday ? Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() : Date()
        guard log(QuickLog.copies(items), name: name, date: date, mealTime: mealTime) else { return false }
        notice = "Logged to \(yesterday ? "yesterday’s " : "")\(mealTime.title.lowercased())"
        return true
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
        return change { state in state = Self.merged(state, backup) }
    }
    /// Everything in `current` plus `incoming`; entries with the same ID take the incoming version.
    static func merged(_ current: AppData, _ backup: AppData) -> AppData {
        var state = current
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
        if let pins = backup.pinned {
            var merged = state.pinned ?? []
            for pin in pins where !merged.contains(where: { $0.id == pin.id }) { merged.append(pin) }
            state.pinned = Array(merged.prefix(pinLimit))
        }
        if state.tray.isEmpty { state.tray = backup.tray }
        if !backup.weightLog.isEmpty {
            var weights = state.weightLog
            for weight in backup.weightLog {
                if let i = weights.firstIndex(where: { $0.id == weight.id }) { weights[i] = weight } else { weights.append(weight) }
            }
            state.weights = weights
        }
        return state
    }
}
