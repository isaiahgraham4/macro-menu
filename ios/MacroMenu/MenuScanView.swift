import SwiftUI
import PhotosUI
import VisionKit

/// Scan a menu: photograph any restaurant's menu and Takeawise estimates each dish from its own foods. Your iPhone reads the
/// photo and nothing is sent anywhere. Figures are estimates unless the restaurant's own item was found, and say so.
struct MenuScanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealTime: MealTime
    /// Logs the chosen portions under one name; false if it couldn't be saved.
    let log: (_ portions: [Portion], _ name: String) -> Bool

    /// One dish on the menu and what's been decided about it.
    struct Row: Identifiable, Equatable {
        var id: UUID { dish.id }
        var dish: MenuDish
        var estimate: MenuEstimate?
        var size = PortionSize.regular
        var picked = false
        var total: Nutrition? { estimate?.total(size) }
        var portion: Portion? { estimate?.portion(named: dish.name, size: size) }

        static func == (a: Row, b: Row) -> Bool { a.dish == b.dish && a.estimate == b.estimate && a.size == b.size && a.picked == b.picked }
    }

    private enum Phase: Equatable { case choosing, reading, done, failed(String) }
    private enum Order: String, CaseIterable, Identifiable {
        case menu = "Menu", protein = "Protein", lightest = "Lightest"
        var id: Self { self }
    }

    @State private var phase = Phase.choosing
    @State private var pages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var rows: [Row] = []
    @State private var restaurant: String?
    @State private var chain: String?
    @State private var estimator: MenuEstimator?
    @State private var order = Order.menu
    @State private var opened: Row.ID?
    @State private var refining = false
    @State private var failed = false

    private var portions: [Portion] { rows.filter(\.picked).compactMap(\.portion) }
    private var caloriesLeft: Double? { Assistant.remaining(store.data, goals: store.goals).calories }

    var body: some View {
        LeanrList {
            if pages.isEmpty {
                choosing
            } else {
                photos
            }
            if phase == .done {
                if rows.isEmpty {
                    Section { Text("No dishes found in this photo. Try again with the menu flat, in good light and filling the frame.").foregroundStyle(.secondary) }
                } else {
                    results
                }
            }
        }
        .navigationTitle("Scan a menu").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            if !portions.isEmpty {
                BottomActionBar {
                    Button {
                        if log(portions, portions.map(\.food.name).joined(separator: " + ")) { dismiss() } else { failed = true }
                    } label: {
                        Text("Log \(portions.count) to \(mealTime.title) · \(Nutrition(portions).cal.rounded().number) Cal").frame(maxWidth: .infinity)
                    }.disabled(!portions.allSatisfy(\.isValid))
                }
            }
        }
        .onChange(of: pickerItems) {
            guard !pickerItems.isEmpty else { return }
            let items = pickerItems
            phase = .reading
            Task {
                var picked: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { picked.append(image) }
                }
                if picked.isEmpty { phase = .failed("Those photos couldn't be opened. Try others."); pages = []; return }
                read(picked)
            }
        }
        .fullScreenCover(isPresented: $camera) {
            MenuCamera { scanned in camera = false; if !scanned.isEmpty { read(scanned) } }.ignoresSafeArea()
        }
        .sheet(item: Binding(get: { opened.map(Opened.init) }, set: { opened = $0?.id })) { target in
            if let index = rows.firstIndex(where: { $0.id == target.id }) {
                NavigationStack {
                    MenuDishDetail(row: $rows[index], caloriesLeft: caloriesLeft) { dish in estimator?.estimate(dish, chain: chain) }
                }
            }
        }
        .alert("Couldn’t log that", isPresented: $failed) { Button("OK", role: .cancel) {} } message: {
            Text("Your data was not changed. Check available storage and try again.")
        }
    }

    private struct Opened: Identifiable { let id: Row.ID }

    // MARK: Sections

    private var choosing: some View {
        Section {
            if VNDocumentCameraViewController.isSupported {
                Button { camera = true } label: { Label("Photograph the menu", systemImage: "camera") }
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: MenuReader.pageLimit, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
            }
            if phase == .reading { ProgressView("Reading the menu…").frame(maxWidth: .infinity) }
            if case .failed(let message) = phase { Text(message).foregroundStyle(.secondary) }
        } footer: {
            Text("Works with any restaurant, up to \(MenuReader.pageLimit) pages. Your iPhone reads the menu, and nothing is saved or sent anywhere.")
        }
    }

    private var photos: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Image(uiImage: pages[index]).resizable().scaledToFit().frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Menu page \(index + 1)")
                    }
                }
            }
            if phase == .reading { ProgressView("Reading the menu…").frame(maxWidth: .infinity) }
            if case .failed(let message) = phase { Text(message).foregroundStyle(.secondary) }
            if phase != .reading { Button("Scan a different menu", systemImage: "arrow.counterclockwise") { reset() } }
        }
    }

    @ViewBuilder private var results: some View {
        Section {
            Picker("Order", selection: $order) { ForEach(Order.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            if let left = Assistant.leftText(store.data, goals: store.goals) {
                Label("Left today: \(left)", systemImage: "fork.knife").font(.roboto(.subheadline))
            }
            if refining { ProgressView("Looking closer at the dishes it couldn't place…").font(.roboto(.caption)) }
        } footer: {
            Text(summary)
        }
        ForEach(groups, id: \.title) { group in
            Section(group.title) {
                ForEach(group.rows) { row in rowView(row) }
            }
        }
    }

    /// How many dishes, from where, and how far to trust them.
    private var summary: String {
        let place = restaurant.map { " at \($0)" } ?? ""
        let count = "\(rows.count) \(rows.count == 1 ? "dish" : "dishes")\(place)."
        if rows.contains(where: { $0.estimate?.basis == .official }), rows.allSatisfy({ $0.estimate?.basis == .official || $0.estimate == nil }) {
            return "\(count) These are the restaurant's own figures."
        }
        return "\(count) Figures are estimates of a typical serve and can be well off, so tap a dish to see what's counted. Allergens aren't checked: ask the restaurant."
    }

    private var groups: [(title: String, rows: [Row])] {
        guard order == .menu else {
            let known = rows.filter { $0.estimate != nil }
            let sorted = order == .protein
                ? known.sorted { ($0.total?.p ?? 0) > ($1.total?.p ?? 0) }
                : known.sorted { ($0.total?.cal ?? 0) < ($1.total?.cal ?? 0) }
            let title = order == .protein ? "Most protein" : "Fewest calories"
            return [(title, sorted)] + (rows.count > known.count ? [("No estimate", rows.filter { $0.estimate == nil })] : [])
        }
        var titles: [String] = []
        for row in rows where !titles.contains(row.dish.section ?? "Menu") { titles.append(row.dish.section ?? "Menu") }
        return titles.map { title in (title, rows.filter { ($0.dish.section ?? "Menu") == title }) }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { toggle(row) } label: {
                Image(systemName: row.picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(row.picked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.borderless).disabled(row.estimate == nil)
            .accessibilityLabel(row.picked ? "Leave out \(row.dish.name)" : "Choose \(row.dish.name)")
            Button { opened = row.id } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.dish.name).font(.roboto(.headline)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if let price = row.dish.price {
                            Text("$\(price.number)").font(.roboto(.subheadline)).foregroundStyle(.secondary)
                        }
                    }
                    if let total = row.total, let estimate = row.estimate {
                        Text("\(estimate.isExact ? "" : "≈ ")\(total.cal.rounded().number) Cal · \(total.p.rounded().number) g protein")
                            .font(.roboto(.subheadline, weight: .semibold)).foregroundStyle(.primary)
                        Text("\(total.c.rounded().number) g carbs · \(total.f.rounded().number) g fat · \(estimate.label)")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                        if let left = caloriesLeft, left > 0, total.cal <= left {
                            Text("Fits what's left today").font(.roboto(.caption, weight: .medium)).foregroundStyle(.tint)
                        }
                    } else {
                        Text("No estimate. Tap to fix the wording or search for it.").font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows what's counted")
        }
    }

    // MARK: Reading

    private func toggle(_ row: Row) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].picked.toggle()
    }

    private func reset() {
        pages = []; pickerItems = []; rows = []; restaurant = nil; chain = nil; order = .menu; phase = .choosing
    }

    private func read(_ scanned: [UIImage]) {
        pages = Array(scanned.prefix(MenuReader.pageLimit)); rows = []; phase = .reading
        let foods = store.foods, names = store.chainNames
        Task {
            do {
                let menu = try await MenuReader.read(pages)
                let worked = await Task.detached(priority: .userInitiated) {
                    let estimator = MenuEstimator(foods: foods, chainNames: names)
                    let chain = estimator.chain(for: menu.restaurant)
                    return (estimator, chain, menu.dishes.map { Row(dish: $0, estimate: estimator.estimate($0, chain: chain)) })
                }.value
                estimator = worked.0; chain = worked.1; rows = worked.2
                restaurant = menu.restaurant
                phase = .done
                await refine()
            } catch {
                phase = .failed("Couldn't read this menu. Try another photo.")
            }
        }
    }

    /// Where the iPhone has Apple Intelligence, asks what's in the dishes Takeawise had little or nothing to go on for.
    private func refine() async {
        guard MenuModel.isAvailable, let estimator else { return }
        let unsure = rows.filter { $0.estimate == nil || $0.estimate?.basis == .rough }.prefix(MenuModel.dishLimit)
        guard !unsure.isEmpty else { return }
        refining = true
        defer { refining = false }
        for row in unsure {
            let parts = await MenuModel.ingredients(of: row.dish)
            guard !Task.isCancelled else { return }
            // Only a row left as it was: a food picked or something turned off in the meantime stands.
            if let better = estimator.estimate(suggested: parts, section: row.dish.section),
               let index = rows.firstIndex(where: { $0.id == row.id && $0.dish == row.dish && $0.estimate == row.estimate }) {
                rows[index].estimate = better
            }
        }
    }
}

/// One dish: what's counted, how sure the figure is, and the ways to put it right.
private struct MenuDishDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var row: MenuScanView.Row
    let caloriesLeft: Double?
    let estimate: (MenuDish) -> MenuEstimate?
    @State private var name = ""
    @State private var details = ""
    @State private var searching = false

    private var edited: Bool { name != row.dish.name || details != row.dish.details }

    var body: some View {
        LeanrList {
            if let total = row.total, let estimate = row.estimate {
                Section {
                    NutritionView(total: total, details: false)
                } footer: {
                    Text(rangeText(total, estimate))
                }
                if !estimate.isExact {
                    Section {
                        Picker("Portion", selection: $row.size) { ForEach(PortionSize.allCases) { Text($0.title).tag($0) } }
                            .pickerStyle(.segmented)
                    } header: { Text("Serve size") }
                    if let components = row.estimate?.components, !components.isEmpty {
                        Section {
                            ForEach(components.indices, id: \.self) { index in componentRow(index) }
                        } header: {
                            Text("What's counted")
                        } footer: {
                            Text("Turn off anything that isn't in your dish.")
                        }
                    }
                }
            } else {
                Section { Text("Takeawise can't tell what's in this from the words on the menu. Fix the wording below if it misread them, or search for something close.").foregroundStyle(.secondary) }
            }
            Section {
                TextField("Dish", text: $name)
                TextField("What the menu says is in it", text: $details, axis: .vertical).lineLimit(2...5)
                if edited {
                    Button("Work it out again", systemImage: "arrow.clockwise") { rework() }
                }
            } header: {
                Text("What the menu says")
            } footer: {
                Text("Check this against the menu. Photos can be misread.")
            }
            Section {
                Button("Search for it instead", systemImage: "magnifyingglass") { searching = true }
            }
        }
        .navigationTitle(row.dish.name).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { name = row.dish.name; details = row.dish.details }
        .sheet(isPresented: $searching) {
            NavigationStack {
                BrowseView(pick: { portion in
                    row.estimate = MenuEstimate(components: [MenuComponent(food: portion.food, quantity: portion.quantity)], basis: .chosen)
                    row.size = .regular
                    searching = false
                }, pickTitle: "Use this", initialSearch: row.dish.name)
                .toolbar { Button("Done") { searching = false } }
            }
        }
    }

    private func componentRow(_ index: Int) -> some View {
        let component = row.estimate?.components[index]
        let scale = row.size.factor
        return Toggle(isOn: Binding(get: { row.estimate?.components[index].isOn ?? false }, set: { row.estimate?.components[index].isOn = $0 })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(component?.food.name ?? "").font(.roboto(.subheadline))
                if let component {
                    Text("\(component.grams.map { "\(($0 * scale).rounded().number) g · " } ?? "")\((component.food.cal * component.quantity * scale).rounded().number) Cal")
                        .font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Typical serve. Could be about 640 to 960 Cal."
    private func rangeText(_ total: Nutrition, _ estimate: MenuEstimate) -> String {
        guard estimate.spread > 0 else { return estimate.label + "." }
        func nearest(_ value: Double) -> String { ((value / 10).rounded() * 10).number }
        return "\(estimate.label). Could be about \(nearest(total.cal * (1 - estimate.spread))) to \(nearest(total.cal * (1 + estimate.spread))) Cal, depending on the kitchen."
    }

    private func rework() {
        row.dish.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        row.dish.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        row.estimate = estimate(row.dish)
        row.size = .regular
        if row.estimate == nil { row.picked = false }
    }
}

/// The document camera, which straightens each page and takes several in a row.
private struct MenuCamera: UIViewControllerRepresentable {
    let done: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let camera = VNDocumentCameraViewController()
        camera.delegate = context.coordinator
        return camera
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let done: ([UIImage]) -> Void
        init(done: @escaping ([UIImage]) -> Void) { self.done = done }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            done((0..<scan.pageCount).map(scan.imageOfPage))
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { done([]) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { done([]) }
    }
}
