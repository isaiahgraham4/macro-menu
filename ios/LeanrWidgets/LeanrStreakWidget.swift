import SwiftUI
import WidgetKit

struct LeanrStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.streakKind, provider: CaloriesProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName("Tracking streak")
        .description("Celebrate consecutive days of logging food. Every tracked day counts.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry
    private var count: Int { entry.calories?.streak(on: entry.date) ?? 0 }
    private var tracked: Bool { entry.calories?.trackingDays.contains(WidgetCalories.dayKey(entry.date)) == true }
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 1) {
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(accent)
                    Text(entry.calories == nil ? "—" : "\(count)").font(.title2.bold()).minimumScaleFactor(0.5)
                    Text("days").font(.system(size: 9))
                }
            } else {
                VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 8) {
                    Label("Tracking streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Text(entry.calories == nil ? "—" : "\(count) day\(count == 1 ? "" : "s")")
                        .font(family == .accessoryRectangular ? .headline : .largeTitle.bold())
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(entry.calories == nil ? "Open Leanr to sync" : tracked ? "Tracked today" : "Log today to \(count > 0 ? "keep it going" : "start")")
                        .font(.caption).foregroundStyle(.secondary)
                    if family == .systemMedium {
                        Text("Consistency counts. Every logged day helps.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .privacySensitive().widgetURL(URL(string: "leanr://today"))
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.calories == nil ? "Open Leanr to sync your tracking streak" : "\(count) day tracking streak. \(tracked ? "Tracked today" : "Log today to continue")")
    }
}
