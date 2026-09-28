import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// How to find a chain in Apple Maps and open its Australian ordering app.
struct ChainPlace: Sendable {
    /// Apple Maps search text.
    let query: String
    /// Lowercased name fragments a search result must contain, so "Subway" doesn't match a train station.
    let match: [String]
    let appName: String
    let appStoreID: Int
    /// A universal link the chain's app claims (checked in its apple-app-site-association file), so iOS
    /// opens the app when it's installed. Chains without one go to their App Store page, which shows
    /// "Open" when the app is installed.
    let appLink: URL?

    var launchTitle: String { appLink == nil ? "\(appName) on App Store" : "Open \(appName)" }

    var storeURL: URL { URL(string: "https://apps.apple.com/au/app/id\(appStoreID)")! }
    func matches(_ name: String?) -> Bool {
        let name = (name ?? "").lowercased()
        return match.contains { name.contains($0) }
    }

    /// Keyed by chain id in MenuData.json. App Store ids are from the AU store (checked 26 Sep 2026).
    static let all: [String: ChainPlace] = [
        "mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "MyMacca's", appStoreID: 1105300599, appLink: URL(string: "https://mcdonaldsau.smart.link/")),
        "kfc": ChainPlace(query: "KFC", match: ["kfc"], appName: "KFC", appStoreID: 725748250, appLink: URL(string: "https://www.kfc.com.au/")),
        "hj": ChainPlace(query: "Hungry Jack's", match: ["hungry jack"], appName: "Hungry Jack's", appStoreID: 518981155, appLink: URL(string: "https://www.hungryjacks.com.au/find-us")),
        "sub": ChainPlace(query: "Subway", match: ["subway"], appName: "Subway", appStoreID: 1570190122, appLink: nil),
        "gyg": ChainPlace(query: "Guzman y Gomez", match: ["guzman", "gyg"], appName: "GYG", appStoreID: 595292048, appLink: URL(string: "https://order.guzmanygomez.com.au/")),
        "nandos": ChainPlace(query: "Nando's", match: ["nando"], appName: "Nando's", appStoreID: 491221341, appLink: URL(string: "https://www.nandos.com.au/menu")),
        "oporto": ChainPlace(query: "Oporto", match: ["oporto"], appName: "Oporto", appStoreID: 920675672, appLink: URL(string: "https://oporto.onelink.me/wCf9/")),
        "rr": ChainPlace(query: "Red Rooster", match: ["red rooster"], appName: "Red Rooster", appStoreID: 958424854, appLink: URL(string: "https://redrooster-prd.onelink.me/nA6U/paid-appy")),
        "dominos": ChainPlace(query: "Domino's Pizza", match: ["domino"], appName: "Domino's", appStoreID: 336882722, appLink: URL(string: "https://order.dominos.com.au/")),
        "spud": ChainPlace(query: "Spudbar", match: ["spud"], appName: "Spudbar", appStoreID: 1398722121, appLink: nil),
    ]
}

/// One restaurant found near the user.
struct NearbyPlace: Identifiable {
    let chain: String
    let item: MKMapItem
    let distance: CLLocationDistance
    var id: ObjectIdentifier { ObjectIdentifier(item) }

    init(chain: String, item: MKMapItem, from here: CLLocation) {
        self.chain = chain; self.item = item
        let spot = NearbyPlace.coordinate(of: item)
        distance = here.distance(from: CLLocation(latitude: spot.latitude, longitude: spot.longitude))
    }
    var coordinate: CLLocationCoordinate2D { NearbyPlace.coordinate(of: item) }
    var address: String {
        if #available(iOS 26, *) { return item.address?.shortAddress ?? item.address?.fullAddress ?? "" }
        return item.placemark.title ?? ""
    }
    var distanceText: String {
        Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road))
    }
    func directions() { item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault]) }

    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26, *) { return item.location.coordinate }
        return item.placemark.coordinate
    }
}

/// The user's location (only while the app is in use) and the nearest restaurants of each chain.
@MainActor @Observable
final class LocationStore: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus = .notDetermined
    private(set) var location: CLLocation?
    private(set) var places: [String: [NearbyPlace]] = [:]
    private(set) var loading: Set<String> = []
    private(set) var failed = false
    private var openingApp = false
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }
    func nearest(_ chain: String) -> NearbyPlace? { places[chain]?.first }

    /// Asks for "while using the app" permission the first time, then fetches the current location.
    func request() {
        failed = false
        if status == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if isAuthorized { manager.requestLocation() }
    }

    /// Searches Apple Maps for any of `chains` not yet looked up from the current location.
    func load(_ chains: [String]) async {
        guard isAuthorized else { return }
        guard let here = location else { manager.requestLocation(); return }
        for chain in chains where places[chain] == nil && !loading.contains(chain) {
            await search(chain, near: here)
        }
    }

    /// Opens the chain's app when iOS can hand off to it, otherwise its App Store page.
    func openApp(_ place: ChainPlace) async {
        guard !openingApp else { return }
        openingApp = true
        defer { openingApp = false }
        // Ask iOS to launch the installed handler without opening Safari first.
        // Fall back only after iOS reports it cannot perform the app handoff.
        if let link = place.appLink, await UIApplication.shared.open(link, options: [.universalLinksOnly: true]) { return }
        await UIApplication.shared.open(place.storeURL)
    }

    private func search(_ chain: String, near here: CLLocation) async {
        loading.insert(chain)
        let found = await LocationStore.find(chain, near: here)
        loading.remove(chain)
        guard here === location else { return }
        places[chain] = found
    }

    /// A chain's restaurants within about 15 km of `here`, closest first.
    static func find(_ chain: String, near here: CLLocation) async -> [NearbyPlace] {
        guard let place = ChainPlace.all[chain] else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.query
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        let items = (try? await MKLocalSearch(request: request).start())?.mapItems ?? []
        return items.filter { place.matches($0.name) }
            .map { NearbyPlace(chain: chain, item: $0, from: here) }
            .sorted { $0.distance < $1.distance }
    }

    private func authorizationChanged() {
        status = manager.authorizationStatus
        if isAuthorized { manager.requestLocation() }
    }

    private func moved() {
        guard let new = manager.location else { return }
        failed = false
        // Small moves keep the current results.
        if let old = location, old.distance(from: new) < 300 { return }
        location = new
        places = [:]
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { moved() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { if location == nil { failed = true } }
    }
}
