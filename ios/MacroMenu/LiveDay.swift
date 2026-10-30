import ActivityKit
import Foundation

/// Keeps today's calories on the Lock Screen and in the Dynamic Island, for people who turn it on in Settings.
/// iOS ends a Live Activity after about 8 hours, and only an app that's open can start one, so it comes back when Leanr next opens.
enum LiveDay {
    static let storageKey = "liveDay"
    /// The refresh in progress. Each waits for the last, or two in a row could both start an activity.
    @MainActor private static var latest: Task<Void, Never>?

    /// Starts, updates or ends the activity to match today's log and the setting.
    @MainActor static func refresh(_ store: AppStore, now: Date = Date()) {
        let day = dayKey(now), previous = latest
        guard UserDefaults.standard.bool(forKey: storageKey), let target = store.goals.values["cal"] else {
            latest = Task { await previous?.value; await show(nil, day: day, until: nil) }
            return
        }
        let total = Nutrition((store.data.logs[day] ?? []).flatMap(\.items))
        let accent = AppAccent.resolved(UserDefaults.standard.string(forKey: AppAccent.storageKey) ?? AppAccent.standard.rawValue).rawValue
        let state = LeanrDayAttributes.ContentState(eaten: total.cal, target: target, protein: total.p, proteinTarget: store.goals.values["p"], accent: accent)
        // It goes stale at midnight, when the figures stop being today's.
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))
        latest = Task { await previous?.value; await show(state, day: day, until: midnight) }
    }

    private nonisolated static func show(_ state: LeanrDayAttributes.ContentState?, day: String, until midnight: Date?) async {
        for activity in Activity<LeanrDayAttributes>.activities where state == nil || activity.attributes.day != day {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let state else { return }
        let content = ActivityContent(state: state, staleDate: midnight)
        if let current = Activity<LeanrDayAttributes>.activities.first(where: { $0.attributes.day == day && $0.activityState == .active }) {
            if current.content.state != state { await current.update(content) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: LeanrDayAttributes(day: day), content: content)
        }
    }
}
