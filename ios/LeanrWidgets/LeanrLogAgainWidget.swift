import SwiftUI
import WidgetKit
import AppIntents

/// One-tap logging from the Home Screen and Lock Screen: your usual meal for this time of day, then pinned foods.
struct LeanrLogAgainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.logAgainKind, provider: LogAgainProvider()) { entry in
            LogAgainWidgetView(entry: entry)
        }
        .configurationDisplayName("Log again")
        .description("Log your usual meal or a pinned food with one tap, without opening Leanr.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct LogAgainProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { Self.example }
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? Self.example : CaloriesEntry(date: Date(), calories: WidgetCalories.read()))
    }
    /// A new entry whenever the meal time changes, so the usual meal follows the clock, and at midnight for the ticks.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date(), snapshot = WidgetCalories.read()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        let dates = ([now, midnight] + MealSlot.changes(after: now)).sorted()
        completion(Timeline(entries: dates.map { CaloriesEntry(date: $0, calories: snapshot) }, policy: .after(dates.last ?? midnight)))
    }
    static var example: CaloriesEntry {
        let now = Date()
        var snapshot = WidgetCalories(target: 2200, dailyCalories: [WidgetCalories.dayKey(now): 1350])
        snapshot.quickLogOptions = [
            WidgetQuickLog(id: "usual:\(MealSlot.at(now))", name: "Oats with berries", calories: 420, mealTime: MealSlot.at(now)),
            WidgetQuickLog(id: "pin:example-1", name: "Zinger Burger", calories: 448),
            WidgetQuickLog(id: "pin:example-2", name: "Protein shake", calories: 210)
        ]
        return CaloriesEntry(date: now, calories: snapshot)
    }
}

struct LogAgainWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry
    private var options: [WidgetQuickLog] { entry.calories?.quickLogs(at: entry.date) ?? [] }
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    private var today: String { WidgetCalories.dayKey(entry.date) }

    var body: some View {
        Group {
            if let first = options.first {
                switch family {
                case .accessoryCircular: circular(first)
                case .accessoryRectangular: rectangular(first)
                case .systemSmall: small(first)
                default: medium
                }
            } else {
                empty
            }
        }
        .privacySensitive()
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private func logged(_ option: WidgetQuickLog) -> Bool { option.lastLogged == today }
    private func calories(_ option: WidgetQuickLog) -> String { option.calories.formatted(.number.precision(.fractionLength(0))) }
    private func detail(_ option: WidgetQuickLog) -> String {
        option.isUsual ? "Usual \(option.mealTime ?? "meal")" : "Pinned"
    }
    private func label(_ option: WidgetQuickLog) -> String {
        "Log \(option.name), \(calories(option)) calories\(logged(option) ? ". Already logged today" : "")"
    }

    private func circular(_ option: WidgetQuickLog) -> some View {
        Button(intent: LogAgainIntent(option: option.id)) {
            VStack(spacing: 1) {
                Image(systemName: logged(option) ? "checkmark" : "plus").font(.roboto(.headline, weight: .bold))
                Text(calories(option)).font(.roboto(size: 11, weight: .semibold)).minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AccessoryWidgetBackground() }
            .clipShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label(option))
    }

    private func rectangular(_ option: WidgetQuickLog) -> some View {
        Button(intent: LogAgainIntent(option: option.id)) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(logged(option) ? "Logged today" : "Log again").font(.roboto(.caption, weight: .semibold))
                    Text(option.name).font(.roboto(.headline)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(calories(option)) Cal · \(detail(option))").font(.roboto(.caption)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: logged(option) ? "checkmark.circle" : "plus.circle.fill").font(.title2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).accessibilityLabel(label(option))
    }

    private func small(_ option: WidgetQuickLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Log again", systemImage: "arrow.uturn.backward").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
            Spacer(minLength: 0)
            Text(option.name).font(.roboto(.headline)).lineLimit(2).minimumScaleFactor(0.8)
            Text("\(calories(option)) Cal · \(detail(option))").font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            logButton(option, title: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Log again", systemImage: "arrow.uturn.backward").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
                Spacer()
                if let left = entry.remaining {
                    Text(left >= 0 ? "\(entry.value) Cal left" : "\(entry.value) Cal over").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
            ForEach(options.prefix(3)) { option in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name).font(.roboto(.subheadline, weight: .semibold)).lineLimit(1)
                        Text("\(calories(option)) Cal · \(detail(option))").font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    logButton(option, title: false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func logButton(_ option: WidgetQuickLog, title: Bool) -> some View {
        Button(intent: LogAgainIntent(option: option.id)) {
            if title {
                Label(logged(option) ? "Log again" : "Log", systemImage: logged(option) ? "checkmark" : "plus")
                    .font(.roboto(.subheadline, weight: .semibold)).frame(maxWidth: .infinity)
            } else {
                Image(systemName: logged(option) ? "checkmark" : "plus").font(.roboto(.subheadline, weight: .bold)).frame(width: 22, height: 22)
            }
        }
        .tint(accent).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        .accessibilityLabel(label(option))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            if family == .accessoryCircular {
                Image(systemName: "plus").font(.title3).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { AccessoryWidgetBackground() }.clipShape(Circle())
            } else {
                Label("Log again", systemImage: "arrow.uturn.backward").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
                Text(entry.calories == nil ? "Open Leanr to sync" : "Pin a food or log a few meals in Leanr to see them here.")
                    .font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
