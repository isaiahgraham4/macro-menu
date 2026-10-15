import SwiftUI
import WidgetKit
import AppIntents

/// Today's water on the Home Screen and Lock Screen, with a button that adds a glass.
struct LeanrWaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.waterKind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Water")
        .description("Today's water against your target. Tap + to add a glass.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { Self.example }
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? Self.example : CaloriesEntry(date: Date(), calories: WidgetCalories.read()))
    }
    /// Now, and midnight, when the day's water starts again from nothing.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date(), snapshot = WidgetCalories.read()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        completion(Timeline(entries: [now, midnight].map { CaloriesEntry(date: $0, calories: snapshot) }, policy: .after(midnight)))
    }
    static var example: CaloriesEntry {
        let now = Date()
        var snapshot = WidgetCalories(target: 2200, dailyCalories: [:])
        snapshot.water = [WidgetCalories.dayKey(now): 1250]
        snapshot.waterTarget = 2000
        snapshot.waterGlass = 250
        return CaloriesEntry(date: now, calories: snapshot)
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry

    private var drunk: Double { entry.calories?.waterDrunk(on: entry.date) ?? 0 }
    private var target: Double { entry.calories?.waterTarget ?? 2000 }
    private var glass: Double { entry.calories?.waterGlass ?? 250 }
    private var progress: Double { target > 0 ? min(1, drunk / target) : 0 }
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }

    private func amount(_ millilitres: Double) -> String {
        millilitres < 1000 ? "\(Int(millilitres.rounded())) mL" : (millilitres / 1000).formatted(.number.precision(.fractionLength(0...2))) + " L"
    }
    private var addLabel: String { "Add \(amount(glass)) of water" }
    /// The second button on the wide widget: a bottle, or the next size up when a glass is already that big.
    private var bottle: Double { glass == 500 ? 750 : 500 }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("\(amount(drunk)) of \(amount(target)) water")
            case .accessoryCircular:
                Button(intent: LogAgainIntent(option: WidgetCalories.waterOption(glass))) {
                    Gauge(value: progress) {
                        Image(systemName: "drop.fill")
                    } currentValueLabel: {
                        Image(systemName: "plus").font(.caption.weight(.bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(amount(drunk)) of \(amount(target)) water. \(addLabel)")
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Water", systemImage: "drop.fill").font(.caption2.weight(.semibold)).widgetAccentable()
                        Text(amount(drunk)).font(.headline).minimumScaleFactor(0.7).lineLimit(1).invalidatableContent()
                        Gauge(value: progress) { EmptyView() }.gaugeStyle(.accessoryLinearCapacity).invalidatableContent()
                    }
                    Button(intent: LogAgainIntent(option: WidgetCalories.waterOption(glass))) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain).accessibilityLabel(addLabel)
                }
            case .systemMedium:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Water", systemImage: "drop.fill").font(.roboto(.caption, weight: .semibold)).foregroundStyle(.cyan)
                        Spacer(minLength: 0)
                        Text(amount(drunk)).font(.roboto(.title, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1).monospacedDigit().invalidatableContent()
                        Text(drunk >= target ? "Target reached" : "of \(amount(target))").font(.roboto(.caption)).foregroundStyle(.secondary)
                        Gauge(value: progress) { EmptyView() }.gaugeStyle(.linearCapacity).tint(.cyan).accessibilityHidden(true).invalidatableContent()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        ForEach([glass, bottle], id: \.self) { size in
                            Button(intent: LogAgainIntent(option: WidgetCalories.waterOption(size))) {
                                Label("+ \(amount(size))", systemImage: "drop.fill").labelStyle(.titleOnly)
                                    .font(.roboto(.subheadline, weight: .semibold)).frame(maxWidth: .infinity)
                            }
                            .tint(accent).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .accessibilityLabel("Add \(amount(size)) of water")
                        }
                    }
                    .frame(width: 120)
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Label("Water", systemImage: "drop.fill").font(.roboto(.caption, weight: .semibold)).foregroundStyle(.cyan)
                    Spacer(minLength: 0)
                    Text(amount(drunk)).font(.roboto(.title2, weight: .bold)).minimumScaleFactor(0.7).lineLimit(1).monospacedDigit().invalidatableContent()
                    Text(drunk >= target ? "Target reached" : "of \(amount(target))").font(.roboto(.caption)).foregroundStyle(.secondary)
                    Gauge(value: progress) { EmptyView() }.gaugeStyle(.linearCapacity).tint(.cyan).accessibilityHidden(true).invalidatableContent()
                    Spacer(minLength: 0)
                    Button(intent: LogAgainIntent(option: WidgetCalories.waterOption(glass))) {
                        Label("+ \(amount(glass))", systemImage: "drop.fill").labelStyle(.titleOnly)
                            .font(.roboto(.subheadline, weight: .semibold)).frame(maxWidth: .infinity)
                    }
                    .tint(accent).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .accessibilityLabel(addLabel)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}
