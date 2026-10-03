import Foundation

/// A restaurant's weekly opening hours, read from OpenStreetMap, and whether it's open at a given moment.
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

    /// The time zone the hours are in: the phone's own (restaurants are nearby) unless an offset is given. A restaurant on the
    /// phone's offset uses the phone's time zone, which knows when daylight saving changes; one elsewhere uses the fixed offset.
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

    // MARK: OpenStreetMap opening_hours

    private static let dayNames = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    /// Reads an OpenStreetMap `opening_hours` value, such as "Mo-Fr 06:00-24:00; Sa,Su 07:00-23:00", "Mo-Su 10:00-02:00"
    /// or "24/7". Public holiday, school holiday and date rules are skipped. Nil when the value uses anything else, or
    /// says nothing about which days it's open, so hours are never guessed.
    static func parseOSM(_ text: String) -> PlaceHours? {
        var days: [[(Int, Int)]?] = Array(repeating: nil, count: 7)
        for rule in text.split(separator: ";") {
            // ", " followed by days after a time or "off" starts another rule that adds to the ones before it.
            for (index, part) in additiveParts(String(rule)).enumerated() {
                // "Mo-Th, Su 10:00-23:00" lists days with spaces too.
                let trimmed = part.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #",\s+(?=[A-Za-z])"#, with: ",", options: .regularExpression)
                if trimmed.isEmpty { continue }
                if skipped(trimmed) { continue }
                guard let (selected, spans) = osmRule(trimmed) else { return nil }
                for day in selected {
                    if index == 0 || spans.isEmpty { days[day] = spans } else { days[day] = (days[day] ?? []) + spans }
                }
            }
        }
        guard days.contains(where: { !($0 ?? []).isEmpty }) else { return nil }
        if days.allSatisfy({ $0?.contains { $0.0 == 0 && $0.1 >= 1440 } ?? false }) {
            return PlaceHours(periods: [.init(openDay: 0, openMinute: 0, closeDay: nil, closeMinute: nil)], utcOffsetMinutes: nil)
        }
        let periods = days.enumerated().flatMap { day, spans in
            (spans ?? []).map { start, end in
                Period(openDay: day, openMinute: start, closeDay: (day + end / 1440) % 7, closeMinute: end % 1440)
            }
        }
        return PlaceHours(periods: periods, utcOffsetMinutes: nil)
    }

    /// Splits "Mo-Th 10:00-22:00, Fr-Sa 10:00-02:00" into its rules, leaving day lists like "Mo-We,Su" whole.
    private static func additiveParts(_ rule: String) -> [String] {
        var parts: [String] = [], current = ""
        let pieces = rule.components(separatedBy: ",")
        for (index, piece) in pieces.enumerated() {
            if index > 0 {
                let before = current.trimmingCharacters(in: .whitespaces).lowercased()
                let next = piece.trimmingCharacters(in: .whitespaces)
                let endsRule = before.last?.isNumber == true || before.hasSuffix("off") || before.hasSuffix("closed")
                if endsRule && next.first?.isLetter == true { parts.append(current); current = piece; continue }
                current += ","
            }
            current += piece
        }
        parts.append(current)
        return parts
    }

    /// Public and school holidays, months, dates and weeks: rules the app leaves out.
    private static func skipped(_ rule: String) -> Bool {
        let selector = rule.prefix { $0 != " " }
        let first = String(selector.prefix { $0 != "," && $0 != "-" })
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let holidaysOnly = selector.split(separator: ",").allSatisfy { $0 == "PH" || $0 == "SH" }
        return holidaysOnly || first == "week" || months.contains(first) || first.allSatisfy(\.isNumber) && first.count == 4
    }

    /// One rule: the days it covers (Sunday 0) and its opening spans in minutes after midnight (an end past 1440 runs
    /// into the next day). No spans means closed those days.
    private static func osmRule(_ rule: String) -> ([Int], [(Int, Int)])? {
        var rest = Substring(rule)
        var selected = Array(0..<7)
        if let first = rest.first, first.isLetter, !rest.hasPrefix("off"), !rest.hasPrefix("closed"), !rest.hasPrefix("open") {
            let selector = rest.prefix { $0 != " " }
            rest = rest.dropFirst(selector.count).drop { $0 == " " }
            selected = []
            for item in selector.split(separator: ",") where item != "PH" && item != "SH" {
                let ends = item.split(separator: "-").map(String.init)
                guard let from = ends.first.flatMap({ dayNames.firstIndex(of: $0) }) else { return nil }
                guard ends.count == 2 else { if ends.count == 1 { selected.append(from); continue } else { return nil } }
                guard let to = dayNames.firstIndex(of: ends[1]) else { return nil }
                var day = from
                while true { selected.append(day); if day == to { break }; day = (day + 1) % 7 }
            }
        }
        let times = rest.trimmingCharacters(in: .whitespaces)
        if times == "off" || times == "closed" { return (selected, []) }
        if times.isEmpty || times == "open" || times == "24/7" { return (selected, [(0, 1440)]) }
        var spans: [(Int, Int)] = []
        for span in times.split(separator: ",") {
            let ends = span.trimmingCharacters(in: .whitespaces).split(separator: "-")
            guard ends.count == 2, let start = minutes(ends[0]), var end = minutes(ends[1]), start < 1440 else { return nil }
            if end <= start { end += 1440 }
            spans.append((start, end))
        }
        return (selected, spans)
    }

    /// "06:30" as 390; hours up to 48 for times past midnight.
    private static func minutes(_ text: Substring) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...48).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}

/// Finds a restaurant's hours in an OpenStreetMap (Overpass) answer: the closest mapped place within `radius` metres
/// whose name or brand matches the chain.
enum OSMHours {
    struct Element: Decodable, Sendable {
        struct Centre: Decodable, Sendable { var lat: Double; var lon: Double }
        var lat: Double?
        var lon: Double?
        var center: Centre?
        var tags: [String: String]?
    }
    struct Response: Decodable, Sendable { var elements: [Element] }

    static let radius = 120.0

    static func pick(_ elements: [Element], latitude: Double, longitude: Double, match: [String]) -> String? {
        let found = elements.compactMap { element -> (String, Double)? in
            guard let tags = element.tags, let hours = tags["opening_hours"],
                  let lat = element.lat ?? element.center?.lat, let lon = element.lon ?? element.center?.lon else { return nil }
            let names = [tags["name"], tags["brand"], tags["name:en"]].compactMap { $0?.lowercased() }
            guard names.contains(where: { name in match.contains { name.contains($0) } }) else { return nil }
            let metres = hypot((lat - latitude) * 111_000, (lon - longitude) * 111_000 * cos(latitude * .pi / 180))
            return metres <= radius ? (hours, metres) : nil
        }
        return found.min { $0.1 < $1.1 }?.0
    }

    /// One Overpass query for every place at once: anything with opening hours near each of them.
    static func query(_ spots: [(latitude: Double, longitude: Double)]) -> String {
        let parts = spots.map { String(format: "nwr(around:%.0f,%.5f,%.5f)[\"opening_hours\"];", radius, $0.latitude, $0.longitude) }
        return "[out:json][timeout:25];(" + parts.joined() + ");out tags center;"
    }
}
