import Foundation
import UserNotifications

/// "Nothing logged for lunch yet" nudges. A notification can't check the log when it fires, so reminders are booked
/// two weeks ahead and today's is taken back as soon as that meal is logged.
@MainActor enum MealReminders {
    static let meals: [MealTime] = [.breakfast, .lunch, .dinner]
    nonisolated private static let prefix = "reminder."
    nonisolated private static let days = 14
    private static var queue: Task<Void, Never>?

    static let weeklyKey = "reminder.weekly.on"
    static var weeklyOn: Bool { UserDefaults.standard.bool(forKey: weeklyKey) }

    /// The next Sunday at 6 pm, when the weekly review goes out.
    nonisolated static func nextReview(after now: Date, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: 18, minute: 0, weekday: 1), matchingPolicy: .nextTime)
    }

    static func enabledKey(_ meal: MealTime) -> String { "reminder.\(meal.rawValue).on" }
    static func timeKey(_ meal: MealTime) -> String { "reminder.\(meal.rawValue).minutes" }
    static func defaultMinutes(_ meal: MealTime) -> Int {
        switch meal {
        case .breakfast: 9 * 60 + 30
        case .lunch: 13 * 60 + 30
        case .dinner: 19 * 60 + 30
        case .snacks: 15 * 60 + 30
        }
    }
    static func isOn(_ meal: MealTime) -> Bool { UserDefaults.standard.bool(forKey: enabledKey(meal)) }
    /// Minutes after midnight.
    static func minutes(_ meal: MealTime) -> Int { UserDefaults.standard.object(forKey: timeKey(meal)) as? Int ?? defaultMinutes(meal) }

    struct Reminder: Equatable {
        var id: String
        var meal: MealTime
        var date: Date
    }

    /// Reminders still to come over the next two weeks, skipping meals already logged that day.
    nonisolated static func plan(_ settings: [(meal: MealTime, minutes: Int)], logs: [String: [LogEntry]], now: Date = Date(), calendar: Calendar = .current) -> [Reminder] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).flatMap { offset -> [Reminder] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            let key = dayKey(day), logged = Set((logs[key] ?? []).compactMap(\.mealTime))
            return settings.compactMap { setting in
                // The chosen clock time, not minutes after midnight, so daylight-saving days keep it.
                guard !logged.contains(setting.meal),
                      let date = calendar.date(bySettingHour: setting.minutes / 60, minute: setting.minutes % 60, second: 0, of: day),
                      date > now else { return nil }
                return Reminder(id: "reminder.\(setting.meal.rawValue).\(key)", meal: setting.meal, date: date)
            }
        }
    }

    /// What the booked reminders depend on: the log from a week back to the end of the booking window, targets and weigh-ins.
    /// Comparing this is cheap, unlike comparing the whole log history on every save.
    struct Inputs: Equatable {
        var logs: [String: [LogEntry]]
        var goals: [String: Double]
        var dayGoals: [String: [String: Double]]
        var weighIns: Int
        var lastWeight: WeightEntry?
    }

    nonisolated static func inputs(_ data: AppData, goals: Goals, now: Date = Date(), calendar: Calendar = .current) -> Inputs {
        let today = calendar.startOfDay(for: now)
        let keys = (-7..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }.map(dayKey)
        return Inputs(logs: Dictionary(uniqueKeysWithValues: keys.compactMap { key in data.logs[key].map { (key, $0) } }),
                      goals: goals.values,
                      dayGoals: Dictionary(uniqueKeysWithValues: keys.compactMap { key in data.dayGoals[key].map { (key, $0.values) } }),
                      weighIns: data.weightLog.count, lastWeight: data.weightLog.max { $0.date < $1.date })
    }

    /// Rebooks reminders after the log or the settings change. Runs one at a time so a quick log can't leave a stale reminder.
    /// The weekly review's text is worked out now, so it's rebooked with every change to stay current.
    static func refresh(_ data: AppData, goals: Goals) {
        let settings = meals.filter(isOn).map { (meal: $0, minutes: minutes($0)) }
        let upcoming = plan(settings, logs: data.logs)
        var weekly: (id: String, date: Date, text: String)?
        if weeklyOn, let date = nextReview(after: Date()) {
            let review = WeeklyReview.make(data, goals: goals, ending: date)
            if review.loggedDays > 0 { weekly = ("reminder.weekly.\(dayKey(date))", date, review.summary) }
        }
        queue = Task { [previous = queue] in
            await previous?.value
            let center = UNUserNotificationCenter.current()
            let booked = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: booked)
            guard !upcoming.isEmpty || weekly != nil, ![.denied, .notDetermined].contains(await center.notificationSettings().authorizationStatus) else { return }
            for reminder in upcoming {
                let content = UNMutableNotificationContent()
                content.title = reminder.meal.title
                content.body = "Nothing logged for \(reminder.meal.title.lowercased()) yet. Tap to add it."
                content.sound = .default
                content.threadIdentifier = "meal-reminders"
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
                let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
            }
            if let weekly {
                let content = UNMutableNotificationContent()
                content.title = "Your week in Leanr"
                content.body = weekly.text
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: weekly.date)
                try? await center.add(UNNotificationRequest(identifier: weekly.id, content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
            }
        }
    }

    /// Asks to send notifications. False if the person declines or turned them off in Settings.
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return true
        }
    }
}
