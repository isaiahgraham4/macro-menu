import Foundation
import UserNotifications

/// "Nothing logged for lunch yet" nudges. A notification can't check the log when it fires, so reminders are booked
/// two weeks ahead and today's is taken back as soon as that meal is logged.
/// The fourth reminder is the late-night one, kept under the Snacks slot: it only goes out if nothing at all was logged that day.
/// Water reminders sit alongside them: spaced through the day, and dropped for a day once its water target is reached.
@MainActor enum MealReminders {
    static let meals: [MealTime] = [.breakfast, .lunch, .dinner, .snacks]
    /// What a reminder is called, since the Snacks slot is the late-night check.
    static func title(_ meal: MealTime) -> String { meal == .snacks ? "Late night" : meal.title }
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
        case .snacks: 21 * 60 + 30
        }
    }
    static func isOn(_ meal: MealTime) -> Bool { UserDefaults.standard.bool(forKey: enabledKey(meal)) }
    /// Minutes after midnight.
    static func minutes(_ meal: MealTime) -> Int { UserDefaults.standard.object(forKey: timeKey(meal)) as? Int ?? defaultMinutes(meal) }

    /// Different wording each day, in a fixed order so rebooking never changes what tomorrow's reminder will say.
    nonisolated private static let phrases: [MealTime: [(title: String, body: String)]] = [
        .breakfast: [
            ("Morning! Breakfast?", "Nothing logged yet. Add it in a couple of taps."),
            ("Start the day on the board", "Log your breakfast and get your day going."),
            ("Had breakfast yet?", "Log it now so you don't forget later."),
            ("Breakfast check-in", "Nothing's logged for breakfast. Tap to add it."),
            ("Fuel up, then log it", "Your breakfast isn't in Leanr yet."),
            ("Skipping breakfast?", "No problem. If you ate something, tap to log it.")],
        .lunch: [
            ("Lunch o'clock", "Nothing logged for lunch yet. Tap to add it."),
            ("Midday check-in", "What's for lunch? Log it while it's fresh."),
            ("Had lunch yet?", "Add it now and keep your day accurate."),
            ("Lunch break", "Your lunch isn't logged yet. It only takes a moment."),
            ("Don't let lunch slip by", "Tap to log what you ate."),
            ("Halfway through the day", "Nothing logged for lunch. Add it now?")],
        .dinner: [
            ("Dinner time", "Nothing logged for dinner yet. Tap to add it."),
            ("What's for dinner?", "Log it as you go and keep your day on track."),
            ("Dinner check-in", "Your dinner isn't in Leanr yet."),
            ("Evening! Had dinner?", "Add it now while you remember what was on the plate."),
            ("Nearly end of day", "Log your dinner to keep your numbers right."),
            ("Dinner's not logged", "It takes a few seconds. Tap to add it.")],
        .snacks: [
            ("Before you wind down", "Nothing logged today. Add what you ate to keep your streak going."),
            ("Last call for today", "You haven't logged anything today. A quick log counts."),
            ("Still time to log today", "Add what you've eaten and close out your day."),
            ("Don't lose your streak", "Nothing's logged today. Tap to add a meal or snack."),
            ("End-of-day check-in", "Log today's food before bed. Even a quick one counts."),
            ("Day's nearly done", "Nothing logged yet today. Tap to add it.")]
    ]
    /// The reminder's wording for that day. Consecutive days always differ.
    nonisolated static func message(_ meal: MealTime, on date: Date, calendar: Calendar = .current) -> (title: String, body: String) {
        let bank = phrases[meal] ?? phrases[.dinner]!
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return bank[day % bank.count]
    }

    // MARK: Water

    static let waterOnKey = "reminder.water.on"
    static let waterFromKey = "reminder.water.from"
    static let waterUntilKey = "reminder.water.until"
    static let waterEveryKey = "reminder.water.every"
    static var waterOn: Bool { UserDefaults.standard.bool(forKey: waterOnKey) }

    /// Water reminders from `from` until `until` (minutes after midnight), every `everyHours` hours.
    struct WaterSchedule: Equatable {
        var from = 9 * 60
        var until = 20 * 60
        var everyHours = 2
        static let hourChoices = [1, 2, 3, 4]
    }

    static var waterSchedule: WaterSchedule {
        let defaults = UserDefaults.standard, standard = WaterSchedule()
        let from = defaults.object(forKey: waterFromKey) as? Int ?? standard.from
        let until = defaults.object(forKey: waterUntilKey) as? Int ?? standard.until
        let every = defaults.object(forKey: waterEveryKey) as? Int ?? standard.everyHours
        return WaterSchedule(from: min(max(from, 0), 23 * 60 + 59), until: min(max(until, 0), 23 * 60 + 59),
                             everyHours: WaterSchedule.hourChoices.contains(every) ? every : standard.everyHours)
    }

    /// The times of day a schedule fires, as minutes after midnight. Always at least one: the start.
    nonisolated static func waterTimes(_ schedule: WaterSchedule) -> [Int] {
        let step = max(1, schedule.everyHours) * 60
        return Array(stride(from: schedule.from, through: max(schedule.from, schedule.until), by: step))
    }

    struct WaterReminder: Equatable {
        var id: String
        /// Which of the day's reminders this is, so neighbours get different wording.
        var slot: Int
        var date: Date
    }

    /// Water reminders over the next two weeks. A day whose target is already reached has none, and none are in the past.
    /// A reminder can't check the log when it fires, so logging water rebooks the rest of today.
    nonisolated static func waterPlan(_ schedule: WaterSchedule, water: [String: Double], target: Double, now: Date = Date(), calendar: Calendar = .current) -> [WaterReminder] {
        let today = calendar.startOfDay(for: now), times = waterTimes(schedule)
        return (0..<days).flatMap { offset -> [WaterReminder] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return [] }
            let key = dayKey(day)
            if target > 0, (water[key] ?? 0) >= target { return [] }
            return times.enumerated().compactMap { slot, minutes in
                guard let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), date > now else { return nil }
                return WaterReminder(id: "reminder.water.\(key).\(minutes)", slot: slot, date: date)
            }
        }
    }

    nonisolated private static let waterPhrases: [(title: String, body: String)] = [
        ("Time for some water", "Have a glass, then tap to log it."),
        ("Water break", "A quick glass now keeps the day on track."),
        ("Sip, sip", "When did you last have water? Tap to log it."),
        ("Stay topped up", "Have a glass and log it in a tap."),
        ("Drink up", "A glass of water, then log it in Leanr."),
        ("Hydration check", "Water time. It takes a second to log.")]

    /// The wording for one water reminder. Consecutive days differ, and so do neighbouring reminders on the same day.
    nonisolated static func waterMessage(on date: Date, slot: Int, calendar: Calendar = .current) -> (title: String, body: String) {
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return waterPhrases[(day + slot) % waterPhrases.count]
    }

    /// iOS keeps only 64 pending notifications and drops the rest, so what's booked is the soonest of them.
    nonisolated static let bookingLimit = 64

    struct Booking: Equatable {
        var id: String
        var date: Date
        var title: String
        var body: String
        var thread: String
    }

    /// Meal and water reminders in the order they'll fire, cut to what fits. `reserved` leaves room for other notifications.
    nonisolated static func bookings(meals: [Reminder], water: [WaterReminder], reserved: Int = 0, calendar: Calendar = .current) -> [Booking] {
        let all = meals.map { reminder -> Booking in
            let words = message(reminder.meal, on: reminder.date, calendar: calendar)
            return Booking(id: reminder.id, date: reminder.date, title: words.title, body: words.body, thread: "meal-reminders")
        } + water.map { reminder -> Booking in
            let words = waterMessage(on: reminder.date, slot: reminder.slot, calendar: calendar)
            return Booking(id: reminder.id, date: reminder.date, title: words.title, body: words.body, thread: "water-reminders")
        }
        return Array(all.sorted { ($0.date, $0.id) < ($1.date, $1.id) }.prefix(max(0, bookingLimit - reserved)))
    }

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
            let key = dayKey(day), entries = logs[key] ?? [], logged = Set(entries.compactMap(\.mealTime))
            return settings.compactMap { setting in
                // Late night is a check on the whole day; the others on their own meal.
                let covered = setting.meal == .snacks ? !entries.isEmpty : logged.contains(setting.meal)
                // The chosen clock time, not minutes after midnight, so daylight-saving days keep it.
                guard !covered,
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
        /// Water by day and the target, which decide whether a day's water reminders go out.
        var water: [String: Double] = [:]
        var waterTarget = Water.defaultTarget
        /// Whether choosing and sending log reminders is allowed (Premium).
        var logReminders = true
    }

    nonisolated static func inputs(_ data: AppData, goals: Goals, now: Date = Date(), calendar: Calendar = .current, logReminders: Bool = true) -> Inputs {
        let today = calendar.startOfDay(for: now)
        let keys = (-7..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }.map(dayKey)
        return Inputs(logs: Dictionary(uniqueKeysWithValues: keys.compactMap { key in data.logs[key].map { (key, $0) } }),
                      goals: goals.values,
                      dayGoals: Dictionary(uniqueKeysWithValues: keys.compactMap { key in data.dayGoals[key].map { (key, $0.values) } }),
                      weighIns: data.weightLog.count, lastWeight: data.weightLog.max { $0.date < $1.date },
                      water: Dictionary(uniqueKeysWithValues: keys.compactMap { key in data.water?[key].map { (key, $0) } }),
                      waterTarget: Water.target(data), logReminders: logReminders)
    }

    /// Rebooks reminders after the log or the settings change. Runs one at a time so a quick log can't leave a stale reminder.
    /// The weekly review's text is worked out now, so it's rebooked with every change to stay current.
    /// With `logReminders` off (Premium locked), the meal and water reminders are cleared and only the weekly review remains.
    static func refresh(_ data: AppData, goals: Goals, logReminders: Bool = true) {
        let settings = logReminders ? meals.filter(isOn).map { (meal: $0, minutes: minutes($0)) } : []
        let upcoming = plan(settings, logs: data.logs)
        let watering = logReminders && waterOn ? waterPlan(waterSchedule, water: data.water ?? [:], target: Water.target(data)) : []
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
            guard !upcoming.isEmpty || !watering.isEmpty || weekly != nil,
                  ![.denied, .notDetermined].contains(await center.notificationSettings().authorizationStatus) else { return }
            for booking in bookings(meals: upcoming, water: watering, reserved: weekly == nil ? 0 : 1) {
                let content = UNMutableNotificationContent()
                content.title = booking.title
                content.body = booking.body
                content.sound = .default
                content.threadIdentifier = booking.thread
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: booking.date)
                let request = UNNotificationRequest(identifier: booking.id, content: content,
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

    /// Whether every meal reminder and the water reminder are on.
    static var allOn: Bool { meals.allSatisfy(isOn) && waterOn }
    /// Whether any meal or water reminder is on.
    static var anyOn: Bool { meals.contains(where: isOn) || waterOn }

    /// Turns on every meal reminder and the water reminder at their usual times. False if notifications aren't allowed.
    static func enableAll() async -> Bool {
        guard await requestPermission() else { return false }
        for meal in meals { UserDefaults.standard.set(true, forKey: enabledKey(meal)) }
        UserDefaults.standard.set(true, forKey: waterOnKey)
        return true
    }

    /// Turns on just the chosen reminders. False if notifications aren't allowed.
    static func enable(_ chosen: Set<MealTime>, water: Bool) async -> Bool {
        guard await requestPermission() else { return false }
        for meal in chosen { UserDefaults.standard.set(true, forKey: enabledKey(meal)) }
        if water { UserDefaults.standard.set(true, forKey: waterOnKey) }
        return true
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

/// The one-off question that offers reminders to someone who has come back to Leanr after a few days away and has none set up.
enum ReminderPrompt {
    static let lastActiveKey = "leanr.lastActive"
    static let askedKey = "leanr.reminderPrompt.asked"
    /// How long away counts as "a while", and how long to leave it after asking before asking again.
    static let awayFor: TimeInterval = 3 * 24 * 3600
    static let askAgainAfter: TimeInterval = 30 * 24 * 3600

    /// Only for someone who can choose reminders, has none on, hasn't turned notifications off, was away a while,
    /// and wasn't asked recently. A first launch has no last visit, so it never asks straight away.
    nonisolated static func shouldShow(now: Date, lastActive: Date?, lastAsked: Date?, anyReminderOn: Bool, notificationsDenied: Bool, canChoose: Bool) -> Bool {
        guard canChoose, !anyReminderOn, !notificationsDenied, let lastActive, now.timeIntervalSince(lastActive) >= awayFor else { return false }
        if let lastAsked, now.timeIntervalSince(lastAsked) < askAgainAfter { return false }
        return true
    }
}
