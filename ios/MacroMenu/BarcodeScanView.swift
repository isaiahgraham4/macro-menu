import SwiftUI
import VisionKit
import Vision
import AVFoundation

/// Present the scanner immediately; open the editor only after choosing a product or manual entry.
struct BarcodeFoodFlow: View {
    var savePortion: ((Portion) -> Bool)? = nil
    let save: (Food) -> Bool
    @State private var product: BarcodeProduct?
    @State private var barcode: String?
    @State private var editing = false

    var body: some View {
        if editing {
            NavigationStack { FoodEditor(food: nil, scannedProduct: product, barcode: barcode, savePortion: savePortion, save: save) }
        } else {
            // Logging (from Today) or saving (from My foods) can happen right on the scan screen; the editor is there for changes.
            BarcodeScanView(dismissAfterUse: false, manualEntry: { barcode = $0; editing = true },
                            quick: savePortion.map { .log($0) } ?? .save) {
                product = $0; editing = true
            }
        }
    }
}

struct BarcodeScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppStore.self) private var store
    var dismissAfterUse = true
    /// Called with the barcode that wasn't found, if any, so the food can be entered by hand and keep it.
    var manualEntry: ((String?) -> Void)? = nil
    /// What the scan screen can do in one tap, without opening the editor. Nil when the scan just fills in a food being edited.
    var quick: BarcodeQuickActions.Mode? = nil
    let use: (BarcodeProduct) -> Void
    @State private var digits = ""
    @State private var pending: String?
    @State private var product: BarcodeProduct?
    @State private var saved: (code: String, food: Food)?
    @State private var missing: String?
    @State private var message: String?
    @State private var cameraMessage: String?
    @State private var cameraReady = false
    @State private var denied = false
    @AppStorage(RecentBarcodes.storageKey) private var recentData = Data()

    var body: some View {
        NavigationStack {
            LeanrList {
                if let saved {
                    Section {
                        Text(saved.food.name).font(.roboto(.headline))
                        Text("Nutrition per \(saved.food.serve)").foregroundStyle(.secondary)
                        NutritionView(total: Nutrition([Portion(food: saved.food)]), details: quick == nil)
                        if let quick {
                            BarcodeQuickActions(food: saved.food, per100: saved.food.serve.hasPrefix("100 "), inMyFoods: true, mode: quick) { dismiss() }
                        }
                        if quick == nil || quick?.logs == true {
                            Button(quick == nil ? "Use this food" : "Change details first") {
                                use(BarcodeProduct(food: saved.food, per100: false, unit: saved.food.servingWeight?.1 ?? "g",
                                                   sourceURL: URL(string: "leanr://barcode/\(saved.code)")!))
                                if dismissAfterUse { dismiss() }
                            }.buttonStyle(.bordered)
                        }
                        Button("Scan another product") { reset() }
                    } header: { Text("In My foods") } footer: {
                        Text("You saved barcode \(saved.code) with this food. Change it from the food's editor in My foods.")
                    }
                } else if let product {
                    Section("Product found") {
                        Text(product.food.name).font(.roboto(.headline))
                        Text(product.per100 ? "Nutrition per 100 \(product.unit)" : "Nutrition per \(product.food.serve)")
                            .foregroundStyle(.secondary)
                        if let quick {
                            // Logging comes first, so it's reachable without scrolling; the full panel is a tap away.
                            NutritionView(total: Nutrition([Portion(food: product.food)]), details: false)
                            BarcodeQuickActions(food: product.food, per100: product.per100, inMyFoods: false, mode: quick) { dismiss() }
                            Button("Edit details first") { use(product) }.buttonStyle(.bordered)
                            DisclosureGroup("Full nutrition") { NutritionView(total: Nutrition([Portion(food: product.food)])) }
                            Text("Check this matches your package before logging.").font(.roboto(.caption)).foregroundStyle(.secondary)
                        } else {
                            NutritionView(total: Nutrition([Portion(food: product.food)]))
                            Text("Check this matches your package. You'll choose your serving and review the numbers before saving.")
                                .font(.roboto(.caption)).foregroundStyle(.secondary)
                            Button("Use nutrition & choose serving") { use(product); if dismissAfterUse { dismiss() } }.buttonStyle(.borderedProminent)
                        }
                        Link("Source: Open Food Facts · ODbL", destination: product.sourceURL)
                        Button("Scan another product") { reset() }
                    }
                } else {
                    Section {
                        if pending != nil {
                            ProgressView("Looking up product…").frame(maxWidth: .infinity).padding(30)
                        } else if cameraReady && scenePhase == .active && message == nil {
                            BarcodeCamera { code in lookup(code) } failed: { reason in
                                cameraReady = false; cameraMessage = reason
                            }
                            .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                            Text("Point at the product barcode. Keep it steady; the scan starts automatically. Pinch to zoom.")
                                .font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                        if let cameraMessage { Text(cameraMessage).font(.roboto(.caption)).foregroundStyle(.secondary) }
                        if denied {
                            Button("Allow camera in Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                        if let message {
                            Text(message).foregroundStyle(.secondary)
                            if let missing {
                                Button {
                                    if let manualEntry { manualEntry(missing) } else { dismiss() }
                                } label: { Text("Add barcode to a new food") }
                                .buttonStyle(.borderedProminent)
                            }
                            Button("Try scanning again") { reset() }
                        }
                    }
                    RecentBarcodeSection { selected in
                        pending = nil; message = nil
                        // A recent scan you've since saved opens from My foods.
                        if let code = selected.food.barcode, let food = BarcodeLookup.match(code, in: store.data.foods) { saved = (code, food) }
                        else { product = selected }
                    }
                    Section("Or enter the barcode") {
                        TextField("Barcode number", text: $digits).keyboardType(.numberPad)
                            .accessibilityLabel("Barcode number")
                        Button("Look up barcode") { lookup(digits) }
                            .disabled(digits.isEmpty || pending != nil)
                    }
                    Section {
                        Button("Use nutrition label or manual entry") {
                            if let manualEntry { manualEntry(nil) } else { dismiss() }
                        }
                    } footer: {
                        Text("Product data by Open Food Facts (ODbL). Internet required. Only the barcode is sent for lookup; camera images stay on your device. Product coverage and nutrition completeness vary.")
                    }
                }
            }
            .navigationTitle("Scan barcode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await prepareCamera() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await prepareCamera() } }
            }
            .task(id: pending) {
                guard let code = pending else { return }
                do {
                    let found = try await BarcodeLookup.fetch(code)
                    guard !Task.isCancelled, pending == code else { return }
                    product = found; pending = nil
                    recentData = RecentBarcodes.recording(found, in: recentData)
                } catch {
                    guard !Task.isCancelled, pending == code else { return }
                    message = (error as? BarcodeLookupError)?.errorDescription ?? "Couldn't connect to the food database. Check your internet connection and try again."
                    switch error as? BarcodeLookupError {
                    case .notFound?, .incomplete?: missing = code
                    default: break
                    }
                    pending = nil
                }
            }
        }
    }

    private func lookup(_ input: String) {
        guard pending == nil else { return }
        do {
            let code = try BarcodeLookup.validatedCode(input)
            digits = code; message = nil; missing = nil
            // Barcodes you've added to your own foods win over the online database.
            if let food = BarcodeLookup.match(code, in: store.data.foods) { saved = (code, food) } else { pending = code }
        } catch { message = error.localizedDescription }
    }
    private func reset() { product = nil; saved = nil; message = nil; missing = nil; pending = nil; digits = "" }
    private func prepareCamera() async {
        guard DataScannerViewController.isSupported else {
            cameraMessage = "Live scanning isn't supported on this device. Enter the barcode below."; return
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        denied = !allowed
        cameraReady = allowed && DataScannerViewController.isAvailable
        cameraMessage = cameraReady ? nil : "Camera scanning is unavailable. You can enter the barcode below."
    }
}

/// Reads a barcode with the camera and hands back the digits, without looking the product up.
struct BarcodeCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let found: (String) -> Void
    @State private var ready = false
    @State private var message: String?
    @State private var denied = false

    var body: some View {
        NavigationStack {
            LeanrList {
                Section {
                    if ready && scenePhase == .active {
                        BarcodeCamera { code in found(code); dismiss() } failed: { reason in ready = false; message = reason }
                            .frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("Point at the product barcode. It's added as soon as it's read.")
                            .font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                    if let message { Text(message).foregroundStyle(.secondary) }
                    if denied {
                        Button("Allow camera in Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
            .navigationTitle("Add barcode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await prepare() }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await prepare() } } }
        }
    }

    private func prepare() async {
        guard DataScannerViewController.isSupported else {
            message = "Live scanning isn't supported on this device. Close this and type the barcode digits instead."; return
        }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard !Task.isCancelled else { return }
        denied = !allowed
        ready = allowed && DataScannerViewController.isAvailable
        message = ready ? nil : "The camera is unavailable. Close this and type the barcode digits instead."
    }
}

/// Logs or saves a scanned product in one tap: how much you had, whether to keep it in My foods, then Log.
struct BarcodeQuickActions: View {
    enum Mode {
        /// Logging, e.g. from Today: hands back the portion to log.
        case log((Portion) -> Bool)
        /// Adding to My foods.
        case save
        var logs: Bool { if case .log = self { true } else { false } }
    }
    @Environment(AppStore.self) private var store
    let food: Food
    /// Already in My foods, so there's nothing to save.
    let inMyFoods: Bool
    let mode: Mode
    let done: () -> Void
    /// Remembered, so it stays how you left it.
    @AppStorage(FoodEditor.keepKey) private var keep = true
    @State private var byWeight: Bool
    @State private var servings = 1.0
    @State private var weight: Double
    @State private var failed = false

    init(food: Food, per100: Bool, inMyFoods: Bool, mode: Mode, done: @escaping () -> Void) {
        self.food = food; self.inMyFoods = inMyFoods; self.mode = mode; self.done = done
        // Per-100 figures are logged by weight, so the grams eaten can be typed straight in.
        _byWeight = State(initialValue: per100 && food.servingWeight != nil)
        _weight = State(initialValue: food.servingWeight?.0 ?? 100)
    }
    private var quantity: Double {
        if byWeight, let serving = food.servingWeight { return weight / serving.0 }
        return servings
    }
    private var valid: Bool { quantity.isFinite && quantity > 0 && quantity <= 10000 }

    var body: some View {
        Group {
            switch mode {
            case .log(let logPortion):
                if let serving = food.servingWeight {
                    Picker("Measure in", selection: $byWeight) {
                        Text("Servings").tag(false); Text(serving.1 == "g" ? "Grams" : "mL").tag(true)
                    }.pickerStyle(.segmented)
                }
                if byWeight, let serving = food.servingWeight { NumberField(title: "Amount (\(serving.1))", value: $weight) }
                else { NumberField(title: "Servings", value: $servings, places: 2) }
                if !inMyFoods {
                    Toggle(isOn: $keep) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save to My foods")
                            Text("Log it again with one tap, and scanning it opens it straight away.").font(.roboto(.caption)).foregroundStyle(.secondary)
                        }
                    }
                }
                Button { log(logPortion) } label: {
                    Text("Log · \(Nutrition([Portion(food: food, quantity: valid ? quantity : 0)]).cal.rounded().number) Cal").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(!valid)
                .task(id: food.id) { useLastAmount() }
            case .save:
                if inMyFoods {
                    Label("Already in My foods", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                } else {
                    Button {
                        if let kept = store.saveToMyFoods(food) { store.notice = "Saved \(kept.name) to My foods"; done() } else { failed = true }
                    } label: { Text("Save to My foods").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Couldn’t save food", isPresented: $failed) { Button("OK", role: .cancel) {} } message: {
            Text("Your data was not changed. Check available storage and any data recovery message in the app.")
        }
    }

    /// A food you've logged before starts at the amount you had last time.
    private func useLastAmount() {
        guard inMyFoods, let last = QuickLog.lastQuantity(of: food.id, logs: store.data.logs) else { return }
        if byWeight, let serving = food.servingWeight { weight = (last * serving.0).tenth } else { servings = last }
    }

    private func log(_ logPortion: (Portion) -> Bool) {
        var item = food, kept = false
        if keep && !inMyFoods, let saved = store.saveToMyFoods(food) { item = saved; kept = true }
        guard logPortion(Portion(food: item, quantity: quantity)) else { failed = true; return }
        if kept { store.notice = "Logged and saved to My foods" }
        done()
    }
}

struct RecentBarcodeSection: View {
    @AppStorage(RecentBarcodes.storageKey) private var recentData = Data()
    let use: (BarcodeProduct) -> Void

    var body: some View {
        let products = RecentBarcodes.products(from: recentData)
        if !products.isEmpty {
            Section {
                // A dropdown, so the last few scans don't push the rest of the screen down.
                Menu {
                    ForEach(products, id: \.sourceURL) { product in
                        Button {
                            recentData = RecentBarcodes.recording(product, in: recentData)
                            use(product)
                        } label: {
                            Text(product.food.name)
                            Text("\(product.food.cal.number) Cals · \(product.food.serve)")
                        }
                    }
                } label: {
                    HStack {
                        Label("Recently scanned", systemImage: "clock.arrow.circlepath")
                        Spacer()
                        Text("\(products.count)").foregroundStyle(.secondary).monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    }.frame(minHeight: 28).contentShape(Rectangle())
                }
                .accessibilityLabel("Recently scanned, \(products.count) products")
            } footer: {
                Text("Reuse one of your last \(RecentBarcodes.limit) scans. Ones you saved open from My foods.")
            }
        }
    }
}

private struct BarcodeCamera: UIViewControllerRepresentable {
    let found: (String) -> Void
    let failed: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(found: found, failed: failed) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .itf14])],
            qualityLevel: .balanced, recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        let coordinator = context.coordinator
        guard !coordinator.started else { return }
        coordinator.started = true
        Task { @MainActor [weak controller, weak coordinator] in
            guard let controller, let coordinator, !coordinator.stopped else { return }
            do { try controller.startScanning() }
            catch { coordinator.failed("Couldn't start the camera. Enter the barcode below or reopen the scanner.") }
        }
    }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.stopped = true; controller.stopScanning()
    }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        let failed: (String) -> Void
        var started = false
        var stopped = false
        init(found: @escaping (String) -> Void, failed: @escaping (String) -> Void) { self.found = found; self.failed = failed }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            accept(addedItems, scanner: dataScanner)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            accept(updatedItems, scanner: dataScanner)
        }
        private func accept(_ items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !stopped else { return }
            for case .barcode(let barcode) in items {
                if let code = barcode.payloadStringValue, (try? BarcodeLookup.validatedCode(code)) != nil {
                    stopped = true; scanner.stopScanning(); found(code); break
                }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !stopped else { return }
            stopped = true; dataScanner.stopScanning()
            failed("Camera scanning stopped. Enter the barcode or reopen the scanner.")
        }
    }
}
