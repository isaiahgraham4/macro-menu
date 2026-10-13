import SwiftUI
import WidgetKit

@main
struct LeanrWatchWidgets: WidgetBundle {
    var body: some Widget {
        CaloriesComplication()
        ProteinComplication()
        WaterComplication()
    }
}

struct WatchEntry: TimelineEntry {
    var date: Date
    /// Nil until Leanr on iPhone has sent anything.
    var today: WatchSnapshot?
}

/// The latest snapshot now, and the same targets with nothing eaten from midnight, so a complication never carries
/// yesterday's totals into today.
struct WatchProvider: TimelineProvider {
    static let example = WatchSnapshot(day: WatchSnapshot.key(Date()), calories: 1340, calorieTarget: 2200, protein: 96, proteinTarget: 150,
                                       water: 1250, waterTarget: 2000, glass: 250, options: [])

    func placeholder(in context: Context) -> WatchEntry { WatchEntry(date: Date(), today: Self.example) }

    func getSnapshot(in context: Context, completion: @escaping (WatchEntry) -> Void) {
        let stored = WatchStorage.read()?.current()
        completion(WatchEntry(date: Date(), today: stored ?? (context.isPreview ? Self.example : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchEntry>) -> Void) {
        let now = Date(), stored = WatchStorage.read()
        var entries = [WatchEntry(date: now, today: stored?.current(on: now))]
        if let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) {
            entries.append(WatchEntry(date: midnight, today: stored?.current(on: midnight)))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

private func number(_ value: Double) -> String { value.rounded().formatted(.number.precision(.fractionLength(0))) }

private func fraction(_ value: Double, of target: Double?) -> Double {
    guard let target, target > 0 else { return 0 }
    return min(1, max(0, value / target))
}

private func millilitres(_ value: Double) -> String {
    value < 1000 ? "\(Int(value.rounded()))" : (value / 1000).formatted(.number.precision(.fractionLength(0...1))) + "L"
}

// MARK: Calories

struct CaloriesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchStorage.caloriesKind, provider: WatchProvider()) { entry in
            CaloriesComplicationView(entry: entry).containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Calories left")
        .description("What's left of today's calories, from Leanr on your iPhone.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct CaloriesComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var today: WatchSnapshot? { entry.today }
    private var left: Double? { today?.caloriesLeft }
    private var value: String { left.map { number(abs($0)) } ?? today.map { number($0.calories) } ?? "—" }
    private var label: String { left.map { $0 >= 0 ? "left" : "over" } ?? "eaten" }
    private var progress: Double { fraction(today?.calories ?? 0, of: today?.calorieTarget) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(today == nil ? "Leanr" : "\(value) Cal \(label)")
        case .accessoryCorner:
            Image(systemName: "fork.knife").font(.title3).widgetAccentable()
                .widgetLabel {
                    Gauge(value: progress) { Text("Cal") } currentValueLabel: { Text(value) }
                        minimumValueLabel: { Text("") } maximumValueLabel: { Text(value) }
                }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Leanr").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).widgetAccentable()
                Text(today == nil ? "Open Leanr on iPhone" : "\(value) Cal \(label)").font(.headline).minimumScaleFactor(0.7).lineLimit(1)
                if let today, let target = today.proteinTarget {
                    let to = target - today.protein
                    Text(to > 0 ? "\(number(to)) g protein to go" : "Protein target reached").font(.caption2).foregroundStyle(.secondary)
                }
                Gauge(value: progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).widgetAccentable()
            }
        default:
            Gauge(value: progress) {
                Image(systemName: "fork.knife")
            } currentValueLabel: {
                Text(value).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity).widgetAccentable()
            .accessibilityLabel(today == nil ? "Leanr" : "\(value) calories \(label)")
        }
    }
}

// MARK: Protein

struct ProteinComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchStorage.proteinKind, provider: WatchProvider()) { entry in
            ProteinComplicationView(entry: entry).containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Protein")
        .description("Today's protein against your target.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct ProteinComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var eaten: String { entry.today.map { number($0.protein) } ?? "—" }
    private var progress: Double { fraction(entry.today?.protein ?? 0, of: entry.today?.proteinTarget) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.today.map { "\(eaten)\($0.proteinTarget.map { " of \(number($0))" } ?? "") g protein" } ?? "Leanr")
        case .accessoryCorner:
            Text("P").font(.title3.weight(.bold)).widgetAccentable()
                .widgetLabel {
                    Gauge(value: progress) { Text("Protein") } currentValueLabel: { Text(eaten) }
                        minimumValueLabel: { Text("") } maximumValueLabel: { Text("\(eaten) g") }
                }
        default:
            Gauge(value: progress) {
                Text("P")
            } currentValueLabel: {
                Text(eaten).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity).widgetAccentable()
            .accessibilityLabel("\(eaten) grams of protein")
        }
    }
}

// MARK: Water

struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchStorage.waterKind, provider: WatchProvider()) { entry in
            WaterComplicationView(entry: entry).containerBackground(for: .widget) {}
        }
        .configurationDisplayName("Water")
        .description("Today's water against your target.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WaterComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchEntry

    private var drunk: String { entry.today.map { millilitres($0.water) } ?? "—" }
    private var progress: Double { fraction(entry.today?.water ?? 0, of: entry.today?.waterTarget) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.today.map { "\(drunk)\($0.water < 1000 ? " mL" : "") water" } ?? "Leanr")
        case .accessoryCorner:
            Image(systemName: "drop.fill").font(.title3).foregroundStyle(.cyan).widgetAccentable()
                .widgetLabel {
                    Gauge(value: progress) { Text("Water") } currentValueLabel: { Text(drunk) }
                        minimumValueLabel: { Text("") } maximumValueLabel: { Text(drunk) }
                        .tint(.cyan)
                }
        default:
            Gauge(value: progress) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text(drunk).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity).tint(.cyan).widgetAccentable()
            .accessibilityLabel("\(drunk) water")
        }
    }
}
