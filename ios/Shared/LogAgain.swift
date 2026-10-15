import AppIntents
import WidgetKit

/// The widget's log button. It runs inside the widget, so a tap shows at once: the widget adds the meal or water to what it
/// shows and queues the request, and Leanr logs it, with Apple Health and sync, the next time it runs. (Run as a Live Activity
/// intent, the system launched Leanr in the background first and held the widget for several seconds.)
/// If the system runs it in Leanr instead, Leanr logs it straight away.
struct LogAgainIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Again"
    static let description = IntentDescription("Logs a pinned food, your usual meal, a planned meal or a glass of water to today.")
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Item") var option: String

    init() {}
    init(option: String) { self.option = option }

    func perform() async throws -> some IntentResult {
        #if LEANR_WIDGET
        let now = Date()
        QuickLogQueue.add(option, at: now)
        // Only the widgets this changes, the tapped one first.
        for kind in QuickLogQueue.showQueued(option, at: now) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        #else
        await AppServices.logAgain(option)
        #endif
        return .result()
    }
}
