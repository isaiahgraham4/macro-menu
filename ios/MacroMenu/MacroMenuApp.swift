import SwiftUI

@main
struct MacroMenuApp: App {
    init() { AppFonts.setUp() }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(KeyboardDismissal())
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
