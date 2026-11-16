import CloudKit
import Foundation

// Foods people choose to share go to the public CloudKit database in iCloud.com.isaiahgraham.MacroMenu,
// and everyone else sees them in search and barcode scans as "Community" foods.
// Schema, moderation and release steps: ios/SHARED-FOODS.md and ios/cloudkit/schema.ckdb.

/// A food someone shared, as read back from the public database.
struct SharedFood: Codable, Sendable, Hashable {
    /// "food-" plus the sharer's own food ID, so editing the food replaces the shared copy.
    var recordName: String
    /// The sharer's CloudKit user ID for this app. Anonymous; only used to hide everything from someone.
    var creator: String
    var food: Food
    var modified: Date
}

struct SharedFoodReport: Codable, Sendable, Hashable {
    var recordName: String
    var reporter: String
}

enum ShareReportReason: String, CaseIterable, Identifiable, Sendable {
    case wrongNumbers = "The numbers are wrong"
    case offensive = "Offensive or abusive"
    case spam = "Spam or advertising"
    case other = "Something else"
    var id: String { rawValue }
}

enum SharedFoodError: LocalizedError {
    case noAccount, restricted, unavailable
    var errorDescription: String? {
        switch self {
        case .noAccount: "Sign in to iCloud in Settings to share foods."
        case .restricted: "iCloud is restricted on this \(DeviceName.current), so foods can't be shared."
        case .unavailable: "iCloud can't be reached right now. Try again shortly."
        }
    }
}

// MARK: - Backend

protocol SharedFoodBackend: Sendable {
    func myID() async throws -> String
    /// Every shared food, report and moderator removal, newest first, up to the cap.
    func everything() async throws -> (foods: [SharedFood], reports: [SharedFoodReport], removed: Set<String>)
    func foods(barcode: String) async throws -> [SharedFood]
    /// Every report made about these foods.
    func reports(on recordNames: [String]) async throws -> [SharedFoodReport]
    func save(_ food: Food) async throws
    func delete(recordName: String) async throws
    func report(recordName: String, reason: ShareReportReason) async throws
}

/// The public database. Anyone can read; only a record's creator can change or delete it;
/// only the Moderator role can write `SharedFoodRemoved` (see cloudkit/schema.ckdb).
actor CloudKitSharedFoods: SharedFoodBackend {
    static let containerID = "iCloud.com.isaiahgraham.MacroMenu"
    /// Enough for a long while; past this, search sees the newest foods and barcodes are looked up on demand.
    static let cap = 5000
    private let container = CKContainer(identifier: containerID)
    private var db: CKDatabase { container.publicCloudDatabase }
    private var me: String?

    func myID() async throws -> String {
        if let me { return me }
        switch try await container.accountStatus() {
        case .available: break
        case .noAccount: throw SharedFoodError.noAccount
        case .restricted: throw SharedFoodError.restricted
        default: throw SharedFoodError.unavailable
        }
        let id = try await container.userRecordID().recordName
        me = id
        return id
    }

    /// Reads up to `limit` records, newest first, turning each page into `T` as it arrives so the records themselves
    /// (which anyone can write, at any size) are never all held at once.
    private func all<T: Sendable>(_ type: String, predicate: NSPredicate = NSPredicate(value: true), keys: [String]? = nil, limit: Int = cap,
                                  page: Int = 400, _ make: @Sendable (CKRecord) -> T?) async throws -> [T] {
        let query = CKQuery(recordType: type, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        var (results, cursor) = try await db.records(matching: query, desiredKeys: keys, resultsLimit: min(limit, page))
        var read = results.count
        var made = results.compactMap { (try? $0.1.get()).flatMap(make) }
        while let next = cursor, read < limit {
            (results, cursor) = try await db.records(continuingMatchFrom: next, desiredKeys: keys, resultsLimit: page)
            read += results.count
            made += results.compactMap { (try? $0.1.get()).flatMap(make) }
        }
        return made
    }

    /// An empty result when the record type doesn't exist yet (nothing's been shared in this environment).
    private func tolerant<T>(_ work: () async throws -> [T]) async throws -> [T] {
        do { return try await work() }
        catch let error as CKError where error.code == .unknownItem { return [] }
    }

    func everything() async throws -> (foods: [SharedFood], reports: [SharedFoodReport], removed: Set<String>) {
        let foods = try await tolerant { try await all("SharedFood", keys: Self.foodKeys, page: 100, Self.food(from:)) }
        let reports = try await tolerant { try await all("SharedFoodReport", keys: ["foodRecord"], Self.report(from:)) }
        let removed = try await tolerant { try await all("SharedFoodRemoved", keys: ["foodRecord"]) { $0["foodRecord"] as? String } }
        return (foods, reports, Set(removed))
    }

    func foods(barcode: String) async throws -> [SharedFood] {
        let trimmed = String(barcode.drop { $0 == "0" })
        return try await tolerant { try await all("SharedFood", predicate: NSPredicate(format: "barcodeKey == %@", trimmed), keys: Self.foodKeys, limit: 20, Self.food(from:)) }
    }

    func reports(on recordNames: [String]) async throws -> [SharedFoodReport] {
        guard !recordNames.isEmpty else { return [] }
        return try await tolerant { try await all("SharedFoodReport", predicate: NSPredicate(format: "foodRecord IN %@", recordNames), keys: ["foodRecord"], Self.report(from:)) }
    }

    /// The fields the app reads; anything else on a record isn't downloaded.
    private static let foodKeys = ["name", "serve", "cat", "cal", "p", "c", "f", "nut", "barcode"]

    private static func report(from record: CKRecord) -> SharedFoodReport? {
        guard let name = record["foodRecord"] as? String, isSharedRecordName(name), let by = record.creatorUserRecordID?.recordName else { return nil }
        return SharedFoodReport(recordName: name, reporter: by)
    }

    func save(_ food: Food) async throws {
        _ = try await myID()
        let id = CKRecord.ID(recordName: sharedRecordName(for: food.id))
        let record: CKRecord
        do { record = try await db.record(for: id) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "SharedFood", recordID: id) }
        record["name"] = food.name.trimmingCharacters(in: .whitespacesAndNewlines)
        record["serve"] = food.serve.trimmingCharacters(in: .whitespacesAndNewlines)
        record["cat"] = food.cat
        record["cal"] = food.cal
        record["p"] = food.p
        record["c"] = food.c
        record["f"] = food.f
        record["nut"] = SharingRules.knownNutrients(food.nut).flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        record["barcode"] = food.barcode
        record["barcodeKey"] = food.barcode.map { String($0.drop { $0 == "0" }) }
        record["version"] = 1
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys).saveResults[id]?.get()
    }

    func delete(recordName: String) async throws {
        do { _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: recordName)) }
        catch let error as CKError where error.code == .unknownItem { }
    }

    func report(recordName: String, reason: ShareReportReason) async throws {
        let me = try await myID()
        // One report per person per food: reporting again just updates the reason.
        let id = CKRecord.ID(recordName: reportRecordName(food: recordName, reporter: me))
        let record = CKRecord(recordType: "SharedFoodReport", recordID: id)
        record["foodRecord"] = recordName
        record["reason"] = reason.rawValue
        _ = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys).saveResults[id]?.get()
    }

    nonisolated static func food(from record: CKRecord) -> SharedFood? {
        guard let name = record["name"] as? String, let cal = record["cal"] as? Double, let p = record["p"] as? Double,
              let creator = record.creatorUserRecordID?.recordName, isSharedRecordName(record.recordID.recordName) else { return nil }
        // Anyone signed in to iCloud can write a record, so the text fields are sized before they're kept or decoded.
        let text = record["nut"] as? String
        guard name.utf8.count <= 400, ((record["serve"] as? String)?.utf8.count ?? 0) <= 200, (text?.utf8.count ?? 0) <= SharingRules.longestNutrientText,
              ((record["barcode"] as? String)?.utf8.count ?? 0) <= 14, ((record["cat"] as? String)?.utf8.count ?? 0) <= 20 else { return nil }
        let nut = SharingRules.knownNutrients(text.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) })
        let food = Food(id: "community:" + record.recordID.recordName, chain: Food.community, name: name,
                        cat: (record["cat"] as? String) ?? "main", kj: cal * 4.184, cal: cal, p: p,
                        c: record["c"] as? Double, f: record["f"] as? Double, serve: (record["serve"] as? String) ?? "1 serving",
                        nut: nut, barcode: record["barcode"] as? String, contributor: creator)
        guard SharingRules.problem(food) == nil else { return nil }
        return SharedFood(recordName: record.recordID.recordName, creator: creator, food: food, modified: record.modificationDate ?? .distantPast)
    }
}

/// Launch with `-demoCommunityFoods` to try shared foods without iCloud: a few made-up foods, kept in memory.
actor DemoSharedFoods: SharedFoodBackend {
    private var foods: [SharedFood]
    private var reports: [SharedFoodReport] = [
        .init(recordName: "food-demo-reported", reporter: "a"), .init(recordName: "food-demo-reported", reporter: "b"), .init(recordName: "food-demo-reported", reporter: "c"),
    ]
    init() {
        func make(_ id: String, _ name: String, _ serve: String, cal: Double, p: Double, c: Double, f: Double, barcode: String? = nil, by: String = "demo-someone") -> SharedFood {
            let recordName = "food-demo-\(id)"
            return SharedFood(recordName: recordName, creator: by,
                              food: Food(id: "community:" + recordName, chain: Food.community, name: name, cat: "snack", kj: cal * 4.184, cal: cal, p: p, c: c, f: f, serve: serve, barcode: barcode, contributor: by),
                              modified: .now)
        }
        foods = [
            make("bar", "Uncle Tobys Protein Bar Choc Chip", "1 bar (40 g)", cal: 160, p: 10, c: 17, f: 5.5, barcode: "9310000000017"),
            make("yoghurt", "Chobani Fit Vanilla Pouch", "1 pouch (140 g)", cal: 104, p: 13.2, c: 9.8, f: 0.4),
            make("wrap", "Servo chicken wrap", "1 wrap", cal: 420, p: 24, c: 45, f: 15, by: "demo-other"),
            make("reported", "Totally real burger", "1 burger", cal: 500, p: 25, c: 50, f: 22),
        ]
    }
    func myID() async throws -> String { "demo-me" }
    func everything() async throws -> (foods: [SharedFood], reports: [SharedFoodReport], removed: Set<String>) {
        try await Task.sleep(for: .milliseconds(300))
        return (foods, reports, [])
    }
    func foods(barcode: String) async throws -> [SharedFood] {
        let key = barcode.drop { $0 == "0" }
        return foods.filter { $0.food.barcode?.drop { $0 == "0" } == key }
    }
    func reports(on recordNames: [String]) async throws -> [SharedFoodReport] { reports.filter { recordNames.contains($0.recordName) } }
    func save(_ food: Food) async throws {
        let name = sharedRecordName(for: food.id)
        var copy = food; copy.id = "community:" + name; copy.chain = Food.community; copy.contributor = "demo-me"; copy.shared = nil
        foods.removeAll { $0.recordName == name }
        foods.insert(SharedFood(recordName: name, creator: "demo-me", food: copy, modified: .now), at: 0)
    }
    func delete(recordName: String) async throws { foods.removeAll { $0.recordName == recordName } }
    func report(recordName: String, reason: ShareReportReason) async throws { reports.append(.init(recordName: recordName, reporter: "demo-me")) }
}

// MARK: - Store

/// Shared foods for search and barcode scans, plus uploading the foods you choose to share.
@MainActor @Observable
final class CommunityFoods {
    static let showKey = "community.show"
    static let agreedKey = "community.agreed"
    private static let blockedKey = "community.blocked"
    private static let reportedKey = "community.reported"
    private static let uploadKey = "community.pendingUpload"
    private static let deleteKey = "community.pendingDelete"
    /// How often the list is fetched again while the app is used.
    static let refreshEvery: TimeInterval = 6 * 3600

    /// Show other people's foods in search and barcode scans.
    var show: Bool {
        didSet { UserDefaults.standard.set(show, forKey: Self.showKey); publish() }
    }
    private(set) var lastRefreshed: Date?
    private(set) var problem: String?
    private(set) var refreshing = false
    /// People whose foods you've hidden.
    private(set) var blocked: Set<String>
    /// Foods you've reported, hidden for you straight away.
    private(set) var reported: Set<String>
    weak var store: AppStore? { didSet { publish() } }

    private let backend: any SharedFoodBackend
    private var cache = Cache()
    private var myID: String?
    private var flushing = false
    private let cacheURL: URL

    struct Cache: Codable {
        var foods: [SharedFood] = []
        var reports: [SharedFoodReport] = []
        var removed: Set<String> = []
        var fetched: Date?
        var me: String?
    }

    init(backend: (any SharedFoodBackend)? = nil, cacheURL: URL = URL.applicationSupportDirectory.appending(path: "MacroMenu/community-foods.json")) {
        let demo = CommandLine.arguments.contains("-demoCommunityFoods")
        self.backend = backend ?? (demo ? DemoSharedFoods() : CloudKitSharedFoods())
        self.cacheURL = demo ? URL.temporaryDirectory.appending(path: "community-demo.json") : cacheURL
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Self.showKey: true])
        show = defaults.bool(forKey: Self.showKey)
        blocked = Set(defaults.stringArray(forKey: Self.blockedKey) ?? [])
        reported = Set(defaults.stringArray(forKey: Self.reportedKey) ?? [])
        if !demo, let data = try? Data(contentsOf: self.cacheURL), let saved = try? JSONDecoder().decode(Cache.self, from: data) {
            cache = saved; lastRefreshed = saved.fetched; myID = saved.me
        }
    }

    /// Foods others shared that you can see: not removed, not reported by several people or by you, not from someone you've hidden, and not your own.
    var visible: [SharedFood] {
        guard show else { return [] }
        let hidden = SharingRules.hiddenByReports(cache.reports.map { ($0.recordName, $0.reporter) })
        let mine = Set((store?.data.foods ?? []).map { sharedRecordName(for: $0.id) })
        return cache.foods.filter { item in
            !cache.removed.contains(item.recordName) && !hidden.contains(item.recordName) &&
            !reported.contains(item.recordName) && !blocked.contains(item.creator) &&
            item.creator != myID && item.creator != CKCurrentUserDefaultName && !mine.contains(item.recordName)
        }
    }

    private func publish() { store?.useCommunity(visible.map(\.food)) }

    /// Fetches the shared list when it's older than `refreshEvery`, or now when forced; uploads anything waiting first.
    func refresh(force: Bool = false) async {
        await flush()
        guard show || force, !refreshing else { return }
        if !force, let lastRefreshed, Date().timeIntervalSince(lastRefreshed) < Self.refreshEvery { return }
        refreshing = true; defer { refreshing = false }
        do {
            let result = try await backend.everything()
            if myID == nil { myID = try? await backend.myID() }
            cache = Cache(foods: result.foods, reports: result.reports, removed: result.removed, fetched: .now, me: myID)
            lastRefreshed = .now; problem = nil
            saveCache()
            publish()
        } catch {
            problem = Self.describe(error)
        }
    }

    /// A shared food with this barcode, from the saved list or, past its cap, from iCloud.
    func food(barcode: String) async -> Food? {
        guard show else { return nil }
        if let hit = BarcodeLookup.match(barcode, in: visible.map(\.food)) { return hit }
        // The live lookup has to pass the same report check as the saved list. If the reports can't be read, show nothing.
        guard let found = try? await backend.foods(barcode: barcode), !found.isEmpty,
              let live = try? await backend.reports(on: found.map(\.recordName)) else { return nil }
        let hidden = SharingRules.hiddenByReports((cache.reports + live).map { ($0.recordName, $0.reporter) })
        let allowed = Set(found.map(\.recordName)).subtracting(cache.removed).subtracting(reported).subtracting(hidden)
        return found.first { allowed.contains($0.recordName) && !blocked.contains($0.creator) && $0.creator != myID }?.food
    }

    /// Checks iCloud is usable before the first share, so the switch can say why it can't turn on.
    func canShare() async -> String? {
        do { myID = try await backend.myID(); return nil } catch { return Self.describe(error) }
    }

    func report(_ food: Food, reason: ShareReportReason) async -> Bool {
        guard let name = recordName(food) else { return false }
        reported.insert(name)
        UserDefaults.standard.set(Array(reported), forKey: Self.reportedKey)
        publish()
        do { try await backend.report(recordName: name, reason: reason); return true }
        catch { problem = Self.describe(error); return false }
    }

    func block(_ food: Food) {
        guard let who = food.contributor ?? cache.foods.first(where: { $0.food.id == food.id })?.creator else { return }
        blocked.insert(who)
        UserDefaults.standard.set(Array(blocked), forKey: Self.blockedKey)
        publish()
    }

    func unblockEveryone() {
        blocked = []; reported = []
        UserDefaults.standard.removeObject(forKey: Self.blockedKey)
        UserDefaults.standard.removeObject(forKey: Self.reportedKey)
        publish()
    }

    private func recordName(_ food: Food) -> String? {
        guard food.chain == Food.community, food.id.hasPrefix("community:") else { return nil }
        return String(food.id.dropFirst("community:".count))
    }

    // MARK: Your shared foods

    /// Called after every local change: uploads foods newly shared or edited, and removes ones unshared or deleted.
    func follow(old: AppData, new: AppData) {
        func shared(_ data: AppData) -> [String: Food] {
            Dictionary(data.foods.filter { $0.shared == true }.map { ($0.id, $0) }) { a, _ in a }
        }
        let before = shared(old), after = shared(new)
        var uploads = pending(Self.uploadKey), deletes = pending(Self.deleteKey)
        for (id, food) in after where before[id] != food { uploads.insert(id); deletes.remove(id) }
        for id in before.keys where after[id] == nil { deletes.insert(id); uploads.remove(id) }
        guard uploads != pending(Self.uploadKey) || deletes != pending(Self.deleteKey) else { return }
        setPending(uploads, Self.uploadKey); setPending(deletes, Self.deleteKey)
        // Your own changes show up in the community list straight away for no one else; fetch again soon so others' edits arrive too.
        Task { await flush() }
    }

    /// Sends what's waiting. Anything that fails stays queued for the next launch or refresh.
    func flush() async {
        guard !flushing, let store else { return }
        flushing = true; defer { flushing = false }
        var uploads = pending(Self.uploadKey), deletes = pending(Self.deleteKey)
        guard !uploads.isEmpty || !deletes.isEmpty else { return }
        for id in uploads {
            guard let food = store.data.foods.first(where: { $0.id == id }), food.shared == true, SharingRules.problem(food) == nil else {
                uploads.remove(id); deletes.insert(id); continue
            }
            do { try await backend.save(food); uploads.remove(id); problem = nil }
            catch { problem = Self.describe(error) }
        }
        for id in deletes {
            do { try await backend.delete(recordName: sharedRecordName(for: id)); deletes.remove(id) }
            catch { problem = Self.describe(error) }
        }
        setPending(uploads, Self.uploadKey); setPending(deletes, Self.deleteKey)
    }

    /// For Delete all my data: takes down every food you shared. False when iCloud couldn't be reached for some.
    func deleteAllShared(_ foods: [Food]) async -> Bool {
        let ids = Set(foods.filter { $0.shared == true }.map(\.id)).union(pending(Self.uploadKey)).union(pending(Self.deleteKey))
        var ok = true
        for id in ids {
            do { try await backend.delete(recordName: sharedRecordName(for: id)) } catch { ok = false }
        }
        setPending([], Self.uploadKey); setPending([], Self.deleteKey)
        try? FileManager.default.removeItem(at: cacheURL)
        return ok
    }

    private func pending(_ key: String) -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    private func setPending(_ value: Set<String>, _ key: String) {
        if value.isEmpty { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(Array(value), forKey: key) }
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? SharedFoodError { return error.localizedDescription }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated: return SharedFoodError.noAccount.localizedDescription
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud can't be reached right now. Shared foods will update when it can."
            case .quotaExceeded: return "Leanrrr's shared food space is full right now. Your foods will be shared once there's room."
            case .permissionFailure: return "iCloud didn't allow this change."
            default: break
            }
        }
        return "Shared foods couldn't update. \(error.localizedDescription)"
    }
}
