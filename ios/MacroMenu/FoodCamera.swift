import SwiftUI
import VisionKit

/// The camera for a meal photo: a square to frame the food from above, the full-quality picture when you tap the shutter,
/// and a shortcut to the product scanner when a barcode is in shot. Everything stays on the iPhone.
struct FoodCamera: View {
    /// Live barcode spotting needs a recent iPhone with camera access; elsewhere the system camera is used instead.
    @MainActor static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    /// The photo taken, or nil when cancelled.
    let photo: (UIImage?) -> Void
    /// A barcode came into view and the person chose to scan the product instead.
    let barcode: () -> Void
    @State private var scanner: DataScannerViewController?
    @State private var seesBarcode = false
    @State private var capturing = false
    @State private var failed = false

    var body: some View {
        ZStack {
            ScannerView(scanner: $scanner, seesBarcode: $seesBarcode).ignoresSafeArea()
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                .aspectRatio(1, contentMode: .fit)
                .padding(24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            VStack(spacing: 14) {
                HStack {
                    Button("Cancel") { photo(nil) }
                        .font(.roboto(.headline)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                    Spacer()
                }
                Text(failed ? "That didn't take. Try again." : "From above, with the food filling the square")
                    .font(.roboto(.subheadline, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: Capsule())
                Spacer()
                if seesBarcode {
                    Button { barcode() } label: {
                        Label("Barcode in shot · Scan the product", systemImage: "barcode.viewfinder").font(.roboto(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(action: capture) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64).opacity(capturing ? 0.5 : 1)
                    }
                }
                .disabled(scanner == nil || capturing)
                .accessibilityLabel("Take photo")
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(Color.black)
    }

    private func capture() {
        guard let scanner, !capturing else { return }
        capturing = true; failed = false
        Task {
            let image = try? await scanner.capturePhoto()
            capturing = false
            if let image { photo(image) } else { failed = true }
        }
    }
}

/// VisionKit's live camera, watching for barcodes only. It also takes the photo.
private struct ScannerView: UIViewControllerRepresentable {
    @Binding var scanner: DataScannerViewController?
    @Binding var seesBarcode: Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                                   recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                   isPinchToZoomEnabled: true, isGuidanceEnabled: false, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        // Scanning starts once the view is on screen.
        DispatchQueue.main.async {
            try? controller.startScanning()
            scanner = controller
        }
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(seesBarcode: $seesBarcode) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let seesBarcode: Binding<Bool>
        init(seesBarcode: Binding<Bool>) { self.seesBarcode = seesBarcode }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            seesBarcode.wrappedValue = !allItems.isEmpty
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            seesBarcode.wrappedValue = !allItems.isEmpty
        }
    }
}
