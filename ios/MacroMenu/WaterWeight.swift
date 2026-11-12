import Foundation

/// One amount of water added on Today, the watch, a widget or Siri, with when it was drunk. Only the last two days are kept;
/// they're there to tell how much of a weigh-in is water that hasn't been through yet (see `WaterWeight`).
struct WaterSip: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var time: Date
    var millilitres: Double
    var isValid: Bool { millilitres.isFinite && millilitres > 0 && millilitres <= Water.dayLimit }
}

/// How much of a weigh-in is water drunk in the hours before it, so a reading taken after a bottle of water isn't mistaken
/// for real weight gain.
///
/// A rough model, not a measurement. A drink sits in the stomach and is absorbed over about half an hour (`absorbHalfLife`).
/// Once it's in the blood, water beyond what you need is passed by the kidneys, with the excess halving about every 75 minutes
/// (`excreteHalfLife`). That fits studies where well-hydrated adults drink a litre: most of it is passed within two to four
/// hours. Meanwhile you keep losing water through breath, sweat and a minimum of urine (`baselineLoss`), so a drink after a
/// few dry hours first makes up that shortfall and only the rest is extra. The simulation starts at the first drink in the
/// eight hours before the weigh-in, taking you as normally hydrated then, and 1 mL of water weighs 1 g.
///
/// Weighing first thing, before drinking, gives nothing to take off, which is why morning weigh-ins are the most reliable.
enum WaterWeight {
    static let absorbHalfLife = 0.25 * 3600
    static let excreteHalfLife = 1.25 * 3600
    /// Millilitres an hour lost whatever you drink.
    static let baselineLoss = 50.0
    /// Drinks further back than this have long been passed.
    static let window = 8.0 * 3600
    /// Simulation step.
    static let step = 60.0
    /// Below this many kilograms the estimate isn't worth showing or taking off.
    static let smallest = 0.05
    /// How long sips are kept.
    static let keep = 48.0 * 3600

    /// Kilograms of the weight at `time` that are water drunk beforehand and not yet absorbed into normal hydration or passed.
    static func kilograms(at time: Date, sips: [WaterSip]) -> Double {
        let start = time.addingTimeInterval(-window)
        let recent = sips.filter { $0.isValid && $0.time > start && $0.time <= time }.sorted { $0.time < $1.time }
        guard let first = recent.first else { return 0 }
        let absorb = 1 - pow(0.5, step / absorbHalfLife)
        let excrete = 1 - pow(0.5, step / excreteHalfLife)
        let loss = baselineLoss * step / 3600
        // Millilitres in the stomach, and millilitres above (or below, when negative) normal hydration in the body.
        var stomach = 0.0, body = 0.0
        var next = 0
        var now = first.time
        while true {
            while next < recent.count, recent[next].time <= now { stomach += recent[next].millilitres; next += 1 }
            if now >= time { break }
            let absorbed = stomach * absorb
            stomach -= absorbed
            body += absorbed - loss - max(0, body) * excrete
            now = min(time, now.addingTimeInterval(step))
        }
        let kg = max(0, stomach + body) / 1000
        return kg >= smallest ? kg.hundredth : 0
    }

    static func kilograms(at time: Date, in data: AppData) -> Double { kilograms(at: time, sips: data.waterSips ?? []) }

    /// "About 0.4 kg of this is probably water from the 750 mL you had in the 2 hours before."
    static func explanation(kg: Double, at time: Date, sips: [WaterSip]) -> String {
        let recent = sips.filter { $0.isValid && $0.time <= time && $0.time > time.addingTimeInterval(-window) }
        let total = recent.reduce(0) { $0 + $1.millilitres }
        let earliest = recent.map(\.time).min() ?? time
        let hours = max(1, Int((time.timeIntervalSince(earliest) / 3600).rounded(.up)))
        return "About \(kg.number) kg of this is probably water you haven't passed yet, from the \(Water.text(total)) you logged "
            + "in the \(hours == 1 ? "hour" : "\(hours) hours") before. Your trend uses \(kg.number) kg less. Weighing before you drink in the morning avoids this."
    }

    // MARK: Keeping sips in step with the day totals

    /// Records water added to `day` (or taken off, when negative). Added water gets a sip only when the day is today, since a
    /// time is only known for water logged as it's drunk; taking water off removes the latest sips that day first.
    static func record(_ millilitres: Double, on day: String, at time: Date, in data: inout AppData, calendar: Calendar = .current) {
        var sips = data.waterSips ?? []
        if millilitres > 0 {
            if dayKey(time, calendar: calendar) == day { sips.append(WaterSip(time: time, millilitres: millilitres)) }
        } else {
            var left = -millilitres
            for index in sips.indices.reversed() where left > 0 && dayKey(sips[index].time, calendar: calendar) == day {
                let taken = min(left, sips[index].millilitres)
                sips[index].millilitres -= taken
                left -= taken
            }
            sips.removeAll { $0.millilitres <= 0 }
        }
        data.waterSips = sips
        tidy(&data, now: time, calendar: calendar)
    }

    /// Drops sips older than two days, and the oldest sips of any day whose sips add up to more than its total
    /// (after water was taken off on another device, say).
    static func tidy(_ data: inout AppData, now: Date = Date(), calendar: Calendar = .current) {
        let cutoff = now.addingTimeInterval(-keep)
        var sips = (data.waterSips ?? []).filter { $0.isValid && $0.time > cutoff }.sorted { $0.time < $1.time }
        let byDay = Dictionary(grouping: sips.indices) { dayKey(sips[$0].time, calendar: calendar) }
        var drop = Set<UUID>()
        for (day, indices) in byDay {
            var over = indices.reduce(0) { $0 + sips[$1].millilitres } - Water.total(data, on: day)
            for index in indices where over > 0 {
                let taken = min(over, sips[index].millilitres)
                sips[index].millilitres -= taken
                over -= taken
                if sips[index].millilitres <= 0 { drop.insert(sips[index].id) }
            }
        }
        sips.removeAll { drop.contains($0.id) }
        data.waterSips = sips.isEmpty ? nil : sips
    }

    /// Both copies' sips, by ID, for a backup merge.
    static func merged(_ current: [WaterSip]?, _ incoming: [WaterSip]?) -> [WaterSip]? {
        var sips = current ?? []
        for sip in incoming ?? [] where !sips.contains(where: { $0.id == sip.id }) { sips.append(sip) }
        return sips.isEmpty ? nil : sips
    }

    /// For an iCloud merge: sips added here since `base` are kept and sips removed here stay removed.
    static func keepingLocal(_ merged: [WaterSip]?, local: [WaterSip]?, base: [WaterSip]?) -> [WaterSip]? {
        let here = Dictionary((local ?? []).map { ($0.id, $0) }) { a, _ in a }
        let before = Set((base ?? []).map(\.id))
        var sips = (merged ?? []).filter { here[$0.id] != nil || !before.contains($0.id) }
        for (id, sip) in here {
            if let i = sips.firstIndex(where: { $0.id == id }) { sips[i] = sip } else { sips.append(sip) }
        }
        return sips.isEmpty ? nil : sips
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
