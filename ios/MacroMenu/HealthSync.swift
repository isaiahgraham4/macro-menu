import Foundation
import HealthKit

/// Apple Health: writes logged nutrition and weights, reads weight and active energy.
/// Every sample Leanr writes carries the ID of its log entry or weight, so edits and deletes replace exactly those samples.
@MainActor @Observable
final class HealthSync {
    static let enabledKey = "health.enabled"
    private static let entryKey = "LeanrEntryID"
    private static let weightKey = "LeanrWeightID"
    private static let ignoredKey = "health.ignoredWeights"

    private let health = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var enabled = UserDefaults.standard.bool(forKey: HealthSync.enabledKey) {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    /// Why the last connection attempt failed, to show the person.
    private(set) var lastError: String?
    private(set) var activeEnergyToday: Double?
    /// Average daily active energy over the last two weeks, counting days with any recorded.
    private(set) var averageActiveEnergy: Double?
    weak var store: AppStore?
    /// Health updates run one after another, so a quick log-then-undo can't leave a stray sample behind.
    private var queue: Task<Void, Never>?

    /// Leanr nutrient keys and their Health types and units. Trans fat has no Health type.
    private static let nutrients: [(key: String, type: HKQuantityTypeIdentifier, unit: HKUnit)] = [
        ("cal", .dietaryEnergyConsumed, .kilocalorie()), ("p", .dietaryProtein, .gram()),
        ("c", .dietaryCarbohydrates, .gram()), ("f", .dietaryFatTotal, .gram()),
        ("sat", .dietaryFatSaturated, .gram()), ("sugar", .dietarySugar, .gram()), ("fibre", .dietaryFiber, .gram()),
        ("sodium", .dietarySodium, .gramUnit(with: .milli)), ("potassium", .dietaryPotassium, .gramUnit(with: .milli)),
        ("calcium", .dietaryCalcium, .gramUnit(with: .milli)), ("iron", .dietaryIron, .gramUnit(with: .milli)),
        ("chol", .dietaryCholesterol, .gramUnit(with: .milli)), ("caffeine", .dietaryCaffeine, .gramUnit(with: .milli))]
    private static var nutritionTypes: [HKQuantityType] { nutrients.map { HKQuantityType($0.type) } }
    private static let bodyMass = HKQuantityType(.bodyMass)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    private static let food = HKCorrelationType(.food)

    /// Asks for access, then copies the last week's log to Health and reads weights and activity.
    func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await health.requestAuthorization(toShare: Set(Self.nutritionTypes + [Self.bodyMass]),
                                                  read: [Self.bodyMass, Self.activeEnergy])
        } catch { lastError = error.localizedDescription; return false }
        lastError = nil
        enabled = true
        if let store {
            let start = dayKey(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
            for (day, entries) in store.data.logs where day >= start {
                for entry in entries { await replace(entry, day: day) }
            }
            for weight in store.data.weightLog where weight.healthID == nil { await replace(weight) }
        }
        await refresh()
        return true
    }

    func disconnect() {
        enabled = false; activeEnergyToday = nil; averageActiveEnergy = nil
    }

    /// Mirrors a change in Leanr: removed or edited entries and weights come out of Health, new versions go in.
    func follow(old: AppData, new: AppData) {
        guard enabled else { return }
        let before = Self.entries(old), after = Self.entries(new)
        let beforeWeights = Dictionary(old.weightLog.filter { $0.healthID == nil }.map { ($0.id, $0) }) { a, _ in a }
        let afterWeights = Dictionary(new.weightLog.filter { $0.healthID == nil }.map { ($0.id, $0) }) { a, _ in a }
        // Weights imported from Health that you delete in Leanr stay hidden rather than reappearing on the next import.
        let hidden = old.weightLog.compactMap(\.healthID).filter { id in !new.weightLog.contains { $0.healthID == id } }
        if !hidden.isEmpty {
            let ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? []).union(hidden.map(\.uuidString))
            UserDefaults.standard.set(Array(ignored), forKey: Self.ignoredKey)
        }
        queue = Task { [previous = queue] in
            await previous?.value
            for (id, entry) in after where before[id]?.entry != entry.entry { await replace(entry.entry, day: entry.day) }
            for id in before.keys where after[id] == nil { await deleteEntry(id) }
            for (id, weight) in afterWeights where beforeWeights[id] != weight { await replace(weight) }
            for id in beforeWeights.keys where afterWeights[id] == nil { await deleteWeight(id) }
        }
    }

    /// Reads today's and recent active energy, and imports weights recorded in Health by other apps and devices.
    func refresh() async {
        guard enabled else { return }
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date())
        let todayQuery = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: Self.activeEnergy, predicate: HKQuery.predicateForSamples(withStart: today, end: nil)),
            options: .cumulativeSum)
        activeEnergyToday = try? await todayQuery.result(for: health)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        if let start = calendar.date(byAdding: .day, value: -14, to: today) {
            let recent = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: Self.activeEnergy, predicate: HKQuery.predicateForSamples(withStart: start, end: today)),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            if let collection = try? await recent.result(for: health) {
                let days = collection.statistics().compactMap { $0.sumQuantity()?.doubleValue(for: .kilocalorie()) }.filter { $0 > 0 }
                averageActiveEnergy = days.count >= 3 ? days.reduce(0, +) / Double(days.count) : nil
            }
        }
        await importWeights()
    }

    private func importWeights() async {
        guard let store, let since = Calendar.current.date(byAdding: .year, value: -1, to: Date()) else { return }
        let query = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: Self.bodyMass, predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await query.result(for: health) else { return }
        let ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? [])
        let known = Set(store.data.weightLog.compactMap(\.healthID))
        let fresh = samples.filter { sample in
            sample.metadata?[Self.weightKey] == nil && !known.contains(sample.uuid) && !ignored.contains(sample.uuid.uuidString)
        }.map { WeightEntry(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), healthID: $0.uuid) }
            .filter(\.isValid)
        guard !fresh.isEmpty else { return }
        store.change { $0.weights = $0.weightLog + fresh }
    }

    private static func entries(_ data: AppData) -> [UUID: (entry: LogEntry, day: String)] {
        var result: [UUID: (entry: LogEntry, day: String)] = [:]
        for (day, entries) in data.logs { for entry in entries { result[entry.id] = (entry, day) } }
        return result
    }

    /// Logged time on the logged day; entries added to another day are placed at noon on that day.
    private static func sampleDate(_ entry: LogEntry, day: String) -> Date {
        if dayKey(entry.time) == day { return entry.time }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.date(from: day) ?? entry.time
        return Calendar.current.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    private func replace(_ entry: LogEntry, day: String) async {
        await deleteEntry(entry.id)
        let total = Nutrition(entry.items), date = Self.sampleDate(entry, day: day)
        let metadata: [String: Any] = [HKMetadataKeyFoodType: entry.name, Self.entryKey: entry.id.uuidString]
        let samples = Self.nutrients.compactMap { nutrient -> HKQuantitySample? in
            if nutrient.key == "c" && total.missingCarbs || nutrient.key == "f" && total.missingFat { return nil }
            let value = ["cal", "p", "c", "f"].contains(nutrient.key) ? total.value(nutrient.key) : total.nut[nutrient.key]
            guard let value, value > 0, !total.partial.contains(nutrient.key) else { return nil }
            return HKQuantitySample(type: HKQuantityType(nutrient.type), quantity: HKQuantity(unit: nutrient.unit, doubleValue: value),
                                    start: date, end: date, metadata: metadata)
        }
        guard !samples.isEmpty else { return }
        let meal = HKCorrelation(type: Self.food, start: date, end: date, objects: Set(samples), metadata: metadata)
        try? await health.save(meal)
    }

    private func deleteEntry(_ id: UUID) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.entryKey, allowedValues: [id.uuidString])
        for type in Self.nutritionTypes { _ = try? await health.deleteObjects(of: type, predicate: predicate) }
        _ = try? await health.deleteObjects(of: Self.food, predicate: predicate)
    }

    private func replace(_ weight: WeightEntry) async {
        await deleteWeight(weight.id)
        let sample = HKQuantitySample(type: Self.bodyMass, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weight.kg),
                                      start: weight.date, end: weight.date, metadata: [Self.weightKey: weight.id.uuidString])
        try? await health.save(sample)
    }

    private func deleteWeight(_ id: UUID) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.weightKey, allowedValues: [id.uuidString])
        _ = try? await health.deleteObjects(of: Self.bodyMass, predicate: predicate)
    }
}
