import Foundation
import Observation
import MapKit
import CoreLocation

/// Looks up restaurants' opening hours on OpenStreetMap, for Open/Closed on nearby restaurants. Free, with no key or account.
///
/// Requests go to the public Overpass API in batches (one request for every restaurant on screen), and answers are kept on
/// the phone for a week, which OpenStreetMap's licence allows. Restaurants whose hours aren't mapped just offer Apple's
/// place card. Hours shown must credit "© OpenStreetMap contributors".
@MainActor @Observable
final class PlaceHoursStore {
    static let shared = PlaceHoursStore()

    enum Entry: Equatable { case loading, loaded(PlaceHours), unavailable }
    private(set) var entries: [String: Entry] = [:]

    /// What OpenStreetMap said about a restaurant: its `opening_hours` text, or nil when it has none.
    private struct Cached: Codable { var text: String?; var at: Date }
    @ObservationIgnored private var cache: [String: Cached]
    @ObservationIgnored private var pending: [String: Lookup] = [:]
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private let cacheKey = "osmHours.cache"
    /// Mapped hours are reused for a week; a restaurant with none is checked again after three days.
    private let freshFor: TimeInterval = 7 * 86_400, missingFor: TimeInterval = 3 * 86_400
    nonisolated private static let server = URL(string: "https://overpass-api.de/api/interpreter")!

    struct Lookup: Sendable { var key: String; var latitude, longitude: Double; var match: [String] }

    init() {
        let saved = UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([String: Cached].self, from: $0) } ?? [:]
        cache = saved.filter { Date().timeIntervalSince($0.value.at) < 30 * 86_400 }
    }

    /// Identifies a restaurant across searches: its name and position to about 10 m.
    nonisolated static func key(name: String, latitude: Double, longitude: Double) -> String {
        String(format: "%@|%.4f,%.4f", name.lowercased(), latitude, longitude)
    }

    func entry(_ key: String) -> Entry? { entries[key] }

    /// Shows a restaurant's hours from the phone's copy if it's recent, otherwise asks OpenStreetMap. Requests made
    /// within a moment of each other go together in one query.
    func load(key: String, chain: String, name: String, latitude: Double, longitude: Double) async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.demoHours") { entries[key] = .loaded(Self.demo(for: key)); return }
        #endif
        if let saved = cache[key], Date().timeIntervalSince(saved.at) < (saved.text == nil ? missingFor : freshFor) {
            if entries[key] == nil || entries[key] == .loading { show(saved.text, for: key) }
            return
        }
        guard pending[key] == nil, !inFlight.contains(key) else { return }
        let match = ChainPlace.all[chain]?.match ?? [name.lowercased()]
        pending[key] = Lookup(key: key, latitude: latitude, longitude: longitude, match: match)
        if entries[key] == nil || entries[key] == .unavailable { entries[key] = .loading }
        guard !flushing else { return }
        flushing = true
        // The store's own task, so a row scrolling away (which cancels its view's task) doesn't cancel everyone's lookup.
        Task { await flush() }
    }

    private func flush() async {
        try? await Task.sleep(for: .milliseconds(400))
        while !pending.isEmpty {
            let batch = Array(pending.values.prefix(25))
            batch.forEach { pending[$0.key] = nil; inFlight.insert($0.key) }
            await fetch(batch)
            batch.forEach { inFlight.remove($0.key) }
        }
        flushing = false
    }

    private func show(_ text: String?, for key: String) {
        entries[key] = text.flatMap(PlaceHours.parseOSM).map(Entry.loaded) ?? .unavailable
    }

    private func fetch(_ batch: [Lookup]) async {
        let query = OSMHours.query(batch.map { ($0.latitude, $0.longitude) })
        guard let elements = await Self.overpass(query) else {
            // Couldn't reach OpenStreetMap: hours already showing stay, the rest offer Apple's card and are tried next time.
            for lookup in batch where entries[lookup.key] == .loading { entries[lookup.key] = .unavailable }
            return
        }
        let now = Date()
        for lookup in batch {
            let text = OSMHours.pick(elements, latitude: lookup.latitude, longitude: lookup.longitude, match: lookup.match)
            cache[lookup.key] = Cached(text: text, at: now)
            show(text, for: lookup.key)
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(cache), forKey: cacheKey)
    }

    /// Runs a query on the public Overpass server, trying once more after a short wait if it's busy.
    nonisolated private static func overpass(_ query: String) async -> [OSMHours.Element]? {
        var request = URLRequest(url: server, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Overpass asks apps to identify themselves.
        request.setValue("Leanr/1.0 (iOS; \(Bundle.main.bundleIdentifier ?? "Leanr"))", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        var form = URLComponents(); form.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        for attempt in 0..<2 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(3)) }
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            return (try? JSONDecoder().decode(OSMHours.Response.self, from: data))?.elements
        }
        return nil
    }

    #if DEBUG
    /// Sample hours for trying the screens: run with `-debug.demoHours YES`.
    private static func demo(for key: String) -> PlaceHours {
        switch abs(key.hashValue) % 3 {
        case 0: return PlaceHours(periods: [.init(openDay: 0, openMinute: 0, closeDay: nil, closeMinute: nil)], utcOffsetMinutes: nil)
        case 1: return PlaceHours(periods: (0..<7).map { .init(openDay: $0, openMinute: 480, closeDay: $0, closeMinute: 1320) }, utcOffsetMinutes: nil)
        default: return PlaceHours(periods: (0..<7).map { .init(openDay: $0, openMinute: 600, closeDay: ($0 + 1) % 7, closeMinute: 120) }, utcOffsetMinutes: nil)
        }
    }
    #endif
}

/// Which restaurants near you are closed, so lists of things to eat can leave them out.
/// Judged by the closest restaurant of each chain. Unknown hours (no key, not listed, still loading) count as open.
@MainActor enum OpenNow {
    /// The "Open now only" switch, shared by Find and Best choices.
    static let storageKey = "find.openNowOnly"

    /// Chains whose closest restaurant is closed at `date`, with when it next opens.
    static func closed(location: LocationStore, at date: Date = Date()) -> [String: Date?] {
        guard location.isAuthorized else { return [:] }
        var result: [String: Date?] = [:]
        for (chain, places) in location.places {
            guard let nearest = places.first, case .loaded(let hours) = PlaceHoursStore.shared.entry(nearest.hoursKey),
                  case .closed(let opens) = hours.status(at: date) else { continue }
            result[chain] = opens
        }
        return result
    }

    /// Finds the closest restaurant of every chain and looks up its hours. Location is never asked for here.
    static func load(location: LocationStore) async {
        guard location.isAuthorized else { return }
        await location.load(Array(ChainPlace.all.keys))
        // Started together so they share one OpenStreetMap query; the hours are observed, so lists update as they arrive.
        for place in location.places.values.compactMap(\.first) {
            let key = place.hoursKey, chain = place.chain, name = place.item.name ?? place.chain, spot = place.coordinate
            Task { await PlaceHoursStore.shared.load(key: key, chain: chain, name: name, latitude: spot.latitude, longitude: spot.longitude) }
        }
    }

    /// "KFC (opens 8:00 am), Subway", for saying what's been left out.
    static func describe(_ closed: [String: Date?], names: (String) -> String) -> String {
        closed.sorted { names($0.key) < names($1.key) }.map { chain, opens in
            guard let opens else { return names(chain) }
            let today = Calendar.current.isDateInToday(opens)
            let time = opens.formatted(date: .omitted, time: .shortened)
            return "\(names(chain)) (opens \(today ? time : opens.formatted(.dateTime.weekday(.abbreviated)) + " " + time))"
        }.joined(separator: ", ")
    }
}

