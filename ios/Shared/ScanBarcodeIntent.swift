import AppIntents

/// Opens Leanr straight to the barcode scanner. Used by the Scan control, which can sit on the Lock Screen (in place of the
/// torch or camera), in Control Centre or on the Action button. It always runs in Leanr, which the system opens first.
struct ScanBarcodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a Barcode"
    static let description = IntentDescription("Opens Leanr's barcode scanner to log a packaged food.")
    static let openAppWhenRun = true

    init() {}

    func perform() async throws -> some IntentResult {
        #if !LEANR_WIDGET
        await MainActor.run {
            AppServices.start()
            AppServices.nav.opened = nil
            AppServices.nav.tab = .today
            AppServices.nav.scanRequested = true
        }
        #endif
        return .result()
    }
}
