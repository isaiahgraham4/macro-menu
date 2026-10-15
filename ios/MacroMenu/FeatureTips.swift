import Foundation

/// A feature Leanr points out once, on Today, to someone who hasn't tried it. One tip at a time, spaced out, never repeated
/// after it's been dealt with, and never for something already in use.
enum FeatureTip: String, CaseIterable, Identifiable, Sendable {
    // In the order they're offered.
    case describe, scan, water, health, reminders, plan, photo, askLeanr, widgets, checkIn, body
    var id: String { rawValue }

    /// What the tip's button does, handled where the tip is shown.
    enum Action: Sendable { case describe, scan, photo, plan, settings, reminders, find, progress }

    var title: String {
        switch self {
        case .describe: "Say what you ate"
        case .scan: "Scan a barcode"
        case .water: "Track your water"
        case .health: "Connect Apple Health"
        case .reminders: "Get a nudge to log"
        case .plan: "Plan your meals ahead"
        case .photo: "Log a meal from a photo"
        case .askLeanr: "Ask Leanr"
        case .widgets: "Add a widget"
        case .checkIn: "Try the weekly check-in"
        case .body: "Track measurements and photos"
        }
    }

    var detail: String {
        switch self {
        case .describe: "Type or say a meal in your own words and Leanr works out the numbers."
        case .scan: "Scan a packaged food's barcode to log it in a tap."
        case .water: "Tap the plus on the Water row each time you have a glass."
        case .health: "See your steps and calories burnt next to what you eat."
        case .reminders: "Meal and water reminders that skip anything you've already logged."
        case .plan: "Plan tomorrow's meals now and tick them off with one tap."
        case .photo: "Take a photo of your plate and Leanr suggests the foods in it."
        case .askLeanr: "Ask for something like \"high protein, no dairy\" and get matching meals."
        case .widgets: "Calories left, water and steps on your Home or Lock Screen."
        case .checkIn: "Once a week, get a suggestion on whether to adjust your target."
        case .body: "Log measurements and progress photos privately."
        }
    }

    var symbol: String {
        switch self {
        case .describe: "text.bubble"
        case .scan: "barcode.viewfinder"
        case .water: "drop"
        case .health: "heart"
        case .reminders: "bell.badge"
        case .plan: "calendar.badge.plus"
        case .photo: "camera"
        case .askLeanr: "sparkles"
        case .widgets: "square.grid.2x2"
        case .checkIn: "arrow.triangle.2.circlepath"
        case .body: "ruler"
        }
    }

    /// The button's words and what it does, or nil when the tip only needs reading.
    var action: (label: String, does: Action)? {
        switch self {
        case .describe: ("Try it", .describe)
        case .scan: ("Scan one", .scan)
        case .photo: ("Try it", .photo)
        case .plan: ("Plan ahead", .plan)
        case .health: ("Open Settings", .settings)
        case .reminders: ("Choose reminders", .reminders)
        case .askLeanr: ("Open Find", .find)
        case .checkIn, .body: ("Open Progress", .progress)
        case .water, .widgets: nil
        }
    }

    /// Days with something logged before this is worth mentioning.
    var minLoggedDays: Int {
        switch self {
        case .plan: 3
        case .body: 5
        case .checkIn: 7
        default: 0
        }
    }
}

/// What has been shown, and what is finished with. Kept on this device.
struct FeatureTipState: Equatable {
    /// When Leanr first ran with tips, and whether it was already in use then (an existing tester rather than a new person).
    var firstSeen: Date?
    var existingUser = false
    var shownAt: [String: Date] = [:]
    /// Dismissed, acted on, used, or timed out.
    var finished: Set<String> = []
    var lastFinished: Date?
}

enum FeatureTips {
    static let enabledKey = "tips.enabled"
    static let stateKey = "tips.state"
    static let usedKey = "tips.used"
    /// A tip stays up this long if it's ignored, then is retired for good.
    static let holdDays = 3
    /// Quiet time after one tip is dealt with before the next appears.
    static let gapDays = 2
    /// A new person gets a day to find their feet before the first tip.
    static let newUserDelayDays = 1

    struct Decision: Equatable {
        /// The tip to show now, if any.
        var show: FeatureTip?
        /// Whether `show` has only just been picked, rather than carried on from before.
        var begins = false
        /// Tips that were up and are now finished: used by the person, or ignored for too long.
        var finishing: [FeatureTip] = []
    }

    /// Which tip to show. `available` are the tips that make sense on this device (Health exists, Premium is on) and `used` the
    /// ones whose feature the person already uses. Pure, so the pacing can be checked.
    static func decide(available: Set<FeatureTip>, used: Set<FeatureTip>, loggedDays: Int, state: FeatureTipState, now: Date,
                       calendar: Calendar = .current) -> Decision {
        guard let firstSeen = state.firstSeen else { return Decision() }
        var decision = Decision()
        func days(since date: Date) -> Int { calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0 }
        var finished = state.finished
        // Tips already up: finished once used, or after being ignored for the hold time.
        for tip in FeatureTip.allCases {
            guard let shown = state.shownAt[tip.rawValue], !finished.contains(tip.rawValue) else { continue }
            if used.contains(tip) || days(since: shown) >= holdDays {
                decision.finishing.append(tip); finished.insert(tip.rawValue)
            }
        }
        if let current = FeatureTip.allCases.first(where: { state.shownAt[$0.rawValue] != nil && !finished.contains($0.rawValue) && available.contains($0) }) {
            decision.show = current
            return decision
        }
        // Nothing up. Wait out the quiet time, and a new person's first day.
        let lastEnd = decision.finishing.isEmpty ? state.lastFinished : now
        if let lastEnd, days(since: lastEnd) < gapDays { return decision }
        if !state.existingUser, days(since: firstSeen) < newUserDelayDays { return decision }
        if let next = FeatureTip.allCases.first(where: {
            available.contains($0) && !used.contains($0) && !finished.contains($0.rawValue) && state.shownAt[$0.rawValue] == nil
                && $0.minLoggedDays <= loggedDays
        }) {
            decision.show = next; decision.begins = true
        }
        return decision
    }

    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    // MARK: Saved state

    static func load(_ defaults: UserDefaults = .standard) -> FeatureTipState {
        guard let data = defaults.data(forKey: stateKey), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return FeatureTipState() }
        return FeatureTipState(firstSeen: saved.firstSeen, existingUser: saved.existingUser, shownAt: saved.shownAt,
                               finished: Set(saved.finished), lastFinished: saved.lastFinished)
    }

    static func save(_ state: FeatureTipState, _ defaults: UserDefaults = .standard) {
        let saved = Saved(firstSeen: state.firstSeen, existingUser: state.existingUser, shownAt: state.shownAt,
                          finished: state.finished.sorted(), lastFinished: state.lastFinished)
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: stateKey) }
    }

    private struct Saved: Codable {
        var firstSeen: Date?
        var existingUser: Bool
        var shownAt: [String: Date]
        var finished: [String]
        var lastFinished: Date?
    }

    /// Notes the first run with tips. Someone who had already finished onboarding is an existing tester, who sees tips straight away.
    static func noteLaunch(onboardingCompleted: Bool, now: Date = Date(), defaults: UserDefaults = .standard) {
        var state = load(defaults)
        guard state.firstSeen == nil else { return }
        state.firstSeen = now
        state.existingUser = onboardingCompleted
        save(state, defaults)
    }

    /// Features used in ways Leanr can't see from the data, marked when the person opens them.
    static func marked(_ defaults: UserDefaults = .standard) -> Set<FeatureTip> {
        Set((defaults.stringArray(forKey: usedKey) ?? []).compactMap(FeatureTip.init(rawValue:)))
    }

    static func markUsed(_ tip: FeatureTip, _ defaults: UserDefaults = .standard) {
        var current = Set(defaults.stringArray(forKey: usedKey) ?? [])
        guard current.insert(tip.rawValue).inserted else { return }
        defaults.set(current.sorted(), forKey: usedKey)
    }

    /// Applies a decision: a tip starting is stamped, and finished ones are recorded.
    static func apply(_ decision: Decision, to state: FeatureTipState, now: Date) -> FeatureTipState {
        var updated = state
        for tip in decision.finishing { updated.finished.insert(tip.rawValue); updated.lastFinished = now }
        if decision.begins, let tip = decision.show { updated.shownAt[tip.rawValue] = now }
        return updated
    }

    /// The person closed a tip or acted on it: finished, with the quiet time starting.
    static func finish(_ tip: FeatureTip, in state: FeatureTipState, now: Date) -> FeatureTipState {
        var updated = state
        updated.finished.insert(tip.rawValue); updated.lastFinished = now
        if updated.shownAt[tip.rawValue] == nil { updated.shownAt[tip.rawValue] = now }
        return updated
    }
}
