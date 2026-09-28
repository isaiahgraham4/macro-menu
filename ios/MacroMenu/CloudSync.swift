import Foundation

/// Keeps a copy of everything in your iCloud Drive app folder so your other devices can pick it up.
/// The newest copy wins. If both this device and iCloud changed since the last sync, the two are merged so nothing is lost
/// (a deletion made on the other device may come back in that case).
@MainActor @Observable
final class CloudSync {
    static let enabledKey = "icloud.enabled"
    private static let dirtyKey = "icloud.dirty"
    private static let remoteKey = "icloud.lastRemote"
    nonisolated private static let containerID = "iCloud.com.isaiahgraham.MacroMenu"

    struct Snapshot: Codable, Sendable {
        var modified: Date
        var data: AppData
    }

    var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey); if enabled { schedule(after: 0) } }
    }
    private(set) var lastSynced: Date?
    private(set) var problem: String?
    private(set) var syncing = false
    weak var store: AppStore?
    private var pending: Task<Void, Never>?

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.dirtyKey: true])
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        lastSynced = UserDefaults.standard.object(forKey: Self.remoteKey) as? Date
    }

    /// Something changed on this device; upload it shortly.
    func markDirty() {
        guard !syncing else { return }
        UserDefaults.standard.set(true, forKey: Self.dirtyKey)
        schedule(after: 2)
    }

    func schedule(after seconds: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    func sync() async {
        guard enabled, !syncing, let store, store.loadError == nil else { return }
        syncing = true; defer { syncing = false }
        guard let file = await Self.fileURL() else {
            problem = "Sign in to iCloud and turn on iCloud Drive in the Settings app to sync."; return
        }
        let defaults = UserDefaults.standard
        let dirty = defaults.bool(forKey: Self.dirtyKey)
        let lastRemote = defaults.object(forKey: Self.remoteKey) as? Date
        let remote: Snapshot?
        do { remote = try await Self.read(file) } catch { problem = "Couldn’t read your iCloud copy. \(error.localizedDescription)"; return }

        var upload: AppData?
        if let remote, remote.data.isValid, remote.modified != lastRemote {
            // A fresh install has nothing worth merging (only default targets), so it just takes the iCloud copy.
            let fresh = store.data.foods.isEmpty && store.data.logs.isEmpty && store.data.meals.isEmpty && store.data.weightLog.isEmpty
            if dirty && !fresh {
                // Both sides changed: keep everything from both.
                var merged = AppStore.merged(store.data, remote.data)
                merged.tray = store.data.tray
                guard store.applySynced(merged) else { problem = "Couldn’t save synced data on this device."; return }
                upload = merged
            } else {
                // The meal being built stays on each device.
                var incoming = remote.data; incoming.tray = store.data.tray
                guard store.applySynced(incoming) else { problem = "Couldn’t save synced data on this device."; return }
                defaults.set(remote.modified, forKey: Self.remoteKey)
                lastSynced = remote.modified; problem = nil
                return
            }
        } else if dirty || remote == nil {
            upload = store.data
        }
        guard let upload else { problem = nil; return }
        let snapshot = Snapshot(modified: Date(), data: upload)
        do { try await Self.write(snapshot, to: file) } catch { problem = "Couldn’t upload to iCloud. \(error.localizedDescription)"; return }
        defaults.set(snapshot.modified, forKey: Self.remoteKey)
        defaults.set(false, forKey: Self.dirtyKey)
        lastSynced = snapshot.modified; problem = nil
    }

    private static func fileURL() async -> URL? {
        await Task.detached {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
            let folder = container.appending(path: "Documents")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appending(path: "Leanr.json")
        }.value
    }

    private static func read(_ url: URL) async throws -> Snapshot? {
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: url.path) || FileManager.default.isUbiquitousItem(at: url) else { return nil }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            var coordinationError: NSError?
            var result: Result<Snapshot?, Error> = .success(nil)
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
                result = Result {
                    guard let bytes = try? Data(contentsOf: url) else { return nil }
                    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                    return try decoder.decode(Snapshot.self, from: bytes)
                }
            }
            if let coordinationError { throw coordinationError }
            return try result.get()
        }.value
    }

    private static func write(_ snapshot: Snapshot, to url: URL) async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(snapshot)
        try await Task.detached {
            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
                do { try bytes.write(to: url, options: .atomic) } catch { writeError = error }
            }
            if let error = coordinationError ?? writeError { throw error }
        }.value
    }
}
