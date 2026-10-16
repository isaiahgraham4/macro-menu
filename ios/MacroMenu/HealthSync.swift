import Foundation
import HealthKit

/// Apple Health: writes logged nutrition, water and weights, reads weight and active energy.
/// Every sample Leanr writes carries the ID of its log entry or weight, so edits and deletes replace exactly those samples.
@MainActor @Observable
final class HealthSync {
    static let enabledKey = "health.enabled"
    private static let entryKey = "LeanrEntryID"
    private static let weightKey = "LeanrWeightID"
    private static let ignoredKey = "health.ignoredWeights"
    private static let waterKey = "LeanrWaterDay"

    private let health = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private(set) var enabled = UserDefaults.standard.bool(forKey: HealthSync.enabledKey) {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    /// Why the last connection attempt failed, to show the person.
    private(set) var lastError: String?
    /// Active energy (calories burnt) by day (day key) for the last 90 days. Kept in memory only, like steps.
    private(set) var activeEnergy: [String: Double] = [:]
    /// Today's active energy, or nil when none is recorded.
    var activeEnergyToday: Double? { activeEnergy[dayKey(Date())].flatMap { $0 > 0 ? $0 : nil } }
    /// Average daily active energy over the last two weeks, counting days with any recorded.
    var averageActiveEnergy: Double? { ActiveEnergy.recentAverage(activeEnergy, before: Date()) }
    /// The sources that have recorded active energy, and today's from each, to help choose one.
    private(set) var energySources: [StepSource] = []
    private(set) var energySourceTotals: [String: Double] = [:]
    /// The source calories burnt are shown from, by bundle identifier, or nil for all sources together.
    /// Kept on this device: sources differ between devices.
    private(set) var energySourceID: String? = UserDefaults.standard.string(forKey: HealthSync.energySourceKey) {
        didSet { UserDefaults.standard.set(energySourceID, forKey: Self.energySourceKey) }
    }
    @ObservationIgnored private var knownEnergySources: [String: HKSource] = [:]
    static let energySourceKey = "health.energySource"
    /// The chosen source's name, for labels. Nil when showing all sources or the chosen source can't be found.
    var energySourceName: String? { energySourceID.flatMap { id in energySources.first { $0.id == id }?.name } }
    /// True once an active energy read has completed this launch.
    private(set) var energyLoaded = false
    /// Steps by day (day key) for the last 90 days. Kept in memory only: Health data isn't copied to iCloud or Leanr's backups.
    private(set) var steps: [String: Double] = [:]
    /// An app or device that records steps in Health, such as the iPhone, a watch or Google Health.
    struct StepSource: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
    }
    /// The sources that have recorded steps, and today's steps from each, to help choose one.
    private(set) var stepSources: [StepSource] = []
    private(set) var stepSourceTotals: [String: Double] = [:]
    /// The source steps are shown from, by bundle identifier, or nil for all sources together (Health removes double counting).
    /// Kept on this device: sources differ between devices.
    private(set) var stepSourceID: String? = UserDefaults.standard.string(forKey: HealthSync.stepSourceKey) {
        didSet { UserDefaults.standard.set(stepSourceID, forKey: Self.stepSourceKey) }
    }
    @ObservationIgnored private var knownSources: [String: HKSource] = [:]
    static let stepSourceKey = "health.stepSource"
    /// The chosen source's name, for labels. Nil when showing all sources or the chosen source can't be found.
    var stepSourceName: String? { stepSourceID.flatMap { id in stepSources.first { $0.id == id }?.name } }
    /// True once a step read has completed this launch, so the screens can tell "none yet" from "not loaded".
    private(set) var stepsLoaded = false
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
    private static let water = HKQuantityType(.dietaryWater)
    private static let stepCount = HKQuantityType(.stepCount)
    private static let activeEnergyType = HKQuantityType(.activeEnergyBurned)
    private static let food = HKCorrelationType(.food)

    /// Asks for access, then copies the last week's log to Health and reads weights and activity.
    func connect() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await health.requestAuthorization(toShare: Set(Self.nutritionTypes + [Self.bodyMass, Self.water]),
                                                  read: [Self.bodyMass, Self.activeEnergyType, Self.stepCount])
        } catch { lastError = error.localizedDescription; return false }
        lastError = nil
        enabled = true
        if let store {
            let start = dayKey(Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date())
            for (day, entries) in store.data.logs where day >= start {
                for entry in entries { await replace(entry, day: day) }
            }
            for weight in store.data.weightLog where weight.healthID == nil { await replace(weight) }
            for (day, millilitres) in store.data.water ?? [:] where day >= start { await replaceWater(day: day, millilitres: millilitres) }
        }
        await refresh()
        watchSteps()
        return true
    }

    func disconnect() {
        enabled = false; activeEnergy = [:]; energyLoaded = false; steps = [:]; stepsLoaded = false
        store?.updateActiveEnergy([:])
        stepSources = []; stepSourceTotals = [:]; knownSources = [:]
        energySources = []; energySourceTotals = [:]; knownEnergySources = [:]
        store?.updateSteps([:])
        if let stepObserver { health.stop(stepObserver); self.stepObserver = nil }
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
        // Water is one sample a day, replaced whenever that day's total changes.
        let waterBefore = old.water ?? [:], waterAfter = new.water ?? [:]
        let waterDays = Set(waterBefore.keys).union(waterAfter.keys).filter { waterBefore[$0] != waterAfter[$0] }
        queue = Task { [previous = queue] in
            await previous?.value
            if !waterDays.isEmpty {
                // Asks only the first time (and for people who connected before water existed); afterwards it answers at once.
                try? await health.requestAuthorization(toShare: [Self.water], read: [])
                for day in waterDays { await replaceWater(day: day, millilitres: waterAfter[day] ?? 0) }
            }
            for (id, entry) in after where before[id]?.entry != entry.entry { await replace(entry.entry, day: entry.day) }
            for id in before.keys where after[id] == nil { await deleteEntry(id) }
            for (id, weight) in afterWeights where beforeWeights[id] != weight { await replace(weight) }
            for id in beforeWeights.keys where afterWeights[id] == nil { await deleteWeight(id) }
        }
    }

    /// Waits for Health updates already under way, so Siri can finish before the app is suspended.
    func finishPending() async { await queue?.value }

    /// Reads active energy and steps, and imports weights recorded in Health by other apps and devices.
    func refresh() async {
        guard enabled else { return }
        await refreshActiveEnergy()
        await importWeights()
        await refreshSteps()
        watchSteps()
    }

    /// Asks for permission to read steps. For people who connected Health before steps existed, this is the first time it's asked;
    /// afterwards it answers at once. Health doesn't say whether reading was allowed, only whether the question was asked.
    func requestStepAccess() async {
        guard isAvailable else { return }
        do { try await health.requestAuthorization(toShare: [], read: [Self.stepCount]) } catch { lastError = error.localizedDescription; return }
        enabled = true
        await refreshSteps()
        watchSteps()
    }

    /// Reads each day's steps for the last 90 days. Health adds up what the iPhone, watch and other sources recorded without
    /// counting the same walk twice.
    func refreshSteps() async {
        guard enabled else { return }
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -89, to: today) else { return }
        #if DEBUG
        // `-demoSteps` fills in a believable 90 days, because the simulator has no Health data.
        if CommandLine.arguments.contains("-demoSteps") {
            var demo: [String: Double] = [:]
            for offset in 0..<90 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today), offset % 11 != 7 else { continue }
                demo[dayKey(day)] = Double(4200 + (offset * 7919) % 7600)
            }
            steps = demo; stepsLoaded = true; store?.updateSteps(demo)
            return
        }
        #endif
        var source: HKSource?
        if let id = stepSourceID {
            if knownSources[id] == nil { await loadStepSources() }
            // A chosen source that has gone (an app deleted) falls back to everything rather than showing nothing.
            source = knownSources[id]
        }
        // Until steps have been asked for, Health refuses the question; that reads as "no steps yet", with a button to allow them.
        guard let days = await dailySums(Self.stepCount, unit: .count(), from: start, source: source) else { steps = [:]; stepsLoaded = true; return }
        steps = days
        stepsLoaded = true
        store?.updateSteps(days)
    }

    /// Lists what has recorded steps (iPhone, watch, Google Health, Fitbit...) with each one's steps today.
    func loadStepSources() async {
        guard enabled, let found = await recordingSources(Self.stepCount) else { return }
        knownSources = Dictionary(found.map { ($0.bundleIdentifier, $0) }) { first, _ in first }
        stepSources = found.map { StepSource(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        stepSourceTotals = await todayTotals(Self.stepCount, unit: .count(), sources: found)
    }

    /// Shows steps from one source, or from all of them with nil, and reads them again.
    func chooseStepSource(_ id: String?) async {
        stepSourceID = id
        await refreshSteps()
    }

    /// Asks for permission to read active energy. For people who connected Health before calories burnt existed, this is the
    /// first time it's asked; afterwards it answers at once. Health doesn't say whether reading was allowed, only whether it was asked.
    func requestEnergyAccess() async {
        guard isAvailable else { return }
        do { try await health.requestAuthorization(toShare: [], read: [Self.activeEnergyType]) } catch { lastError = error.localizedDescription; return }
        enabled = true
        await refreshActiveEnergy()
    }

    /// Reads each day's active energy for the last 90 days, from the chosen source or from all of them together.
    func refreshActiveEnergy() async {
        guard enabled else { return }
        let calendar = Calendar.current, today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -89, to: today) else { return }
        #if DEBUG
        // `-demoSteps` also fills in a believable 90 days of calories burnt, because the simulator has no Health data.
        if CommandLine.arguments.contains("-demoSteps") {
            var demo: [String: Double] = [:]
            for offset in 0..<90 {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: today), offset % 13 != 5 else { continue }
                demo[dayKey(day)] = Double(260 + (offset * 6151) % 640)
            }
            activeEnergy = demo; energyLoaded = true; store?.updateActiveEnergy(demo)
            return
        }
        #endif
        // Connected before calories burnt existed: Health has never been asked, so it would refuse the read. Ask once now.
        if (try? await health.statusForAuthorizationRequest(toShare: [], read: [Self.activeEnergyType])) == .shouldRequest {
            try? await health.requestAuthorization(toShare: [], read: [Self.activeEnergyType])
        }
        var source: HKSource?
        if let id = energySourceID {
            if knownEnergySources[id] == nil { await loadEnergySources() }
            source = knownEnergySources[id]
        }
        guard let days = await dailySums(Self.activeEnergyType, unit: .kilocalorie(), from: start, source: source) else {
            activeEnergy = [:]; energyLoaded = true; store?.updateActiveEnergy([:]); return
        }
        activeEnergy = days
        energyLoaded = true
        store?.updateActiveEnergy(days)
    }

    /// Lists what has recorded active energy (Apple Watch, iPhone, Fitbit...) with each one's total today.
    func loadEnergySources() async {
        guard enabled, let found = await recordingSources(Self.activeEnergyType) else { return }
        knownEnergySources = Dictionary(found.map { ($0.bundleIdentifier, $0) }) { first, _ in first }
        energySources = found.map { StepSource(id: $0.bundleIdentifier, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        energySourceTotals = await todayTotals(Self.activeEnergyType, unit: .kilocalorie(), sources: found)
    }

    /// Shows calories burnt from one source, or from all of them with nil, and reads them again.
    func chooseEnergySource(_ id: String?) async {
        energySourceID = id
        await refreshActiveEnergy()
    }

    /// Each day's total of a quantity since `start`, from one source or all together. Days with nothing are left out.
    /// Nil when Health refuses the question, which is what an unanswered permission looks like.
    private func dailySums(_ type: HKQuantityType, unit: HKUnit, from start: Date, source: HKSource?) async -> [String: Double]? {
        var predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        if let source { predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, HKQuery.predicateForObjects(from: [source])]) }
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await query.result(for: health) else { return nil }
        var days: [String: Double] = [:]
        for statistics in collection.statistics() {
            if let sum = statistics.sumQuantity()?.doubleValue(for: unit), sum > 0 { days[dayKey(statistics.startDate)] = sum.rounded() }
        }
        return days
    }

    /// The apps and devices that have recorded a quantity.
    private func recordingSources(_ type: HKQuantityType) async -> [HKSource]? {
        guard let found = try? await HKSourceQueryDescriptor(predicate: .quantitySample(type: type)).result(for: health) else { return nil }
        return Array(found)
    }

    /// Today's total from each source, by bundle identifier.
    private func todayTotals(_ type: HKQuantityType, unit: HKUnit, sources: [HKSource]) async -> [String: Double] {
        let today = Calendar.current.startOfDay(for: Date())
        var totals: [String: Double] = [:]
        for source in sources {
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: today, end: nil), HKQuery.predicateForObjects(from: [source])])
            let query = HKStatisticsQueryDescriptor(predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum)
            if let sum = try? await query.result(for: health)?.sumQuantity()?.doubleValue(for: unit) { totals[source.bundleIdentifier] = sum.rounded() }
        }
        return totals
    }

    private var stepObserver: HKObserverQuery?

    /// Asks Health to wake Leanr when new steps arrive, so the Steps widget keeps up without the app being open.
    /// Safe to call again; does nothing until Health is connected.
    func watchSteps() {
        guard enabled, isAvailable, stepObserver == nil else { return }
        let query = HKObserverQuery(sampleType: Self.stepCount, predicate: nil) { [weak self] _, completion, _ in
            nonisolated(unsafe) let finish = completion
            Task { @MainActor in
                // Health wakes Leanr in the background about hourly: a good moment to log what the widgets queued.
                AppServices.logQueued()
                await self?.refreshSteps()
                finish()
            }
        }
        health.execute(query)
        stepObserver = query
        health.enableBackgroundDelivery(for: Self.stepCount, frequency: .hourly) { _, _ in }
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
        }.map {
            // Scales and other apps often store pounds converted to kg (181.5 lb is 82.3293 kg); Leanr keeps weights to 10 g.
            WeightEntry(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)).hundredth, healthID: $0.uuid)
        }
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

    /// One water sample for a day: its total, dated the start of that day. A day back at nothing has no sample.
    private func replaceWater(day: String, millilitres: Double) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.waterKey, allowedValues: [day])
        _ = try? await health.deleteObjects(of: Self.water, predicate: predicate)
        guard millilitres > 0, let start = Water.date(of: day) else { return }
        let sample = HKQuantitySample(type: Self.water, quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: millilitres),
                                      start: start, end: start, metadata: [Self.waterKey: day])
        try? await health.save(sample)
    }

    /// Removes every food and weight Leanr saved to Health. Weights from other apps and devices aren't touched.
    func deleteEverythingSaved() async {
        guard isAvailable else { return }
        let mine = HKQuery.predicateForObjects(from: HKSource.default())
        for type in Self.nutritionTypes + [Self.bodyMass, Self.water] { _ = try? await health.deleteObjects(of: type, predicate: mine) }
        _ = try? await health.deleteObjects(of: Self.food, predicate: mine)
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
