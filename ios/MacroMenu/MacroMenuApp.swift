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
                #if DEBUG
                // `-demoShare` opens a share image at launch, to try Share, Save to Photos and Copy without making one.
                .sheet(isPresented: .constant(CommandLine.arguments.contains("-demoShare"))) {
                    NavigationStack {
                        StoryImagePreview(name: "7 day streak") {
                            StoryCard(icon: "flame.fill", title: "7 day streak", figure: ("7", "days"), detail: "Logged every day this week.",
                                      progress: nil, footnote: Date().formatted(date: .long, time: .omitted)).image
                        }
                    }
                }
                // `-demoShareDay` opens a whole day's share image, made from sample food.
                .sheet(isPresented: .constant(CommandLine.arguments.contains("-demoShareDay"))) {
                    NavigationStack { MealSharePreview(.day(DemoDay.entries, on: Date())) }
                }
                #endif
        }
        .commands { LeanrCommands() }
    }
}

#if DEBUG
private enum DemoDay {
    static func entry(_ name: String, _ time: MealTime, _ foods: [(String, Double, Double, Double, Double)]) -> LogEntry {
        LogEntry(name: name, items: foods.map { Portion(food: Food(name: $0.0, kj: $0.1 * 4.184, cal: $0.1, p: $0.2, c: $0.3, f: $0.4)) }, mealTime: time)
    }
    static let entries = [
        entry("Oats", .breakfast, [("Rolled oats", 300, 10, 54, 6), ("Banana", 105, 1, 27, 0)]),
        entry("Big Mac meal", .lunch, [("Big Mac", 563, 26, 45, 31), ("Medium fries", 320, 4, 43, 15)]),
        entry("Chicken bowl", .dinner, [("Grilled chicken", 280, 52, 0, 6), ("Rice", 260, 5, 57, 1), ("Broccoli", 50, 4, 10, 0)]),
        entry("Protein bar", .snacks, [("Protein bar", 200, 20, 22, 7)]),
    ]
}
#endif

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
