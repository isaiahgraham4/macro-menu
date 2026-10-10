import SwiftUI
import PhotosUI

/// Photo of your meal: Apple Intelligence names the foods, Leanr finds them in its own data, and you check each before logging.
struct MealPhotoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mealTime: MealTime
    /// Logs the chosen portions under one name; false if it couldn't be saved.
    let log: (_ portions: [Portion], _ name: String) -> Bool

    /// One food seen in the photo, and what to log for it.
    struct Row: Identifiable {
        let id = UUID()
        var seen: SeenFood
        var matches: [Food]
        /// The match to log, or nil to leave it out.
        var chosen: String?
        var quantity: Double
        var food: Food? { matches.first { $0.id == chosen } }
    }

    private enum Phase: Equatable { case choosing, looking, done, failed(String) }
    @State private var phase = Phase.choosing
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var camera = false
    @State private var rows: [Row] = []
    @State private var searching: Row.ID?
    @State private var failed = false

    private var portions: [Portion] { rows.compactMap { row in row.food.map { Portion(food: $0, quantity: row.quantity) } } }

    var body: some View {
        LeanrList {
            if let image {
                Section {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Your photo")
                    if phase == .looking { ProgressView("Looking at your photo…").frame(maxWidth: .infinity) }
                    if case .failed(let message) = phase { Text(message).foregroundStyle(.secondary) }
                    if phase != .looking { Button("Use a different photo", systemImage: "arrow.counterclockwise") { reset() } }
                }
            } else {
                Section {
                    if let reason = MealPhoto.unavailableReason {
                        Text(reason).foregroundStyle(.secondary)
                    } else {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label("Take a photo", systemImage: "camera") }
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                    }
                } footer: {
                    Text("Apple Intelligence names the foods on your iPhone. The photo isn't saved or sent anywhere. The figures are Leanr's own, so check each match and how much you had.")
                }
            }
            if phase == .done {
                if rows.isEmpty {
                    Section { Text("No food found in this photo. Try one taken from above, with the food filling the frame.").foregroundStyle(.secondary) }
                }
                ForEach($rows) { $row in
                    Section {
                        if row.matches.isEmpty {
                            Text("Not in Leanr yet.").foregroundStyle(.secondary)
                        } else {
                            Picker("Log as", selection: $row.chosen) {
                                ForEach(row.matches) { food in
                                    Text(food.name).tag(Optional(food.id))
                                }
                                Text("Don't log this").tag(String?.none)
                            }
                            if let food = row.food {
                                NumberField(title: "Servings", value: $row.quantity, places: 2, spokenTitle: "Servings of \(food.name)")
                                Text("\(store.chainName(food.chain)) · \(food.serve.isEmpty ? "1 serving" : food.serve) each · \(Nutrition([Portion(food: food, quantity: row.quantity)]).cal.rounded().number) Cal")
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                        }
                        Button("Search for it instead", systemImage: "magnifyingglass") { searching = row.id }
                    } header: {
                        Text("\(row.seen.count > 1 ? "\(row.seen.count) × " : "")\(row.seen.name)\(row.seen.brand.map { " · \($0)" } ?? "")")
                    }
                }
            }
        }
        .navigationTitle("Photo of your meal").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .safeAreaInset(edge: .bottom) {
            if phase == .done && !portions.isEmpty {
                BottomActionBar {
                    Button {
                        if log(portions, portions.map(\.food.name).joined(separator: " + ")) { dismiss() } else { failed = true }
                    } label: {
                        Text("Log \(portions.count) to \(mealTime.title) · \(Nutrition(portions).cal.rounded().number) Cal").frame(maxWidth: .infinity)
                    }.disabled(!portions.allSatisfy(\.isValid))
                }
            }
        }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task {
                if let data = try? await pickerItem.loadTransferable(type: Data.self), let picked = UIImage(data: data) { look(at: picked) }
                else { phase = .failed("That photo couldn't be opened. Try another.") }
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { taken in camera = false; if let taken { look(at: taken) } }.ignoresSafeArea()
        }
        .sheet(item: Binding(get: { searching.map(SearchTarget.init) }, set: { searching = $0?.id })) { target in
            NavigationStack {
                BrowseView(pick: { portion in
                    if let index = rows.firstIndex(where: { $0.id == target.id }) {
                        rows[index].matches.removeAll { $0.id == portion.food.id }
                        rows[index].matches.insert(portion.food, at: 0)
                        rows[index].chosen = portion.food.id
                        rows[index].quantity = portion.quantity
                    }
                    searching = nil
                }, pickTitle: "Use this", initialSearch: rows.first { $0.id == target.id }?.seen.name ?? "")
                .toolbar { Button("Done") { searching = nil } }
            }
        }
        .alert("Couldn’t log that", isPresented: $failed) { Button("OK", role: .cancel) {} } message: {
            Text("Your data was not changed. Check available storage and try again.")
        }
    }

    private struct SearchTarget: Identifiable { let id: Row.ID }

    private func reset() { image = nil; pickerItem = nil; rows = []; phase = .choosing }

    private func look(at picked: UIImage) {
        image = picked; rows = []; phase = .looking
        guard #available(iOS 27.0, *), let cgImage = picked.normalisedCGImage else { phase = .failed("That photo couldn't be read."); return }
        let foods = store.foods
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: store.chainName(Food.everyday)]) { a, _ in a }
        Task {
            do {
                let seen = try await MealPhoto.foods(in: cgImage)
                let found = await Task.detached(priority: .userInitiated) {
                    seen.map { item in (item, MealPhoto.matches(for: item, in: foods, chainNames: names)) }
                }.value
                rows = found.map { item, matches in Row(seen: item, matches: matches, chosen: matches.first?.id, quantity: Double(item.count)) }
                phase = .done
            } catch {
                phase = .failed(MealPhoto.unavailableReason ?? "Apple Intelligence couldn't look at this photo. Try again, or search for the food instead.")
            }
        }
    }
}

private extension UIImage {
    /// The photo upright, as the model expects, scaled down so recognising stays quick.
    var normalisedCGImage: CGImage? {
        let longest = max(size.width, size.height)
        let scale = longest > 1024 ? 1024 / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }.cgImage
    }
}

/// The system camera, for one photo.
private struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
