import AppIntents
import WidgetKit

/// The widget's log button. As a Live Activity intent it runs inside Leanr, so the meal is saved, sent to Apple Health
/// and synced just like logging in the app. If the system ever runs it in the widget instead, the request is queued for the app.
struct LogAgainIntent: LiveActivityIntent {
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
        QuickLogQueue.showQueued(option, at: now)
        WidgetCenter.shared.reloadAllTimelines()
        #else
        await AppServices.logAgain(option)
        #endif
        return .result()
    }
}
