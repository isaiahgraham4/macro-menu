import Foundation

/// Fetches a newer restaurant menu, so new items and recipe changes can arrive without an app update.
/// The menu is an unlisted GitHub gist (published with `Scripts/publish-menu.sh`). The request carries nothing about the user.
/// A download is only used if it's a format this version understands, is newer than what's in use, and every item checks out.
/// The copy built into the app is always there to fall back on.
enum MenuUpdates {
    /// Where MenuData.json is published. Nil would switch menu updates off and keep the built-in menu.
    static let url: URL? = URL(string: "https://gist.githubusercontent.com/isaiahgraham4/7e5dd29511588062da0d233fdc88cbc1/raw/MenuData.json")
    static let format = 1
    static let cacheURL = URL.applicationSupportDirectory.appending(path: "MacroMenu/MenuData.json")
    private static let checkedKey = "menu.lastChecked"
    private static let etagKey = "menu.etag"
    /// Which menu the saved ETag belongs to, so "unchanged" is only asked about the menu in use.
    private static let etagRevisionKey = "menu.etagRevision"
    private static let session = URLSession(configuration: .ephemeral)
    /// Menus are small but not tiny (about 2 MB); checking a few times a day is plenty.
    private static let interval: TimeInterval = 6 * 60 * 60
    private static let maxBytes = 12_000_000

    /// How far ahead of this device's clock a menu's date may be: enough for a wrong time zone, not for a made-up date.
    private static let clockSlack: TimeInterval = 24 * 60 * 60

    /// When a menu says it was published, or nil when that isn't a date and time.
    static func publishedDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(text, strategy: .iso8601))
    }

    /// Whether `candidate` can replace `current`.
    static func acceptable(_ candidate: MenuCatalog, over current: MenuCatalog, now: Date = Date()) -> Bool {
        guard candidate.format == format, !candidate.chains.isEmpty,
              candidate.foods.count >= current.foods.count / 2 else { return false }
        let latest = now.addingTimeInterval(clockSlack)
        if let text = candidate.published {
            // A date that can't be read, or one from the future, would outrank every real menu after it.
            guard let date = publishedDate(text), date <= latest else { return false }
            // A menu in use whose own date is unreadable or ahead of the clock can't hold a real one back.
            if let mine = publishedDate(current.published), mine <= latest, date <= mine { return false }
        } else if current.published != nil {
            return false
        }
        let chains = Set(candidate.chains.map(\.id)), ids = candidate.foods.map(\.id)
        return Set(ids).count == ids.count && candidate.foods.allSatisfy { $0.isValid && chains.contains($0.chain) }
    }

    /// The newer of the built-in menu and a previously downloaded one.
    static func best(bundled: MenuCatalog, cachedAt url: URL = cacheURL) -> MenuCatalog {
        guard let bytes = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(MenuCatalog.self, from: bytes),
              acceptable(cached, over: bundled) else { return bundled }
        return cached
    }

    /// Downloads the menu if it's been a while, and hands back a newer one if there is one.
    static func check(current: MenuCatalog, force: Bool = false, now: Date = Date()) async -> MenuCatalog? {
        guard let url else { return nil }
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: checkedKey) as? Date, now.timeIntervalSince(last) < interval { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        // "Send it only if it's changed": the site answers 304 without the 2 MB body when it's still the menu in use.
        if let etag = defaults.string(forKey: etagKey), let revision = current.revision,
           defaults.string(forKey: etagRevisionKey) == revision {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (bytes, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        defaults.set(now, forKey: checkedKey)
        guard http.statusCode == 200, bytes.count <= maxBytes else { return nil }
        let decoded = await Task.detached(priority: .utility) { try? JSONDecoder().decode(MenuCatalog.self, from: bytes) }.value
        guard let catalog = decoded else { return nil }
        let etag = http.value(forHTTPHeaderField: "ETag")
        func remember(_ revision: String?) {
            defaults.set(etag, forKey: etagKey); defaults.set(revision, forKey: etagRevisionKey)
        }
        // The same menu as the one in use: remember its ETag so the next check can skip the download.
        if catalog.revision != nil, catalog.revision == current.revision { remember(catalog.revision); return nil }
        guard acceptable(catalog, over: current) else { return nil }
        do {
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: cacheURL, options: .atomic)
        } catch { return nil }
        remember(catalog.revision)
        return catalog
    }
}
