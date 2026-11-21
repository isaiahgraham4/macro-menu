import Foundation

/// One of the food files built into the app that can also arrive newer from Leanrrr's Supabase project:
/// each country's restaurant menu, everyday foods, USDA survey foods and supermarket foods.
enum FoodDataset: Hashable, Sendable {
    case menu(MenuRegion)
    case everyday
    case survey
    case supermarket(MenuRegion)

    /// The dataset's id on Supabase (`public.datasets`), as `Scripts/supabase/upload.py` names it.
    var id: String {
        switch self {
        case .menu(let region): "menu-\(region.rawValue)"
        case .everyday: "generic"
        case .survey: "survey"
        // Australia keeps the id earlier versions read.
        case .supermarket(let region): region == .australia ? "supermarket" : "supermarket-\(region.rawValue)"
        }
    }

    /// Where a downloaded copy is kept. The Australian menu keeps the file earlier versions downloaded to.
    var cacheURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "MacroMenu")
        return self == .menu(.australia) ? folder.appending(path: "MenuData.json") : folder.appending(path: "Updates/\(id).json")
    }

    /// Restaurant menus and supermarket foods name their chains; everyday and survey foods are all chain "generic".
    var isList: Bool { self == .everyday || self == .survey }
}

/// Revisions and publish times of the bundled food files that don't carry their own (`FoodLists.json`, written by
/// `Scripts/supabase/upload.py` and `pull.py`), so a downloaded copy is only used while it's newer than the built-in one.
struct FoodListVersion: Codable, Equatable, Sendable {
    var revision: String?
    var published: String?

    static func bundled(_ url: URL? = Bundle.main.url(forResource: "FoodLists", withExtension: "json")) -> [String: FoodListVersion] {
        guard let url, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: FoodListVersion].self, from: data)) ?? [:]
    }
}

/// Fetches newer food data, so new items and corrected figures arrive without an app update.
/// Every dataset lives in Leanrrr's Supabase project (`ios/supabase`), published with `Scripts/supabase/upload.py` or
/// edited in its dashboard. The requests carry nothing about the user, only the app's public read-only key.
/// A download is only used if it's a format this version understands, is newer than what's in use, and every item checks out.
/// The copy built into the app is always there to fall back on.
enum MenuUpdates {
    /// Supabase's REST address. Nil would switch updates off and keep the built-in data.
    static let server: URL? = URL(string: "https://dmfmrqvmwvabzkqgdbdw.supabase.co/rest/v1/")
    /// The project's publishable key: it can only read foods (row-level security), so it's safe to ship in the app.
    static let publishableKey = "sb_publishable_rV4qINsqDY5CRsh88QzcGQ_2KFiIuJE"
    static let format = 1
    private static let session = URLSession(configuration: .ephemeral)
    /// Datasets are small but not tiny (the Australian menu is under 1 MB compressed); checking a few times a day is plenty.
    private static let interval: TimeInterval = 6 * 60 * 60
    private static let maxBytes = 16_000_000

    /// How far ahead of this device's clock a dataset's date may be: enough for a wrong time zone, not for a made-up date.
    private static let clockSlack: TimeInterval = 24 * 60 * 60

    /// Where one dataset is downloaded from: `/rest/v1/rpc/dataset?id=menu-AU`.
    static func url(_ dataset: FoodDataset) -> URL? {
        server?.appending(path: "rpc/dataset").appending(queryItems: [URLQueryItem(name: "id", value: dataset.id)])
    }

    /// Where its revision and date are asked for first, so an unchanged dataset is never downloaded.
    static func versionURL(_ dataset: FoodDataset) -> URL? {
        server?.appending(path: "datasets").appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(dataset.id)"),
                                                                   URLQueryItem(name: "select", value: "revision,published")])
    }

    /// When a dataset says it was published, or nil when that isn't a date and time.
    static func publishedDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))) ?? (try? Date(text, strategy: .iso8601))
    }

    /// Whether `candidate` can replace `current`.
    static func acceptable(_ candidate: MenuCatalog, over current: MenuCatalog, now: Date = Date()) -> Bool {
        guard candidate.format == format, !candidate.foods.isEmpty, candidate.chains.isEmpty == current.chains.isEmpty,
              candidate.foods.count >= current.foods.count / 2 else { return false }
        let latest = now.addingTimeInterval(clockSlack)
        if let text = candidate.published {
            // A date that can't be read, or one from the future, would outrank every real dataset after it.
            guard let date = publishedDate(text), date <= latest else { return false }
            // One in use whose own date is unreadable or ahead of the clock can't hold a real one back.
            if let mine = publishedDate(current.published), mine <= latest, date <= mine { return false }
        } else if current.published != nil {
            return false
        }
        let chains = Set(candidate.chains.map(\.id)), ids = candidate.foods.map(\.id)
        // Everyday and survey foods have no chain list; each of them is chain "generic".
        let known: (Food) -> Bool = chains.isEmpty ? { $0.chain == "generic" } : { chains.contains($0.chain) }
        return Set(ids).count == ids.count && candidate.foods.allSatisfy { $0.isValid && known($0) }
    }

    /// The newer of the built-in data and a previously downloaded copy.
    static func best(bundled: MenuCatalog, cachedAt url: URL = FoodDataset.menu(.australia).cacheURL) -> MenuCatalog {
        guard let bytes = try? Data(contentsOf: url), let cached = try? JSONDecoder().decode(MenuCatalog.self, from: bytes),
              acceptable(cached, over: bundled) else { return bundled }
        return cached
    }

    private struct Version: Decodable { var revision: String?; var published: String? }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Downloads a dataset if it's been a while and Supabase has a newer one, and hands it back.
    static func check(_ dataset: FoodDataset = .menu(.australia), current: MenuCatalog, force: Bool = false, now: Date = Date()) async -> MenuCatalog? {
        guard let versionURL = versionURL(dataset), let url = url(dataset) else { return nil }
        let defaults = UserDefaults.standard
        let checkedKey = "data.lastChecked.\(dataset.id)"
        if !force, let last = defaults.object(forKey: checkedKey) as? Date, now.timeIntervalSince(last) < interval { return nil }
        // First the revision and date alone (a few bytes): the same or an older dataset isn't downloaded at all.
        guard let (versionBytes, versionResponse) = try? await session.data(for: request(versionURL)),
              (versionResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        defaults.set(now, forKey: checkedKey)
        guard let version = (try? JSONDecoder().decode([Version].self, from: versionBytes))?.first else { return nil }
        if version.revision != nil, version.revision == current.revision { return nil }
        if let theirs = publishedDate(version.published), let mine = publishedDate(current.published), theirs <= mine { return nil }
        guard let (bytes, response) = try? await session.data(for: request(url)),
              (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= maxBytes else { return nil }
        let decoded = await Task.detached(priority: .utility) { try? JSONDecoder().decode(MenuCatalog.self, from: bytes) }.value
        guard let catalog = decoded, acceptable(catalog, over: current) else { return nil }
        do {
            try FileManager.default.createDirectory(at: dataset.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: dataset.cacheURL, options: .atomic)
        } catch { return nil }
        return catalog
    }
}
