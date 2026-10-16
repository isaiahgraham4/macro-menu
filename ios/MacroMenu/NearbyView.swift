import SwiftUI
import MapKit

/// Map of the closest restaurant of each chain, near you or near a place you search for.
struct NearbyView: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    @Environment(Navigator.self) private var nav
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The restaurant pin tapped on the map, shown with Apple's place card.
    @State private var selected: MKMapItem?
    @State private var completer = PlaceCompleter()
    @State private var query = ""
    @State private var searchActive = false
    /// A searched place; nil shows restaurants near the user.
    @State private var area: (name: String, spot: CLLocation)?
    @State private var areaPlaces: [String: [NearbyPlace]] = [:]
    @State private var areaLoading = false
    @State private var noMatch = false
    @State private var searchTask: Task<Void, Never>?
    @State private var searchID = UUID()
    @State private var searchingFor = ""
    var chains: [String] { store.catalog.chains.map(\.id).filter { ChainPlace.all[$0] != nil } }
    var places: [String: [NearbyPlace]] { area == nil ? location.places : areaPlaces }
    var nearest: [NearbyPlace] { chains.compactMap { places[$0]?.first }.sorted { $0.distance < $1.distance } }
    var showingList: Bool { area != nil || (location.isAuthorized && location.location != nil) }
    var searchingNow: Bool { areaLoading || (area == nil && !location.loading.isEmpty) }
    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera, selection: $selected) {
                UserAnnotation()
                if let area { Marker(area.name, systemImage: "mappin", coordinate: area.spot.coordinate).tint(.red) }
                // Tapping a restaurant shows Apple's place card: opening hours, whether it's open now, phone and more.
                ForEach(chains.flatMap { (places[$0] ?? []).prefix(5) }) { place in Marker(item: place.item).tag(place.item) }
                    .mapItemDetailSelectionAccessory(.callout)
            }
            .mapControls { MapUserLocationButton() }
            // A shorter map at the largest text sizes leaves room for the restaurant list.
            .frame(height: typeSize.isAccessibilitySize ? 200 : 250)
            LeanrList {
                if let area {
                    Section {
                        Label("Near \(area.name)", systemImage: "mappin.and.ellipse").font(.roboto(.headline))
                        Button { clearArea() } label: { Label("Back to my location", systemImage: "location") }
                    }
                } else {
                    LocationStatusRows(what: "restaurants near you")
                    if !location.isAuthorized { Section { Text("Or search for a suburb or address above.").font(.roboto(.caption)).foregroundStyle(.secondary) } }
                }
                if noMatch { Section { Text("Couldn't find “\(query)”. Try a suburb or full address.").foregroundStyle(.secondary) } }
                if areaLoading && area == nil {
                    Section {
                        ProgressView("Finding \(searchingFor)…").frame(maxWidth: .infinity)
                    }
                }
                if showingList {
                    Section(searchingNow ? "Searching nearby…" : "Closest of each restaurant") {
                        if searchingNow && nearest.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                        ForEach(nearest) { place in NearbyRow(place: place, showChain: true) { nav.showOptions(at: place.chain) } }
                        let missing = chains.filter { places[$0]?.isEmpty == true }.map { store.chainName($0) }
                        if !missing.isEmpty { Text("None within 15 km: \(missing.joined(separator: ", ")).").font(.roboto(.caption)).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle("Map").navigationBarTitleDisplayMode(.inline)
        // Over the map the bar ignores the app-wide Bebas title, so the title is drawn here.
        .toolbar { ToolbarItem(placement: .principal) { Text("Map").font(.display(.title)).accessibilityAddTraits(.isHeader) } }
        .searchable(text: $query, isPresented: $searchActive, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a suburb, address or place")
        .searchSuggestions {
            ForEach(completer.results, id: \.self) { result in
                Button { startSearch(MKLocalSearch.Request(completion: result), name: result.title) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).foregroundStyle(.primary)
                        if !result.subtitle.isEmpty { Text(result.subtitle).font(.roboto(.caption)).foregroundStyle(.secondary) }
                    }
                }.buttonStyle(.plain)
            }
        }
        .onSubmit(of: .search) {
            let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let request = MKLocalSearch.Request(); request.naturalLanguageQuery = name
            startSearch(request, name: name)
        }
        .onChange(of: query) { noMatch = false; completer.update(query, near: location.location) }
        .onAppear { location.request() }
        .task(id: location.location?.timestamp) { await location.load(chains) }
        .onChange(of: location.location?.timestamp) {
            if area == nil, let here = location.location { show(here) }
        }
        .onDisappear { searchTask?.cancel() }
    }

    /// Cancels an older lookup so a second tap or submission always wins.
    private func startSearch(_ request: MKLocalSearch.Request, name: String) {
        searchTask?.cancel()
        let id = UUID()
        searchID = id
        searchingFor = name
        areaLoading = true
        noMatch = false
        searchActive = false
        searchTask = Task { await go(to: request, name: name, id: id) }
    }

    /// Looks up a searched place, moves the map there and finds the restaurants around it.
    private func go(to request: MKLocalSearch.Request, name: String, id: UUID) async {
        request.region = location.location.map { MKCoordinateRegion(center: $0.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000) } ?? australia
        guard let item = (try? await MKLocalSearch(request: request).start())?.mapItems.first else {
            guard id == searchID, !Task.isCancelled else { return }
            noMatch = true
            areaLoading = false
            return
        }
        guard id == searchID, !Task.isCancelled else { return }
        let spot = NearbyPlace.coordinate(of: item)
        let here = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        area = (item.name ?? name, here); areaPlaces = [:]; noMatch = false
        query = ""; searchActive = false; completer.update("", near: nil)
        show(here)
        // Start every independent MapKit lookup at once instead of waiting on ten
        // consecutive network requests. Each lookup validates the active search before updating.
        let lookups = chains.map { chain in
            Task { @MainActor in
                let found = await LocationStore.find(chain, near: here)
                guard id == searchID, !Task.isCancelled else { return }
                areaPlaces[chain] = found
            }
        }
        defer { lookups.forEach { $0.cancel() } }
        for lookup in lookups { await lookup.value }
        guard id == searchID, !Task.isCancelled else { return }
        areaLoading = false
    }

    private func clearArea() {
        searchTask?.cancel()
        searchID = UUID()
        area = nil; areaPlaces = [:]; areaLoading = false
        if let here = location.location { show(here) } else { camera = .userLocation(fallback: .automatic) }
    }

    private func show(_ spot: CLLocation) {
        camera = .region(MKCoordinateRegion(center: spot.coordinate, latitudinalMeters: 5_000, longitudinalMeters: 5_000))
    }
    private var australia: MKCoordinateRegion {
        MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: -26, longitude: 134), latitudinalMeters: 4_500_000, longitudinalMeters: 4_500_000)
    }
}

/// Place suggestions for the map search, as you type.
@MainActor @Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String, near here: CLLocation?) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; completer.cancel(); return }
        if let here { completer.region = MKCoordinateRegion(center: here.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000) }
        completer.queryFragment = text
    }

    private func refresh() { results = Array(completer.results.prefix(8)) }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { refresh() }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { results = [] }
    }
}

/// A found restaurant: name, address, distance, directions and the chain's app.
struct NearbyRow: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    var place: NearbyPlace
    var showChain = false
    /// Shows this restaurant's options on Find; the button is hidden when nil.
    var showOptions: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let big = typeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: big ? 8 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(showChain ? store.chainName(place.chain) : (place.item.name ?? store.chainName(place.chain))).font(.roboto(.headline))
                Spacer()
                Text(place.distanceText).font(.roboto(.subheadline)).foregroundStyle(.secondary).monospacedDigit()
            }
            if !place.address.isEmpty { Text(place.address).font(.roboto(.caption)).foregroundStyle(.secondary) }
            if big {
                PlaceHoursView(place: place)
                DeliveryLine(place: place)
                // Stacked full width at the largest sizes, where they'd shrink to "…".
                VStack(alignment: .leading, spacing: 8) {
                    directions(iconOnly: false)
                    appButton(iconOnly: false)
                }.buttonStyle(.bordered).font(.roboto(.subheadline))
                if let showOptions { optionsButton(showOptions) }
            } else {
                // Hours and delivery share a line, and the actions share the next one, so each restaurant takes about half the height.
                HStack(spacing: 14) {
                    PlaceHoursView(place: place, compact: true).fixedSize()
                    DeliveryLine(place: place, compact: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if let showOptions {
                        optionsButton(showOptions)
                        directions(iconOnly: true)
                        appButton(iconOnly: true)
                    } else {
                        directions(iconOnly: false)
                        appButton(iconOnly: false)
                    }
                }.buttonStyle(.bordered).font(.roboto(.subheadline))
            }
        }.padding(.vertical, 4)
    }

    private func optionsButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconText("Show \(store.chainName(place.chain)) options", systemImage: "list.bullet").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
        }.buttonStyle(.borderedProminent).font(.roboto(.subheadline, weight: .semibold))
    }

    private func directions(iconOnly: Bool) -> some View {
        Button { place.directions() } label: {
            if iconOnly { Image(systemName: "arrow.triangle.turn.up.right.diamond").frame(minWidth: 24, minHeight: 22) }
            else { IconText("Directions", systemImage: "arrow.triangle.turn.up.right.diamond").frame(maxWidth: .infinity, alignment: .leading) }
        }.accessibilityLabel("Directions to \(store.chainName(place.chain))")
    }

    @ViewBuilder private func appButton(iconOnly: Bool) -> some View {
        if let app = ChainPlace.all[place.chain] {
            Button { Task { await location.openApp(app) } } label: {
                if iconOnly { Image(systemName: "arrow.up.forward.app").frame(minWidth: 24, minHeight: 22) }
                else { IconText(app.launchTitle, systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity, alignment: .leading) }
            }.accessibilityLabel(app.launchTitle)
        }
    }
}

/// Opens Apple's place card for a restaurant, which has its opening hours and whether it's open now.
/// Apple doesn't let apps read the hours themselves, so the card shows them.
struct HoursButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { IconText("Opening hours", systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading) }
            .buttonStyle(.borderless).font(.roboto(.subheadline))
            .accessibilityHint("Shows this restaurant's hours and whether it's open now")
    }
}

/// The nearest restaurant of a chain, with its opening hours and delivery estimate. Shown on suggested orders.
/// Nothing shows until location access is allowed; asking is left to the order's own page.
struct NearestPlaceLine: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    let chain: String
    var body: some View {
        if location.isAuthorized, let place = location.nearest(chain) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("\(place.item.name ?? store.chainName(chain)) · \(place.distanceText)").lineLimit(1)
                } icon: { Image(systemName: "location.fill") }
                .font(.roboto(.caption)).foregroundStyle(.secondary)
                PlaceHoursView(place: place, compact: true)
                DeliveryLine(place: place, compact: true)
            }
        }
    }
}

/// Whether a restaurant is likely to deliver to you, as a menu of delivery apps to check and order in.
/// Distance is from your location (or the place you searched on the map).
struct DeliveryLine: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    let place: NearbyPlace
    var compact = false
    var body: some View {
        let delivery = Delivery.estimate(metres: place.distance)
        let name = store.chainName(place.chain)
        Menu {
            Section("The delivery app confirms it for your address") {
                ForEach(DeliveryApp.all) { app in
                    Button(app.name, systemImage: "bag") { if let url = app.search(name) { openURL(url) } }
                }
                if let own = ChainPlace.all[place.chain] {
                    Button("\(own.appName) app", systemImage: "arrow.up.forward.app") { Task { await location.openApp(own) } }
                }
            }
        } label: {
            // Laid out like IconText, so the icon and text line up with "Opening hours" above it.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "scooter").foregroundStyle(.tint)
                Text(delivery.text).foregroundStyle(colour(delivery)).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.roboto(compact ? .caption : .subheadline, weight: .medium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(delivery.text) from \(name), \(place.distanceText) away")
        .accessibilityHint("Shows delivery apps to check and order in")
    }

    private func colour(_ delivery: Delivery) -> Color {
        switch delivery {
        case .likely: .primary   // green is reserved for "Protein target met"; orange still flags "maybe"
        case .maybe: .orange
        case .tooFar: .secondary
        }
    }
}

/// Opening hours for a restaurant, shown in Apple's place card (Apple doesn't let apps read hours themselves).
/// Nothing about the restaurant or the user leaves the phone beyond Apple Maps.
struct PlaceHoursView: View {
    let place: NearbyPlace
    var compact = false
    @State private var appleCard: MKMapItem?
    var body: some View {
        HoursButton { appleCard = place.item }
            .font(.roboto(compact ? .caption : .subheadline, weight: compact ? .semibold : .regular))
            .mapItemDetailSheet(item: $appleCard)
    }
}

/// Explains or asks for location access; shows nothing once a location is available.
struct LocationStatusRows: View {
    @Environment(LocationStore.self) private var location
    @Environment(\.openURL) private var openURL
    var what: String
    var body: some View {
        if location.isDenied {
            Section {
                Text("Location access is off, so Leanr can't find \(what).").foregroundStyle(.secondary)
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
            }
        } else if !location.isAuthorized {
            Section {
                Button { location.request() } label: { Label("Use my location", systemImage: "location") }
                Text("Your location is only used while you're using the app.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        } else if location.failed {
            Section {
                Text("Couldn't get your location.").foregroundStyle(.secondary)
                Button("Try again") { location.request() }
            }
        } else if location.location == nil {
            Section { ProgressView("Finding your location…").frame(maxWidth: .infinity) }.onAppear { location.request() }
        }
    }
}

/// The closest restaurant for one chain, with directions and a button to its app.
struct NearestPlaceSection: View {
    @Environment(LocationStore.self) private var location
    @Environment(AppStore.self) private var store
    var chain: String
    var body: some View {
        if let app = ChainPlace.all[chain] {
            let name = store.chainName(chain)
            if location.isAuthorized, location.location != nil {
                Section("Nearest \(name)") {
                    if let nearest = location.nearest(chain) { NearbyRow(place: nearest) }
                    else if location.places[chain] == nil { ProgressView().frame(maxWidth: .infinity) }
                    else {
                        Text("No \(name) found within 15 km.").foregroundStyle(.secondary)
                        Button { Task { await location.openApp(app) } } label: { Label(app.launchTitle, systemImage: "arrow.up.forward.app") }
                    }
                }
                .task(id: location.location?.timestamp) { await location.load([chain]) }
            } else if location.isAuthorized || location.isDenied {
                LocationStatusRows(what: "the nearest \(name)")
            } else {
                Section("Nearest \(name)") {
                    Button { location.request() } label: { Label("Find the nearest \(name)", systemImage: "location") }
                    Button { Task { await location.openApp(app) } } label: { Label(app.launchTitle, systemImage: "arrow.up.forward.app") }
                    Text("Your location is only used while you're using the app.").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A suggested order from Find: its items, nutrition and where to get it.
struct OrderDetailView: View {
    @Environment(AppStore.self) private var store
    var match: MealMatch
    var body: some View {
        LeanrForm {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.items.map { $0.food.name }.joined(separator: " + ")).font(.display(.title2))
                    Text(store.chainName(match.chain)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
            Section("Nutrition") { NutritionView(total: match.total) }
            NearestPlaceSection(chain: match.chain)
            Section {
                ForEach(match.items) { item in NavigationLink { FoodDetailView(food: item.food) } label: { FoodRow(food: item.food) } }
            } header: { Text("Items") } footer: {
                if match.customised > 0 {
                    Text("Ask for the changes listed after each item’s name when you order. They use \(store.chainName(match.chain).possessive) own figures for each part, so check the food's details for how each was worked out.")
                }
            }
        }.navigationTitle("Order").navigationBarTitleDisplayMode(.inline)
        // Over the map the bar ignores the app-wide Bebas title, so the title is drawn here.
        .toolbar { ToolbarItem(placement: .principal) { Text("Order").font(.display(.title)).accessibilityAddTraits(.isHeader) } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: mealText("Suggested order", match.items)) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("Share order")
                }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    HStack(spacing: 10) {
                        Button { store.logNow(match.items, name: match.items.map(\.food.name).joined(separator: " + ")) } label: {
                            Text("Log it · \(match.total.cal.number) Cal").frame(maxWidth: .infinity)
                        }
                        Button("Add to meal") { store.add(match.items) }.buttonStyle(.bordered)
                    }
                }
            }
    }
}

/// An icon and its text, like a Label. At the largest text sizes a Label with Roboto clipped its last
/// characters ("Openin"), so these rows lay the two out themselves and let the text wrap.
struct IconText: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
