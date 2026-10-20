import AppIntents
import SwiftUI
import WidgetKit

/// A control that opens the barcode scanner, for the Lock Screen's bottom corners, Control Centre or the Action button.
struct LeanrScanControl: ControlWidget {
    static let kind = "com.isaiahgraham.MacroMenu.scan"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ScanBarcodeIntent()) {
                Label("Scan barcode", systemImage: "leaf.fill")
            }
        }
        .displayName("Scan a barcode")
        .description("Opens Leanr's barcode scanner to log a packaged food.")
    }
}
