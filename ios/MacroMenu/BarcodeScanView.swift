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
            BarcodeScanView(dismissAfterUse: false, manualEntry: { barcode = $0; editing = true }) {
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
                        Text(saved.food.name).font(.headline)
                        Text("Nutrition per \(saved.food.serve)").foregroundStyle(.secondary)
                        NutritionView(total: Nutrition([Portion(food: saved.food)]))
                        Button("Use this food") {
                            use(BarcodeProduct(food: saved.food, per100: false, unit: saved.food.servingWeight?.1 ?? "g",
                                               sourceURL: URL(string: "leanr://barcode/\(saved.code)")!))
                            if dismissAfterUse { dismiss() }
                        }.buttonStyle(.borderedProminent)
                        Button("Scan another product") { reset() }
                    } header: { Text("In your foods") } footer: {
                        Text("You added barcode \(saved.code) to this food. Change it from the food's editor in My foods.")
                    }
                } else if let product {
                    Section("Product found") {
                        Text(product.food.name).font(.headline)
                        Text(product.per100 ? "Nutrition per 100 \(product.unit)" : "Nutrition per \(product.food.serve)")
                            .foregroundStyle(.secondary)
                        NutritionView(total: Nutrition([Portion(food: product.food)]))
                        Text("Check this matches your package. You'll choose your serving and review the numbers before saving.")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Source: Open Food Facts · ODbL", destination: product.sourceURL)
                        Button("Use nutrition & choose serving") { use(product); if dismissAfterUse { dismiss() } }
                            .buttonStyle(.borderedProminent)
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
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let cameraMessage { Text(cameraMessage).font(.caption).foregroundStyle(.secondary) }
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
                        pending = nil; message = nil; product = selected
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
                            .font(.caption).foregroundStyle(.secondary)
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

struct RecentBarcodeSection: View {
    @AppStorage(RecentBarcodes.storageKey) private var recentData = Data()
    let use: (BarcodeProduct) -> Void

    var body: some View {
        let products = RecentBarcodes.products(from: recentData)
        if !products.isEmpty {
            Section {
                ForEach(products, id: \.sourceURL) { product in
                    Button {
                        recentData = RecentBarcodes.recording(product, in: recentData)
                        use(product)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.food.name).foregroundStyle(.primary)
                            Text("\(product.food.cal.number) Cals · \(product.food.serve)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Recently scanned") } footer: {
                Text("Reuse a scanned product, then check its serving size and choose how many servings.")
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
