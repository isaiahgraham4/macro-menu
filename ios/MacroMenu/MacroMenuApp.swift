import SwiftUI

@main
struct MacroMenuApp: App {
    init() { AppFonts.setUp(); AppServices.start() }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(KeyboardDismissal())
                // Tapping a number box selects its number, so one delete clears it and typing replaces it.
                .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                    guard let field = note.object as? UITextField,
                          [.decimalPad, .numberPad].contains(field.keyboardType) else { return }
                    Task { @MainActor in field.selectAll(nil) }
                }
        }
        .commands { LeanrCommands() }
    }
}

/// Shortcuts for an iPad or any attached keyboard. Holding ⌘ lists them, so they teach themselves.
private struct LeanrCommands: Commands {
    @AppStorage("leanr.onboarding.completed") private var onboardingCompleted = false
    private var nav: Navigator { AppServices.nav }
    var body: some Commands {
        CommandMenu("Go") {
            Group {
                Button("Today") { nav.tab = .today }.keyboardShortcut("1")
                Button("Find") { nav.tab = .find }.keyboardShortcut("2")
                Button("Map") { nav.tab = .map }.keyboardShortcut("3")
                Button("Meal") { nav.tab = .meal }.keyboardShortcut("4")
                Button("Progress") { nav.tab = .progress }.keyboardShortcut("5")
                Divider()
                Button("Scan a Barcode") { nav.opened = nil; nav.tab = .today; nav.scanRequested = true }.keyboardShortcut("b")
                Button("Settings") { nav.requestedSheet = .settings }.keyboardShortcut(",")
            }
            .disabled(!onboardingCompleted)
        }
    }
}

/// One non-blocking tap recognizer covers tabs and sheets in this app window.
private struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalView { KeyboardDismissalView() }
    func updateUIView(_ view: KeyboardDismissalView, context: Context) {}
    static func dismantleUIView(_ view: KeyboardDismissalView, coordinator: ()) { view.detach() }
}

private final class KeyboardDismissalView: UIView, UIGestureRecognizerDelegate {
    private weak var installedWindow: UIWindow?
    private lazy var tap: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        gesture.cancelsTouchesInView = false
        gesture.delaysTouchesBegan = false
        gesture.delaysTouchesEnded = false
        gesture.delegate = self
        return gesture
    }()

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard installedWindow !== window else { return }
        detach()
        window?.addGestureRecognizer(tap)
        installedWindow = window
    }

    func detach() {
        installedWindow?.removeGestureRecognizer(tap)
        installedWindow = nil
    }

    @objc private func dismissKeyboard() { installedWindow?.endEditing(true) }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Keep editing, cursor positioning, and switching between fields working.
        var touchedView = touch.view
        while let view = touchedView {
            if view is UITextField || view is UITextView || view is UISearchBar { return false }
            touchedView = view.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
