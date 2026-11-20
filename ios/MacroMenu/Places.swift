import SwiftUI
import MapKit
import CoreLocation
import UIKit

/// How to find a chain in Apple Maps and open its ordering app in that country's App Store.
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
    /// The App Store country the app id is from.
    var store = "au"

    var launchTitle: String { appLink == nil ? "\(appName) on App Store" : "Open \(appName)" }

    var storeURL: URL { URL(string: "https://apps.apple.com/\(store)/app/id\(appStoreID)")! }
    func matches(_ name: String?) -> Bool {
        let name = (name ?? "").lowercased()
        return match.contains { name.contains($0) }
    }

    /// Keyed by chain id in MenuData.json. App Store ids are from the AU store (checked 26 Sep 2026; Zambrero and Boost Juice 30 Sep 2026; the last nine 31 Oct 2026; Coles and Woolworths 2 Nov 2026).
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
        "zam": ChainPlace(query: "Zambrero", match: ["zambrero"], appName: "Zambrero", appStoreID: 1503449708, appLink: nil),
        "boost": ChainPlace(query: "Boost Juice", match: ["boost juice"], appName: "Boost Juice", appStoreID: 874205871, appLink: nil),
        "grilld": ChainPlace(query: "Grill'd", match: ["grill'd", "grilld", "grill’d"], appName: "Grill'd", appStoreID: 1228060909, appLink: URL(string: "https://www.grilld.com.au/menu")),
        "schnitz": ChainPlace(query: "Schnitz", match: ["schnitz"], appName: "Schnitz", appStoreID: 1530765524, appLink: URL(string: "https://order.schnitz.com.au/weborder")),
        "betty": ChainPlace(query: "Betty's Burgers", match: ["betty's", "bettys", "betty’s"], appName: "Betty's Burgers", appStoreID: 1499423312, appLink: nil),
        "fiveguys": ChainPlace(query: "Five Guys", match: ["five guys"], appName: "Five Guys", appStoreID: 683336616, appLink: nil),
        "crust": ChainPlace(query: "Crust Pizza", match: ["crust"], appName: "Crust", appStoreID: 479097479, appLink: nil),
        "donutking": ChainPlace(query: "Donut King", match: ["donut king"], appName: "Donut King", appStoreID: 1502521898, appLink: nil),
        "michels": ChainPlace(query: "Michel's Patisserie", match: ["michel's", "michels", "michel’s"], appName: "Michel's Loyalty", appStoreID: 1502522026, appLink: nil),
        "brumbys": ChainPlace(query: "Brumby's Bakery", match: ["brumby"], appName: "Brumby's Rewards", appStoreID: 1531861019, appLink: nil),
        "soul": ChainPlace(query: "Soul Origin", match: ["soul origin"], appName: "Soul Origin", appStoreID: 1536086153, appLink: nil),
        "rolld": ChainPlace(query: "Roll'd", match: ["roll'd", "rolld", "roll’d"], appName: "Roll'd", appStoreID: 1411683955, appLink: nil),
        "thisbowl": ChainPlace(query: "THISBOWL", match: ["thisbowl", "this bowl", "fishbowl"], appName: "THISBOWL", appStoreID: 6465208456, appLink: nil),
        "coles": ChainPlace(query: "Coles Supermarket", match: ["coles"], appName: "Coles", appStoreID: 529118855, appLink: nil),
        "woolworths": ChainPlace(query: "Woolworths", match: ["woolworths"], appName: "Woolworths", appStoreID: 975089690, appLink: nil),
        // US menu (`MenuRegion.unitedStates`). App Store ids are from the US store (checked 13 Nov 2026). No universal links yet,
        // so they open the App Store page, which shows "Open" when the app is installed.
        "us-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 922103212, appLink: nil, store: "us"),
        "us-cfa": ChainPlace(query: "Chick-fil-A", match: ["chick-fil-a", "chick fil a", "chickfila"], appName: "Chick-fil-A", appStoreID: 488818252, appLink: nil, store: "us"),
        "us-wendys": ChainPlace(query: "Wendy's", match: ["wendy's", "wendys", "wendy’s"], appName: "Wendy's", appStoreID: 540518599, appLink: nil, store: "us"),
        "us-tacobell": ChainPlace(query: "Taco Bell", match: ["taco bell"], appName: "Taco Bell", appStoreID: 497387361, appLink: nil, store: "us"),
        "us-panda": ChainPlace(query: "Panda Express", match: ["panda express"], appName: "Panda Express", appStoreID: 903990394, appLink: nil, store: "us"),
        "us-bk": ChainPlace(query: "Burger King", match: ["burger king"], appName: "Burger King", appStoreID: 638323895, appLink: nil, store: "us"),
        "us-popeyes": ChainPlace(query: "Popeyes", match: ["popeyes"], appName: "Popeyes", appStoreID: 1386566985, appLink: nil, store: "us"),
        // Canada, UK and New Zealand menus. App Store ids from each country's store (checked 14 Nov 2026); no universal links yet.
        "ca-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 375695000, appLink: nil, store: "ca"),
        "ca-bk": ChainPlace(query: "Burger King", match: ["burger king"], appName: "Burger King", appStoreID: 1422864779, appLink: nil, store: "ca"),
        "ca-tims": ChainPlace(query: "Tim Hortons", match: ["tim hortons", "tim horton"], appName: "Tim Hortons", appStoreID: 1143883086, appLink: nil, store: "ca"),
        "uk-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 1082476620, appLink: nil, store: "gb"),
        "uk-greggs": ChainPlace(query: "Greggs", match: ["greggs"], appName: "Greggs", appStoreID: 1098233626, appLink: nil, store: "gb"),
        "nz-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 1217507712, appLink: nil, store: "nz"),
        "nz-dominos": ChainPlace(query: "Domino's Pizza", match: ["domino"], appName: "Domino's", appStoreID: 415419062, appLink: nil, store: "nz"),
        // South African menu. App Store ids from the ZA store (checked 20 Nov 2026); no universal links yet.
        "za-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 1217507712, appLink: nil, store: "za"),
        "za-nandos": ChainPlace(query: "Nando's", match: ["nando"], appName: "Nando's", appStoreID: 1316416867, appLink: nil, store: "za"),
        "za-wimpy": ChainPlace(query: "Wimpy", match: ["wimpy"], appName: "Wimpy Rewards", appStoreID: 1514418099, appLink: nil, store: "za"),
        "za-debonairs": ChainPlace(query: "Debonairs Pizza", match: ["debonairs"], appName: "Debonairs Pizza", appStoreID: 1048945719, appLink: nil, store: "za"),
        "za-kauai": ChainPlace(query: "Kauai", match: ["kauai"], appName: "Kauai", appStoreID: 1585206786, appLink: nil, store: "za"),
        // Indian menu. App Store ids from the IN store (checked 20 Nov 2026); no universal links yet.
        "in-mcd": ChainPlace(query: "McDonald's", match: ["mcdonald"], appName: "McDonald's", appStoreID: 1217507712, appLink: nil, store: "in"),
        "in-kfc": ChainPlace(query: "KFC", match: ["kfc"], appName: "KFC India", appStoreID: 915824379, appLink: nil, store: "in"),
        "in-pizzahut": ChainPlace(query: "Pizza Hut", match: ["pizza hut"], appName: "Pizza Hut India", appStoreID: 1597873835, appLink: nil, store: "in"),
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
