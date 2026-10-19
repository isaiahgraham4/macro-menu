import SwiftUI
import PhotosUI

/// Photo of your meal: Apple Intelligence names the foods, Leanr finds them in its own data, and you check each before logging.
struct MealPhotoView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationStore.self) private var location
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
        /// For everyday and your own foods: how big each one was. Changing it sets the servings.
        var size: PortionSize
        /// Why a match was ticked for you, when it wasn't the usual first match.
        var note: String?
        /// Came from what you wrote about the photo, not from the photo itself.
        var fromNote = false
        var food: Food? { matches.first { $0.id == chosen } }
        /// Servings for the chosen food: the count, scaled by the portion size where sizes apply.
        func servings(for food: Food?) -> Double {
            Double(seen.count) * (food.map(PortionSize.applies) == true ? size.factor : 1)
        }
    }

    private enum Phase: Equatable { case choosing, looking, done, failed(String) }
    @State private var phase = Phase.choosing
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var camera = false
    @State private var rows: [Row] = []
    @State private var searching: Row.ID?
    @State private var failed = false
    @State private var engine = MealPhoto.Engine.appleIntelligence
    @State private var scanningBarcode = false
    @State private var noteText = ""
    @State private var readingNote = false

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
                // What you write is trusted over what the photo looks like: photos can't see tofu, or tell a bowl from soup.
                Section {
                    HStack(spacing: 10) {
                        TextField("What's in it? e.g. tofu, rice and salad", text: $noteText)
                            .submitLabel(.done).onSubmit { applyNote() }
                        if !noteText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button { applyNote() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                                .buttonStyle(.borderless).disabled(readingNote || phase == .looking)
                                .accessibilityLabel("Use what you wrote")
                        }
                    }
                } footer: {
                    Text(readingNote ? "Reading what you wrote…" : "Optional. Name the foods and Leanr ticks those instead of its guesses.")
                }
            } else {
                Section {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { camera = true } label: { Label("Take a photo", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
                } footer: {
                    Text("Your iPhone names the foods in the photo. Nothing is saved or sent anywhere. The figures are Leanr's own, so check each match and how much you had.")
                }
            }
            if phase == .done {
                if rows.isEmpty {
                    Section { Text("No food found in this photo. Try one taken from above, with the food filling the frame, or search for it instead.").foregroundStyle(.secondary) }
                } else {
                    Section {
                        Text(engine == .appleIntelligence
                             ? "Named by Apple Intelligence on your iPhone. Check each match and how much you had."
                             : "Named by your iPhone's built-in image recognition\(engine == .both ? " and Apple Intelligence" : ""). It can't count, so each food is one serving: check the amounts.")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                }
                ForEach($rows) { $row in
                    Section {
                        if row.matches.isEmpty {
                            Text("Not in Leanr yet.").foregroundStyle(.secondary)
                        } else {
                            if row.chosen == nil {
                                Text(row.seen.reason ?? (row.seen.agreed
                                     ? "No everyday food matched. These restaurant items have similar names. Pick one only if that's what you had."
                                     : "Only one of the two readings saw this, so it isn't ticked. Choose it if it's on the plate."))
                                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            if let note = row.note, row.chosen != nil {
                                Label(note, systemImage: "checkmark.circle").font(.roboto(.caption)).foregroundStyle(.secondary)
                            }
                            // Picking here resets the amount; a food picked from search keeps the amount chosen there.
                            Picker("Log as", selection: Binding(get: { row.chosen }, set: { row.chosen = $0; row.quantity = row.servings(for: row.food); row.note = nil })) {
                                ForEach(row.matches) { food in
                                    Text(food.name).tag(Optional(food.id))
                                }
                                Text("Don't log this").tag(String?.none)
                            }
                            if let food = row.food {
                                if PortionSize.applies(to: food) {
                                    Picker("Portion", selection: Binding(get: { row.size }, set: { row.size = $0; row.quantity = row.servings(for: row.food) })) {
                                        ForEach(PortionSize.allCases) { Text($0.title).tag($0) }
                                    }
                                    .pickerStyle(.segmented)
                                    .accessibilityLabel("Portion size of \(food.name)")
                                }
                                NumberField(title: "Servings", value: $row.quantity, places: 2, spokenTitle: "Servings of \(food.name)")
                                Text(detail(food, quantity: row.quantity)).font(.roboto(.caption)).foregroundStyle(.secondary)
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
                        if log(portions, portions.map(\.food.name).joined(separator: " + ")) {
                            remember()
                            dismiss()
                        } else { failed = true }
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
            if FoodCamera.isSupported {
                FoodCamera(photo: { taken in camera = false; if let taken { look(at: taken) } },
                           barcode: { camera = false; scanningBarcode = true })
            } else {
                CameraPicker { taken in camera = false; if let taken { look(at: taken) } }.ignoresSafeArea()
            }
        }
        // A packet in shot: the product scanner finds its exact figures, then logs it like any other way in.
        .sheet(isPresented: $scanningBarcode) {
            BarcodeFoodFlow(savePortion: { portion in
                guard log([portion], portion.food.name) else { return false }
                dismiss(); return true
            }) { food in
                guard log([Portion(food: food)], food.name) else { return false }
                dismiss(); return true
            }
        }
        // Where you are, if location is already allowed (it's never asked for here), so a nearby restaurant's items go first.
        .task {
            guard location.isAuthorized else { return }
            location.request()
            await location.load(store.catalog.chains.map(\.id).filter { ChainPlace.all[$0] != nil })
        }
        .sheet(item: Binding(get: { searching.map(SearchTarget.init) }, set: { searching = $0?.id })) { target in
            NavigationStack {
                BrowseView(pick: { portion in
                    if let index = rows.firstIndex(where: { $0.id == target.id }) {
                        rows[index].matches.removeAll { $0.id == portion.food.id }
                        rows[index].matches.insert(portion.food, at: 0)
                        rows[index].chosen = portion.food.id
                        rows[index].quantity = portion.quantity
                        rows[index].note = nil
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

    private func reset() { image = nil; pickerItem = nil; rows = []; noteText = ""; phase = .choosing }

    /// Reads what you wrote the way "Describe your meal" does, and lists those foods first, ticked. Photo foods your words
    /// cover give way to them; the rest stay listed but unticked.
    private func applyNote() {
        let words = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, !readingNote, phase != .looking else { return }
        readingNote = true
        let foods = store.foods, names = store.chainNames, nearby = nearbyChain
        let known = Set(foods.map { " " + FoodSearch.tokens($0.name).filter { !["and", "with", "n"].contains($0) }.joined(separator: " ") + " " })
        Task {
            var phrases = await MealWords.read(words)
            if phrases.isEmpty {
                phrases = FoodPhrase.meal(words) { candidate in
                    let wanted = " " + FoodSearch.tokens(candidate).filter { !["and", "with", "n"].contains($0) }.joined(separator: " ") + " "
                    return known.contains { $0.contains(wanted) }
                }
            }
            let found = await Task.detached(priority: .userInitiated) {
                phrases.map { phrase in (phrase, MealPhoto.matches(for: phrase.seen, in: foods, chainNames: names, nearby: nearby)) }
            }.value
            let noted = found.map { phrase, matches in
                let pick = FoodPhrase.preselected(from: matches, for: phrase, chainNames: names)
                var row = Row(seen: phrase.seen, matches: matches, chosen: pick?.id,
                              quantity: pick.map { phrase.servings(of: $0).servings } ?? Double(phrase.seen.count), size: .regular, note: nil)
                row.fromNote = true
                return row
            }
            var kept: [Row] = []
            for var row in rows where !row.fromNote {
                if noted.contains(where: { MealPhoto.same($0.seen, row.seen) }) { continue }
                row.chosen = nil; row.note = nil
                row.seen.agreed = false
                row.seen.reason = "Not in what you wrote, so it isn't ticked."
                kept.append(row)
            }
            rows = noted + kept
            phase = .done
            readingNote = false
        }
    }

    private func look(at picked: UIImage) {
        image = picked; rows = []; phase = .looking
        guard let cgImage = picked.normalisedCGImage else { phase = .failed("That photo couldn't be read."); return }
        let foods = store.foods
        let names = Dictionary(store.catalog.chains.map { ($0.id, $0.name) }) { a, _ in a }.merging([Food.everyday: store.chainName(Food.everyday)]) { a, _ in a }
        let nearby = nearbyChain
        let choices = PhotoMemory.load()
        Task {
            do {
                let recognised = try await MealPhoto.recognise(cgImage)
                let found = await Task.detached(priority: .userInitiated) {
                    recognised.foods.map { item in (item, MealPhoto.matches(for: item, in: foods, chainNames: names, nearby: nearby)) }
                }.value
                engine = recognised.engine
                rows = found.map { item, matches in row(for: item, matches: matches, foods: foods, names: names, nearby: nearby, choices: choices) }
                phase = .done
            } catch {
                phase = .failed("Couldn't look at this photo. Try another, or search for the food instead.")
            }
        }
    }

    /// One row, ticked with what you logged last time for this food if there is one, otherwise the usual pick.
    private func row(for item: SeenFood, matches: [Food], foods: [Food], names: [String: String], nearby: String?, choices: [String: PhotoMemory.Choice]) -> Row {
        if let remembered = PhotoMemory.choice(for: item, in: choices), item.agreed,
           let food = matches.first(where: { $0.id == remembered.foodID }) ?? foods.first(where: { $0.id == remembered.foodID }) {
            let list = [food] + matches.filter { $0.id != food.id }.prefix(3)
            return Row(seen: item, matches: list, chosen: food.id, quantity: remembered.perItem * Double(item.count), size: .regular,
                       note: "Ticked as what you logged for this last time")
        }
        let pick = MealPhoto.preselected(from: matches, for: item, chainNames: names, nearby: nearby)
        var row = Row(seen: item, matches: matches, chosen: pick?.id, quantity: 0, size: item.size, note: nil)
        row.quantity = row.servings(for: pick)
        if let pick, let nearby, pick.chain == nearby, MealPhoto.chain(for: item.brand, chainNames: names) == nil {
            row.note = "Ticked because you're at \(store.chainName(nearby))"
        }
        return row
    }

    /// The restaurant you're at: one of Leanr's chains within about 150 m, from the places already found near you.
    private var nearbyChain: String? {
        guard location.isAuthorized else { return nil }
        return location.places.values.compactMap(\.first).filter { $0.distance <= 150 }.min { $0.distance < $1.distance }?.chain
    }

    /// What each logged photo food was, so the same food in a later photo is ticked straight away.
    private func remember() {
        let logged = rows.compactMap { row in row.food.map { (seen: row.seen, food: $0, quantity: row.quantity) } }
        PhotoMemory.save(PhotoMemory.remembering(logged, in: PhotoMemory.load()))
    }

    /// Where it's from, the serving, roughly how much that is by weight when the serving says, and the calories.
    private func detail(_ food: Food, quantity: Double) -> String {
        var parts = ["\(store.chainName(food.chain)) · \(food.serve.isEmpty ? "1 serving" : food.serve) each"]
        if let weight = food.servingWeight, quantity != 1 { parts.append("about \((weight.0 * quantity).rounded().number) \(weight.1)") }
        parts.append("\(Nutrition([Portion(food: food, quantity: quantity)]).cal.rounded().number) Cal")
        return parts.joined(separator: " · ")
    }
}

private extension UIImage {
    /// The photo upright, as the model expects, scaled down so recognising stays quick but each cut-out keeps its detail.
    var normalisedCGImage: CGImage? {
        let longest = max(size.width, size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
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
