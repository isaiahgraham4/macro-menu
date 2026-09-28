import SwiftUI
import PhotosUI
import Vision
import ImageIO
import UIKit
import VisionKit
import AVFoundation

struct MyFoodsView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var barcode = false
    @State private var recipe = false
    @State private var customising = false
    @State private var editing: Food?
    @State private var editingRecipe: Food?
    @State private var search = ""
    var rows: [Food] {
        let digits = search.filter(\.isNumber)
        if digits.count >= 4, digits.count == search.filter({ !$0.isWhitespace }).count {
            return store.data.foods.filter { $0.barcode?.contains(digits) == true }
        }
        return FoodSearch.filter(store.data.foods, query: search) { $0.name }
    }
    var body: some View {
        LeanrList {
            Section {
                TileRow {
                    Button { adding = true } label: { TileLabel(title: "Add or scan food", systemImage: "plus.viewfinder") }
                    Button { recipe = true } label: { TileLabel(title: "Build a recipe", systemImage: "carrot") }
                    Button { customising = true } label: { TileLabel(title: "Customise an order", systemImage: "slider.horizontal.3") }
                }
                Button { barcode = true } label: { Label("Scan product barcode", systemImage: "barcode.viewfinder") }
            }
            Section("Saved foods & recipes") {
                if rows.isEmpty { ContentUnavailableView("Your own menu", systemImage: "bookmark", description: Text("Save foods, recipes and custom orders. They appear throughout the app.")) }
                ForEach(rows) { food in
                    NavigationLink { FoodDetailView(food: food) } label: { FoodRow(food: food) }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { if food.ingredients != nil { editingRecipe = food } else { editing = food } }.tint(.blue)
                        }
                        .swipeActions { Button("Delete", role: .destructive) { store.change(undo: "Deleted \(food.name)") { $0.foods.removeAll { $0.id == food.id } } } }
                }
            }
        }.navigationTitle("My foods").searchable(text: $search)
            .sheet(isPresented: $barcode) { BarcodeFoodFlow { store.saveFood($0) } }
            .navigationDestination(isPresented: $customising) { BrowseView() }
            .sheet(isPresented: $adding) { NavigationStack { FoodEditor(food: nil) { store.saveFood($0) } } }
            .sheet(item: $editing) { food in NavigationStack { FoodEditor(food: food) { store.saveFood($0) } } }
            .sheet(isPresented: $recipe) { NavigationStack { RecipeEditor() } }
            .sheet(item: $editingRecipe) { food in NavigationStack { RecipeEditor(food: food) } }
    }
}

/// Export and import of all app data, shown in Settings.
struct BackupSection: View {
    @Environment(AppStore.self) private var store
    @State private var importing = false
    @State private var exporting = false
    @State private var document = FoodDocument(data: Data())
    @State private var pending: AppData?
    @State private var confirm = false
    /// Shown here because the main screen's alerts can't appear over the Settings sheet.
    @State private var message: String?
    var body: some View {
        Section {
            Button {
                do { document = FoodDocument(data: try store.export()); exporting = true }
                catch { message = error.localizedDescription }
            } label: { Label("Export all app data", systemImage: "square.and.arrow.up") }
            Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
        } header: {
            Text("Your data")
        } footer: {
            Text("Foods, recipes, saved meals, daily logs, targets and your current meal are saved on this device. Export a backup to transfer them. Native backups and Macro Menu web exports are supported; web exports do not include daily history.")
        }
        .disabled(store.loadError != nil)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Leanr-\(dayKey(Date()))") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                pending = try store.decodeBackup(Data(contentsOf: url)); confirm = true
            } catch { message = "Couldn’t import this backup. \(error.localizedDescription)" }
        }
        .confirmationDialog("Merge this backup?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Import backup") {
                if let pending { message = store.merge(pending) ? "Backup imported." : (store.errorMessage ?? "Couldn’t import this backup."); store.errorMessage = nil }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("Import \(pending?.foods.count ?? 0) foods, \(pending?.meals.count ?? 0) saved meals and \(pending?.logs.count ?? 0) days. Existing entries are kept; matching IDs are updated. A nonempty current meal is kept.")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } }
    }
}

struct FoodEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppStore.self) private var store
    @State private var draft: Food
    let save: (Food) -> Bool
    let savePortion: ((Portion) -> Bool)?
    @State private var servings = 1.0
    @State private var scanBasisConfirmed = true
    @State private var per100 = false
    @State private var servingSize = 100.0
    @State private var servingUnit = "g"
    @State private var energyUnit = "Cal"
    @State private var energy = 0.0
    @State private var photo: PhotosPickerItem?
    @State private var capturingPhoto = false
    @State private var takingPhoto = false
    @State private var cameraDenied = false
    @State private var scanPreview: UIImage?
    @State private var scanning = false
    @State private var scannedText = ""
    @State private var scanError: String?
    @State private var scanColumn = 0
    @State private var saveFailed = false
    @State private var barcodeLookup = false
    @State private var capturingBarcode = false
    @State private var customNutrient = ""
    @State private var customUnit = "mg"
    @State private var customValue = 0.0
    init(food: Food?, scannedProduct: BarcodeProduct? = nil, barcode: String? = nil, savePortion: ((Portion) -> Bool)? = nil, save: @escaping (Food) -> Bool) {
        var initial = scannedProduct?.food ?? food ?? Food(name: "", kj: 0, cal: 0, p: 0, c: nil, f: nil)
        if let barcode { initial.barcode = barcode }
        _draft = State(initialValue: initial); _energy = State(initialValue: initial.cal); self.save = save
        _per100 = State(initialValue: scannedProduct?.per100 ?? false)
        _servingUnit = State(initialValue: scannedProduct?.unit ?? "g")
        _servingSize = State(initialValue: scannedProduct?.per100 == true ? 0 : 100)
        self.savePortion = savePortion
    }
    var result: Food {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ratio = per100 ? servingSize / 100 : 1
        value.cal = (energyUnit == "kJ" ? energy / 4.184 : energy) * ratio
        value.kj = value.cal * 4.184; value.p *= ratio; value.c = value.c.map { $0 * ratio }; value.f = value.f.map { $0 * ratio }
        value.nut = value.nut?.mapValues { $0 * ratio }
        // Saved foods keep one decimal place, like everywhere they're shown.
        value.cal = value.cal.tenth; value.kj = value.cal * 4.184; value.p = value.p.tenth
        value.c = value.c?.tenth; value.f = value.f?.tenth; value.nut = value.nut?.mapValues(\.tenth)
        if per100 { value.serve = "\(servingSize.number) \(servingUnit)" }
        value.barcode = barcodeCode
        return value
    }
    /// The entered barcode's digits, or nil when there's none or it isn't a valid product barcode.
    var barcodeCode: String? { draft.barcode.flatMap { try? BarcodeLookup.validatedCode($0) } }
    var barcodeInvalid: Bool { !(draft.barcode ?? "").isEmpty && barcodeCode == nil }
    var body: some View {
        LeanrForm {
            if draft.name.isEmpty {
                RecentBarcodeSection { applyBarcode($0) }
            }
            Section("Food") {
                TextField("Name", text: $draft.name)
                TextField("Serving size (e.g. 150 g)", text: $draft.serve)
                Toggle("Enter nutrition per 100 g / mL", isOn: $per100)
                if per100 {
                    NumberField(title: "Size of one serving", value: $servingSize)
                    Picker("Unit", selection: $servingUnit) { Text("g").tag("g"); Text("mL").tag("mL") }.pickerStyle(.segmented)
                    Text("Enter the package's serving size to convert the per-100 values.").font(.caption).foregroundStyle(.secondary)
                    Button("Convert to per serving") {
                        let converted = result
                        draft = converted
                        energy = energyUnit == "kJ" ? converted.kj : converted.cal
                        per100 = false
                    }.disabled(!servingSize.isFinite || servingSize <= 0)
                }
                if savePortion != nil {
                    NumberField(title: "Number of servings", value: $servings, places: 2)
                    Text("For example, 0.5 for half a serving or 2 for two servings.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                HStack {
                    Label { TextField("Barcode number", text: Binding(get: { draft.barcode ?? "" }, set: { draft.barcode = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.numberPad).monospacedDigit() } icon: { Image(systemName: "barcode") }
                    if draft.barcode != nil {
                        Button { draft.barcode = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Remove barcode")
                    }
                    Button { capturingBarcode = true } label: { Image(systemName: "camera.viewfinder") }
                        .buttonStyle(.borderless).accessibilityLabel("Scan barcode")
                }
                if barcodeInvalid {
                    Text("Check the digits. Product barcodes have 8, 12, 13 or 14 digits.").font(.caption).foregroundStyle(.orange)
                } else if let code = barcodeCode, let other = BarcodeLookup.match(code, in: store.data.foods.filter { $0.id != draft.id }) {
                    Text("\(other.name) already has this barcode. Scanning it will open that food.").font(.caption).foregroundStyle(.orange)
                }
            } header: { Text("Barcode") } footer: {
                Text("Add the barcode when scanning doesn't find this product. Next time you scan it, Leanr opens this food.")
            }
            Section("Find a packaged food") {
                Button { barcodeLookup = true } label: { Label("Scan product barcode", systemImage: "barcode.viewfinder") }
                    .disabled(scanning)
                if let note = draft.note, note.hasPrefix("Source: Open Food Facts") {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                    Text("Confirm the nutrition basis and serving amount below before saving.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Read a nutrition label") {
                Button { openScanner() } label: {
                    Label("Scan nutrition label", systemImage: "viewfinder")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent)
                    .disabled(scanning || !VNDocumentCameraViewController.isSupported)
                Text("Fit the nutrition panel in the frame. Capture one label, adjust its corners, then tap Save to review.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose existing photo", systemImage: "photo") }
                    .disabled(scanning)
                Button { openScanner(directPhoto: true) } label: { Label("Take photo", systemImage: "camera.fill") }
                    .disabled(scanning || !UIImagePickerController.isSourceTypeAvailable(.camera))
                Text("When calories aren’t listed, Leanr converts kilojoules to calories automatically (kJ ÷ 4.184).")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
                if scanning { ProgressView("Reading label…") }
                if let scanError { Text(scanError).foregroundStyle(.red).font(.roboto(.caption)) }
                if !scannedText.isEmpty {
                    if let scanPreview {
                        Image(uiImage: scanPreview).resizable().scaledToFit().frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("Check every number and whether the column is per serving or per 100 g before saving. Text recognition can misread labels.").font(.roboto(.caption)).foregroundStyle(.orange)
                    DisclosureGroup("Recognised text") { Text(scannedText).font(.roboto(.caption)).textSelection(.enabled) }
                    Picker("Numeric column", selection: $scanColumn) { Text("First").tag(0); Text("Second").tag(1) }.pickerStyle(.segmented)
                        .onChange(of: scanColumn) { fillScannedNutrition() }
                    if !scanBasisConfirmed {
                        Text("The column heading wasn't recognised. Check the selected column and the per-100 toggle before confirming.").font(.caption).foregroundStyle(.orange)
                        Button("I've checked the nutrition basis") { scanBasisConfirmed = true }
                    }
                    let recognised = LabelParser.suggestions(scannedText, column: scanColumn)
                    ForEach(nutrientNames.filter { recognised[$0.key] != nil }, id: \.key) { nutrient in
                        LabeledContent(nutrient.label, value: "\(recognised[nutrient.key]!.number) \(nutrient.unit)")
                    }
                    Button("Fill recognised numbers for review") { fillScannedNutrition() }
                        .disabled(recognised.isEmpty || scanning)
                    if recognised.isEmpty { Text("No nutrition values found in this column. Try the other column or scan again closer to the label.").font(.roboto(.caption)).foregroundStyle(.secondary) }
                } else { Text("Reads text on your device. No image upload or account is needed.").font(.roboto(.caption)).foregroundStyle(.secondary) }
            }
            Section(per100 ? "Nutrition per 100 \(servingUnit)" : "Nutrition per serving") {
                Picker("Energy unit", selection: Binding(get: { energyUnit }, set: { new in
                    guard new != energyUnit else { return }
                    energy = new == "kJ" ? energy * 4.184 : energy / 4.184
                    energyUnit = new
                })) { Text("Calories").tag("Cal"); Text("Kilojoules").tag("kJ") }
                NumberField(title: "Energy (\(energyUnit))", value: $energy)
                NumberField(title: "Protein (g)", value: $draft.p)
                OptionalNumberField(title: "Carbs (g)", value: $draft.c)
                OptionalNumberField(title: "Fat (g)", value: $draft.f)
                OptionalNumberField(title: "Price per serving (AUD)", value: $draft.price, places: 2)
            }
            Section("Optional nutrients") {
                ForEach(nutrientNames.dropFirst(4), id: \.key) { n in
                    OptionalNumberField(title: "\(n.label) (\(n.unit))", value: Binding(get: { draft.nut?[n.key] }, set: { value in
                        if draft.nut == nil { draft.nut = [:] }; draft.nut?[n.key] = value
                    }))
                }
                ForEach((draft.nut ?? [:]).keys.filter { key in !nutrientNames.contains { $0.key == key } }.sorted(), id: \.self) { key in
                    OptionalNumberField(title: key, value: Binding(get: { draft.nut?[key] }, set: { draft.nut?[key] = $0 }))
                }
                DisclosureGroup("Another nutrient") {
                    TextField("Nutrient name", text: $customNutrient)
                    Picker("Unit", selection: $customUnit) { ForEach(["g","mg","µg","%"], id: \.self) { Text($0) } }
                    NumberField(title: "Amount", value: $customValue)
                    Button("Add nutrient") {
                        if draft.nut == nil { draft.nut = [:] }
                        draft.nut?["\(customNutrient) (\(customUnit))"] = customValue; customNutrient = ""; customValue = 0
                    }.disabled(customNutrient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customValue < 0)
                }
            }
            Section("Per-serving preview") { NutritionView(total: Nutrition([Portion(food: result)])) }
            if savePortion != nil {
                Section("Total for \(servings.number) servings") {
                    NutritionView(total: Nutrition([Portion(food: result, quantity: servings.isFinite && servings > 0 ? servings : 0)]))
                }
            }
        }.navigationTitle("Food details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(savePortion == nil ? "Save" : "Log food") {
                        let succeeded = savePortion.map { $0(Portion(food: result, quantity: servings)) } ?? save(result)
                        if succeeded { dismiss() } else { saveFailed = true }
                    }.disabled(!result.isValid || barcodeInvalid || servingSize <= 0 || scanning || !scanBasisConfirmed || !servings.isFinite || servings <= 0 || servings > 10000)
                }
            }
            .alert("Couldn’t save food", isPresented: $saveFailed) { Button("OK", role: .cancel) {} } message: { Text("Your data was not changed. Check available storage and any data recovery message in the app.") }
            .sheet(isPresented: $barcodeLookup) {
                BarcodeScanView(manualEntry: { code in
                    if let code { draft.barcode = code }
                    barcodeLookup = false
                }) { product in
                    applyBarcode(product)
                }
            }
            .sheet(isPresented: $capturingBarcode) { BarcodeCaptureView { draft.barcode = $0 } }
            .fullScreenCover(isPresented: $capturingPhoto) {
                CameraPicker { image in
                    capturingPhoto = false
                    scan(image: image)
                } onCancel: {
                    capturingPhoto = false
                } onError: {
                    capturingPhoto = false
                    scanError = "The camera couldn’t capture this label. Try again or choose an existing photo."
                }
                .ignoresSafeArea()
            }
            .alert("Camera access is off", isPresented: $cameraDenied) {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Allow camera access for Leanr in Settings to scan a nutrition label.") }
            .fullScreenCover(isPresented: $takingPhoto) {
                NutritionPhotoCamera { image in
                    takingPhoto = false
                    scan(image: image)
                } onCancel: { takingPhoto = false }
                    .ignoresSafeArea()
            }
            .onChange(of: photo) { _, selected in
                Task {
                    do {
                        guard let bytes = try await selected?.loadTransferable(type: Data.self) else { return }
                        scanPreview = UIImage(data: bytes)
                        scan(data: bytes)
                    } catch { scanError = "Couldn’t read this image. \(error.localizedDescription)" }
                }
            }
    }

    private func applyBarcode(_ product: BarcodeProduct) {
        let existingID = draft.id, existingBarcode = draft.barcode
        draft = product.food; draft.id = existingID
        if draft.barcode == nil { draft.barcode = existingBarcode }
        per100 = product.per100; servingSize = product.per100 ? 0 : 100; servingUnit = product.unit
        servings = 1; scanBasisConfirmed = true
        energyUnit = "Cal"; energy = product.food.cal
        scannedText = ""; scanPreview = nil; scanError = nil; scanColumn = 0
    }
    private func scan(data: Data) {
        scanning = true; scanError = nil; scannedText = ""; scanColumn = 0
        Task {
            do {
                let text = try await Task.detached(priority: .userInitiated) { try LabelReader.read(data) }.value
                await MainActor.run {
                    scanning = false
                    scannedText = text
                    let layout = LabelParser.layout(text)
                    scanColumn = layout.servingColumn ?? layout.per100Column ?? 0
                    fillScannedNutrition()
                    if text.isEmpty { scanError = "No text found. Try a sharper, better-lit photo." }
                }
            } catch {
                await MainActor.run {
                    scanning = false
                    scanError = "Couldn’t read this image. Try a sharper, better-lit photo."
                }
            }
        }
    }

    private func scan(image: UIImage) {
        // Render upright before encoding; OCR runs off the main thread for both sources.
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let data = upright.jpegData(compressionQuality: 0.95) else { scanError = "Couldn’t read this photo. Try again."; return }
        scanPreview = upright
        scan(data: data)
    }

    private func fillScannedNutrition() {
        let layout = LabelParser.layout(scannedText)
        let values = LabelParser.servingSuggestions(scannedText, column: scanColumn)
        let hundred = layout.per100Column == scanColumn
        per100 = hundred && layout.amount == nil
        servingSize = per100 ? 0 : (layout.amount ?? 100)
        servingUnit = layout.unit
        draft.serve = layout.servingDescription ?? (per100 ? "Enter serving size" : "1 serving")
        scanBasisConfirmed = layout.servingColumn == scanColumn || hundred
        let calories = values["cal"] ?? 0
        energy = energyUnit == "kJ" ? calories * 4.184 : calories
        draft.p = values["p"] ?? 0
        draft.c = values["c"]; draft.f = values["f"]
        draft.nut = values.filter { !["cal", "p", "c", "f"].contains($0.key) }
        servings = 1
        scanError = values["cal"] == nil ? "Energy wasn't recognised. Check the column or enter the label's energy manually." : nil
    }

    private func openScanner(directPhoto: Bool = false) {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed {
                if directPhoto { takingPhoto = true } else { capturingPhoto = true }
            } else { cameraDenied = true }
        }
    }
}

enum LabelReader {
    static func read(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw CocoaError(.fileReadCorruptFile) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString: Any]
        let orientation = CGImagePropertyOrientation(rawValue: properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1) ?? .up
        return try read(image, orientation: orientation)
    }

    static func read(_ image: UIImage) throws -> String {
        guard let cgImage = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
        return try read(cgImage, orientation: image.cgImageOrientation)
    }

    private static func read(_ image: CGImage, orientation: CGImagePropertyOrientation) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.01
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        // Vision often returns the nutrient name and each value as separate boxes.
        // Reassemble horizontal rows before parsing, preserving left-to-right columns.
        var rows: [[VNRecognizedTextObservation]] = []
        for observation in (request.results ?? []).sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let anchor = row.first else { return false }
                return abs(anchor.boundingBox.midY - observation.boundingBox.midY) < min(anchor.boundingBox.height, observation.boundingBox.height) * 0.55
            }) { rows[index].append(observation) }
            else { rows.append([observation]) }
        }
        return rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private struct NutritionPhotoCamera: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let camera = UIImagePickerController()
        camera.sourceType = .camera
        camera.cameraCaptureMode = .photo
        camera.delegate = context.coordinator
        return camera
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: NutritionPhotoCamera
        init(_ parent: NutritionPhotoCamera) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            else { parent.onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    let onError: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let picker = VNDocumentCameraViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, @preconcurrency VNDocumentCameraViewControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 { parent.onImage(scan.imageOfPage(at: 0)) } else { parent.onCancel() }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onError() }
    }
}

struct RecipeEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var food: Food?
    @State private var name = ""
    @State private var servings = 1.0
    @State private var ingredients: [Portion] = []
    @State private var picking = false
    @State private var own = false
    var recipe: Food {
        var value = Nutrition(ingredients).food(name: name, servings: max(servings,0.001), ingredients: ingredients)
        value.id = food?.id ?? value.id; value.serve = "1 of \(servings.number) servings"
        return value
    }
    var body: some View {
        LeanrForm {
            Section { TextField("Recipe name", text: $name); NumberField(title: "Recipe makes (servings)", value: $servings, places: 2) }
            Section("Ingredients") {
                ForEach(ingredients) { item in
                    VStack(alignment: .leading) {
                        Text(item.food.name).font(.roboto(.headline))
                        NumberField(title: "Servings of ingredient", value: Binding(get: { ingredients.first { $0.id == item.id }?.quantity ?? 1 }, set: { quantity in
                            if let i = ingredients.firstIndex(where: { $0.id == item.id }) { ingredients[i].quantity = quantity }
                        }), places: 2)
                    }
                }.onDelete { ingredients.remove(atOffsets: $0) }
                Button("Choose a food") { picking = true }
                Button("Enter ingredient nutrition") { own = true }
            }
            if !ingredients.isEmpty {
                Section("Whole recipe") { NutritionView(total: Nutrition(ingredients), details: false) }
                Section("Per serving") { NutritionView(total: Nutrition([Portion(food: recipe)])) }
            }
        }.navigationTitle(food == nil ? "Build a recipe" : "Edit recipe")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if store.saveFood(recipe) { dismiss() } }.disabled(!recipe.isValid || ingredients.isEmpty || servings <= 0) }
            }
            .onAppear { if let food, ingredients.isEmpty { name = food.name; servings = food.recipeYield ?? 1; ingredients = food.ingredients ?? [] } }
            .sheet(isPresented: $picking) { NavigationStack { BrowseView { portion in ingredients.append(portion); picking = false }.toolbar { Button("Done") { picking = false } } } }
            .sheet(isPresented: $own) { NavigationStack { FoodEditor(food: nil) { ingredients.append(Portion(food: $0)); own = false; return true } } }
    }
}
