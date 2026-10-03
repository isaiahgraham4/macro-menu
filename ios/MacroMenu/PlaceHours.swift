import Foundation

/// A restaurant's weekly opening hours, read from Google Places, and whether it's open at a given moment.
/// Times are the restaurant's own clock times; `utcOffsetMinutes` says which time zone that clock is in.
struct PlaceHours: Equatable, Sendable {
    /// One opening in the week. Days run Sunday (0) to Saturday (6); minutes are after midnight.
    /// No close means open around the clock.
    struct Period: Equatable, Sendable {
        var openDay: Int
        var openMinute: Int
        var closeDay: Int?
        var closeMinute: Int?
    }
    var periods: [Period]
    var utcOffsetMinutes: Int?
    /// The restaurant's time zone when known exactly (checks use this); otherwise worked out from `utcOffsetMinutes`.
    var zone: TimeZone? = nil

    enum Status: Equatable, Sendable {
        case alwaysOpen
        /// Open now; `closes` is when it next closes.
        case open(closes: Date)
        /// Closed now; `opens` is when it next opens, if it ever does.
        case closed(opens: Date?)
    }

    private static let week = 7 * 1440

    /// The time zone the hours are in. Google gives only today's offset, so a restaurant on the phone's offset uses the
    /// phone's time zone, which knows when daylight saving changes; one elsewhere uses the fixed offset.
    var timeZone: TimeZone {
        if let zone { return zone }
        guard let offset = utcOffsetMinutes, offset * 60 != TimeZone.current.secondsFromGMT() else { return .current }
        return TimeZone(secondsFromGMT: offset * 60) ?? .current
    }

    /// The moment `minutesAhead` minutes of the restaurant's week after `now`, as a time on its clock, so a daylight-saving
    /// change in between doesn't shift it (opening at 8 am stays 8 am).
    private func moment(_ minutesAhead: Int, after now: Date, weekMinute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let total = weekMinute % 1440 + minutesAhead
        let day = calendar.date(byAdding: .day, value: total / 1440, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: (total % 1440) / 60, minute: total % 60, second: 0, of: day) ?? day
    }

    /// Minutes since Sunday midnight at the restaurant.
    private func weekMinute(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return ((parts.weekday ?? 1) - 1) * 1440 + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Each opening as minutes since Sunday midnight, with the close after the open (wrapping past Saturday night).
    private var spans: [(start: Int, end: Int)] {
        periods.compactMap { period in
            guard let closeDay = period.closeDay, let closeMinute = period.closeMinute else { return nil }
            let start = period.openDay * 1440 + period.openMinute
            var end = closeDay * 1440 + closeMinute
            if end <= start { end += Self.week }
            return (start, end)
        }
    }

    var isAlwaysOpen: Bool { periods.contains { $0.closeDay == nil } }

    func status(at date: Date) -> Status {
        if isAlwaysOpen { return .alwaysOpen }
        let now = weekMinute(date), spans = spans
        guard !spans.isEmpty else { return .closed(opens: nil) }
        // Open if now falls inside an opening; a following opening that starts as this one ends (past midnight) counts as the same stretch.
        if var current = spans.first(where: { (now - $0.start + Self.week) % Self.week < $0.end - $0.start }) {
            var minutesLeft = current.end - current.start - (now - current.start + Self.week) % Self.week
            for _ in 0..<7 {
                guard let next = spans.first(where: { $0.start % Self.week == current.end % Self.week && $0 != current }) else { break }
                minutesLeft += next.end - next.start; current = next
                if minutesLeft >= Self.week { return .alwaysOpen }
            }
            return .open(closes: moment(minutesLeft, after: date, weekMinute: now))
        }
        let wait = spans.map { ($0.start - now + Self.week) % Self.week }.min() ?? 0
        return .closed(opens: moment(wait, after: date, weekMinute: now))
    }

    /// "Open · closes 10:00 pm", "Closed · opens 8:00 am tomorrow", "Open 24 hours".
    func summary(at date: Date) -> String {
        switch status(at: date) {
        case .alwaysOpen: return "Open 24 hours"
        case .open(let closes): return "Open · closes \(clock(closes, from: date))"
        case .closed(let opens?): return "Closed · opens \(clock(opens, from: date))"
        case .closed(nil): return "Closed"
        }
    }

    var isOpenNow: Bool { if case .closed = status(at: Date()) { false } else { true } }

    /// A time, with "tomorrow" or the weekday when it isn't today at the restaurant.
    private func clock(_ time: Date, from now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let style = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
        let text = time.formatted(style)
        if calendar.isDate(time, inSameDayAs: now) { return text }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(time, inSameDayAs: tomorrow) { return "\(text) tomorrow" }
        return "\(time.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))) \(text)"
    }

    /// One line per day, Monday first: "8:00 am – 10:00 pm", "Closed" or "Open 24 hours".
    var week: [(day: String, hours: String)] {
        var calendar = Calendar(identifier: .gregorian); calendar.locale = .current
        let names = calendar.weekdaySymbols
        return [1, 2, 3, 4, 5, 6, 0].map { day in
            if isAlwaysOpen { return (names[day], "Open 24 hours") }
            let opens = periods.filter { $0.openDay == day }.sorted { $0.openMinute < $1.openMinute }
            guard !opens.isEmpty else { return (names[day], "Closed") }
            let text = opens.map { period -> String in
                guard let close = period.closeMinute else { return "Open 24 hours" }
                if period.openMinute == 0 && close == 0 && period.closeDay == (day + 1) % 7 { return "Open 24 hours" }
                return "\(Self.time(period.openMinute)) – \(Self.time(close))"
            }.joined(separator: ", ")
            return (names[day], text)
        }
    }

    /// Minutes after midnight as the phone shows times, e.g. "8:00 am".
    static func time(_ minutes: Int) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: minutes / 60, minute: minutes % 60)) ?? Date()
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: TimeZone(secondsFromGMT: 0)!))
    }

    // MARK: Google Places (New) JSON

    private struct Response: Decodable {
        struct Hours: Decodable {
            struct Point: Decodable { var day: Int?; var hour: Int?; var minute: Int? }
            struct Span: Decodable { var open: Point?; var close: Point? }
            var periods: [Span]?
        }
        var regularOpeningHours: Hours?
        var currentOpeningHours: Hours?
        var utcOffsetMinutes: Int?
    }

    /// Reads a Place Details response. This week's hours (which include public holidays) win over the usual ones.
    /// Nil when the place doesn't list any hours.
    static func parse(_ data: Data) -> PlaceHours? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let spans = response.currentOpeningHours?.periods ?? response.regularOpeningHours?.periods, !spans.isEmpty else { return nil }
        let periods = spans.compactMap { span -> Period? in
            guard let open = span.open, let day = open.day else { return nil }
            return Period(openDay: day, openMinute: (open.hour ?? 0) * 60 + (open.minute ?? 0),
                          closeDay: span.close?.day, closeMinute: span.close.map { ($0.hour ?? 0) * 60 + ($0.minute ?? 0) })
        }
        return periods.isEmpty ? nil : PlaceHours(periods: periods, utcOffsetMinutes: response.utcOffsetMinutes)
    }
}

