import SwiftUI
import WidgetKit

struct CaloriesEntry: TimelineEntry {
    let date: Date
    let calories: WidgetCalories?
    var remaining: Double? { calories?.remaining(on: date) }
    var value: String { remaining.map { abs($0).formatted(.number.precision(.fractionLength(0))) } ?? "—" }
    var eatenValue: String { calories.map { $0.eaten(on: date).formatted(.number.precision(.fractionLength(0))) } ?? "—" }
    var targetValue: String { calories?.target.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0))) } ?? "—" }
    var caption: String { (remaining ?? 0) < 0 ? "Cal over target" : "Cals left today" }
    var progress: Double {
        guard let target = calories?.target else { return 0 }
        return min(1, max(0, (calories?.eaten(on: date) ?? 0) / target))
    }
    var prompt: String { calories == nil ? "Open Leanr to sync" : "Set a calorie target" }
    static var example: CaloriesEntry {
        let now = Date()
        return CaloriesEntry(date: now, calories: WidgetCalories(target: 2200, dailyCalories: [WidgetCalories.dayKey(now): 1350]))
    }
}

struct CaloriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { .example }
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? .example : CaloriesEntry(date: Date(), calories: WidgetCalories.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let dates = WidgetCalories.timelineDates(from: Date())
        let snapshot = WidgetCalories.read()
        completion(Timeline(entries: dates.map { CaloriesEntry(date: $0, calories: snapshot) },
                            policy: .after(dates[1])))
    }
}

struct CaloriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(entry.remaining == nil ? "Leanr · \(entry.prompt)" : "Leanr · \(entry.value) \(entry.caption)")
            case .accessoryCircular:
                circularProgress
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Label("Leanr", systemImage: "leaf.fill").font(.caption.weight(.semibold))
                    if entry.remaining != nil {
                        Text("\(entry.value) \(entry.caption)").font(.headline).minimumScaleFactor(0.7).lineLimit(1)
                        ProgressView(value: entry.progress).tint(accent)
                    } else {
                        Text(entry.prompt).font(.caption)
                    }
                }
            default:
                homeScreen
            }
        }
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.remaining == nil ? "Leanr. \(entry.prompt)" : (family == .accessoryCircular ? "Leanr. \(entry.eatenValue) calories eaten out of a daily target of \(entry.targetValue) calories." : "Leanr. \(entry.value) \(entry.caption)"))
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
    }

    private var circularProgress: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().stroke(.primary.opacity(0.18), lineWidth: 3)
                if entry.progress > 0 {
                    Circle().trim(from: 0, to: entry.progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .widgetAccentable()
                }
                VStack(spacing: 1) {
                    Text(entry.eatenValue)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    HStack(spacing: 2) {
                        Text("cals").font(.system(size: 7, weight: .medium))
                        Image(systemName: "leaf.fill").font(.system(size: 6))
                    }
                    Text("/\(entry.targetValue)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.5)
                }.frame(width: max(0, side - 20), height: max(0, side - 20))
            }
            .frame(width: max(0, side - 6), height: max(0, side - 6))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private var homeScreen: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Leanr", systemImage: "leaf.fill")
                    .font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(accent)
                Spacer(minLength: 2)
                if entry.remaining != nil {
                    Text(entry.value).font(.system(size: 38, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1).contentTransition(.numericText())
                    Text(entry.caption).font(.system(.subheadline, design: .rounded, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 2)
                    Text("\(formatted(entry.calories?.eaten(on: entry.date) ?? 0)) / \(formatted(entry.calories?.target ?? 0)) Cal")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Text(entry.prompt).font(.system(.headline, design: .rounded))
                    Text("Your daily balance, at a glance.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if family == .systemMedium, entry.remaining != nil {
                ZStack {
                    Circle().stroke(accent.opacity(0.18), lineWidth: 9)
                    Circle().trim(from: 0, to: entry.progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 4) {
                        Image(systemName: "fork.knife").font(.title3).foregroundStyle(accent)
                        Text("Today").font(.caption.weight(.medium))
                    }
                }.frame(width: 92, height: 92).padding(6).accessibilityHidden(true)
            }
        }
    }
    private func formatted(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
}

struct LeanrCaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.kind, provider: CaloriesProvider()) { entry in
            CaloriesWidgetView(entry: entry)
        }
        .configurationDisplayName("Calories left")
        .description("See today's calories remaining against your Leanr target.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
