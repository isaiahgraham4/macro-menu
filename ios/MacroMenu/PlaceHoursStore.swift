import Foundation
import Observation
import MapKit
import CoreLocation

/// Looks up restaurants' opening hours with Google Places, for Open/Closed on nearby restaurants.
///
/// The API key lives in `GooglePlaces.plist` (key `APIKey`) next to this file, which git ignores. Without it,
/// nothing is looked up and rows just offer Apple's place card.
///
/// Google's terms let apps keep place IDs, but not other place content, so IDs are saved and hours are only
/// held in memory for a short while.
@MainActor @Observable
final class PlaceHoursStore {
    static let shared = PlaceHoursStore()

    enum Entry: Equatable { case loading, loaded(PlaceHours), unavailable }
    private(set) var entries: [String: Entry] = [:]
    @ObservationIgnored private var fetched: [String: Date] = [:]
    @ObservationIgnored private let apiKey: String?
    @ObservationIgnored private let idsKey = "googlePlaces.ids"
    /// How long hours are reused before they're looked up again.
    private let freshFor: TimeInterval = 30 * 60

    init() {
        let url = Bundle.main.url(forResource: "GooglePlaces", withExtension: "plist")
        let key = url.flatMap { NSDictionary(contentsOf: $0)?["APIKey"] as? String }?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (key?.isEmpty ?? true) ? nil : key
    }

    var isConfigured: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.demoHours") { return true }
        #endif
        return apiKey != nil
    }

    /// Identifies a restaurant across searches: its name and position to about 10 m.
    nonisolated static func key(name: String, latitude: Double, longitude: Double) -> String {
        String(format: "%@|%.4f,%.4f", name.lowercased(), latitude, longitude)
    }

    func entry(_ key: String) -> Entry? { entries[key] }

    /// Fetches hours for a restaurant unless they're already fresh or on the way.
    func load(key: String, name: String, address: String, latitude: Double, longitude: Double) async {
        guard isConfigured else { return }
        if entries[key] == .loading { return }
        if let at = fetched[key], Date().timeIntervalSince(at) < freshFor { return }
        entries[key] = .loading
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "debug.demoHours") {
            entries[key] = .loaded(Self.demo(for: key)); fetched[key] = Date(); return
        }
        #endif
        guard let apiKey else { return }
        let hours: PlaceHours?
        if let id = await placeID(for: key, name: name, address: address, latitude: latitude, longitude: longitude, apiKey: apiKey) {
            hours = await Self.details(id: id, apiKey: apiKey)
        } else { hours = nil }
        entries[key] = hours.map(Entry.loaded) ?? .unavailable
        fetched[key] = Date()
    }

    /// The Google place ID for a restaurant: saved from an earlier search, or found by name near its position.
    private func placeID(for key: String, name: String, address: String, latitude: Double, longitude: Double, apiKey: String) async -> String? {
        var saved = UserDefaults.standard.dictionary(forKey: idsKey) as? [String: String] ?? [:]
        if let id = saved[key] { return id }
        guard let id = await Self.search(name: name, address: address, latitude: latitude, longitude: longitude, apiKey: apiKey) else { return nil }
        saved[key] = id
        UserDefaults.standard.set(saved, forKey: idsKey)
        return id
    }

    nonisolated private static func request(_ url: URL, apiKey: String, fields: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(fields, forHTTPHeaderField: "X-Goog-FieldMask")
        // Lets the key be restricted to this app in Google Cloud.
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        return request
    }

    /// Text Search asking only for IDs and positions, biased to within 150 m of the restaurant.
    nonisolated private static func search(name: String, address: String, latitude: Double, longitude: Double, apiKey: String) async -> String? {
        var request = request(URL(string: "https://places.googleapis.com/v1/places:searchText")!, apiKey: apiKey, fields: "places.id,places.location")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "textQuery": address.isEmpty ? name : "\(name), \(address)",
            "maxResultCount": 3,
            "locationBias": ["circle": ["center": ["latitude": latitude, "longitude": longitude], "radius": 150.0]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        struct Found: Decodable {
            struct Place: Decodable { struct Spot: Decodable { var latitude: Double; var longitude: Double }; var id: String; var location: Spot? }
            var places: [Place]?
        }
        let places = (try? JSONDecoder().decode(Found.self, from: data))?.places ?? []
        // The closest result, and only if it's really the same spot rather than another branch down the road.
        let near = places.compactMap { place -> (String, Double)? in
            guard let spot = place.location else { return nil }
            let metres = hypot((spot.latitude - latitude) * 111_000, (spot.longitude - longitude) * 111_000 * cos(latitude * .pi / 180))
            return metres <= 150 ? (place.id, metres) : nil
        }
        return near.min { $0.1 < $1.1 }?.0
    }

    nonisolated private static func details(id: String, apiKey: String) async -> PlaceHours? {
        guard let url = URL(string: "https://places.googleapis.com/v1/places/\(id)") else { return nil }
        let request = request(url, apiKey: apiKey, fields: "regularOpeningHours,currentOpeningHours,utcOffsetMinutes")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return PlaceHours.parse(data)
    }

    #if DEBUG
    /// Sample hours for trying the screens without a key: run with `-debug.demoHours YES`.
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
        guard location.isAuthorized, PlaceHoursStore.shared.isConfigured else { return }
        await location.load(Array(ChainPlace.all.keys))
        struct Lookup: Sendable { var key, name, address: String; var latitude, longitude: Double }
        let lookups = location.places.values.compactMap(\.first).map {
            Lookup(key: $0.hoursKey, name: $0.item.name ?? $0.chain, address: $0.address, latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        // All at once; each result shows as soon as it arrives, since the hours are observed.
        for lookup in lookups {
            Task {
                await PlaceHoursStore.shared.load(key: lookup.key, name: lookup.name, address: lookup.address,
                                                  latitude: lookup.latitude, longitude: lookup.longitude)
            }
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
