import SwiftUI
import WidgetKit
import AppIntents

/// Today's planned meals on the Home Screen and Lock Screen: the next one to eat, with a tick that logs it.
struct LeanrPlannedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetCalories.plannedKind, provider: PlannedProvider()) { entry in
            PlannedWidgetView(entry: entry)
        }
        .configurationDisplayName("Planned meals")
        .description("Your next planned meal, logged with a tick when you've eaten it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct PlannedProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaloriesEntry { Self.example }
    func getSnapshot(in context: Context, completion: @escaping (CaloriesEntry) -> Void) {
        completion(context.isPreview ? Self.example : CaloriesEntry(date: Date(), calories: WidgetCalories.read()))
    }
    /// Now, and midnight, when today's plan is over.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaloriesEntry>) -> Void) {
        let now = Date(), snapshot = WidgetCalories.read()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        completion(Timeline(entries: [now, midnight].map { CaloriesEntry(date: $0, calories: snapshot) }, policy: .after(midnight)))
    }
    static var example: CaloriesEntry {
        let now = Date()
        var snapshot = WidgetCalories(target: 2200, dailyCalories: [WidgetCalories.dayKey(now): 640])
        snapshot.plannedDay = WidgetCalories.dayKey(now)
        snapshot.planned = [
            WidgetQuickLog(id: "plan:example-1", name: "Chicken burrito bowl", calories: 620, mealTime: "lunch"),
            WidgetQuickLog(id: "plan:example-2", name: "Greek yoghurt and berries", calories: 210, mealTime: "snacks"),
            WidgetQuickLog(id: "plan:example-3", name: "Salmon, rice and greens", calories: 680, mealTime: "dinner")
        ]
        return CaloriesEntry(date: now, calories: snapshot)
    }
}

struct PlannedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CaloriesEntry
    private var meals: [WidgetQuickLog] { entry.calories?.plannedMeals(on: entry.date) ?? [] }
    private var accent: Color { (entry.calories?.selectedAccent ?? .standard).color }

    var body: some View {
        Group {
            if let next = meals.first {
                switch family {
                case .accessoryRectangular: rectangular(next)
                case .systemSmall: small(next)
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

    private func calories(_ meal: WidgetQuickLog) -> String { meal.calories.formatted(.number.precision(.fractionLength(0))) }
    private func mealTitle(_ meal: WidgetQuickLog) -> String { (meal.mealTime ?? "meal").capitalized }
    private func label(_ meal: WidgetQuickLog) -> String { "Log \(meal.name), planned for \(mealTitle(meal).lowercased()), \(calories(meal)) calories" }

    private func rectangular(_ meal: WidgetQuickLog) -> some View {
        Button(intent: LogAgainIntent(option: meal.id)) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next · \(mealTitle(meal))").font(.roboto(.caption, weight: .semibold))
                    Text(meal.name).font(.roboto(.headline)).lineLimit(1).minimumScaleFactor(0.7).invalidatableContent()
                    Text("\(calories(meal)) Cal\(meals.count > 1 ? " · \(meals.count - 1) more planned" : "")").font(.roboto(.caption)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark.circle").font(.title2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain).accessibilityLabel(label(meal))
    }

    private func small(_ meal: WidgetQuickLog) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next · \(mealTitle(meal))", systemImage: "calendar").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
            Spacer(minLength: 0)
            Text(meal.name).font(.roboto(.headline)).lineLimit(2).minimumScaleFactor(0.8).invalidatableContent()
            Text("\(calories(meal)) Cal\(meals.count > 1 ? " · \(meals.count - 1) more" : "")").font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            tick(meal, title: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Planned today", systemImage: "calendar").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
                Spacer()
                if let left = entry.remaining {
                    Text(left >= 0 ? "\(entry.value) Cal left" : "\(entry.value) Cal over").font(.roboto(.caption)).foregroundStyle(.secondary)
                }
            }
            ForEach(meals.prefix(3)) { meal in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(meal.name).font(.roboto(.subheadline, weight: .semibold)).lineLimit(1).invalidatableContent()
                        Text("\(mealTitle(meal)) · \(calories(meal)) Cal").font(.roboto(.caption)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    tick(meal, title: false)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tick(_ meal: WidgetQuickLog, title: Bool) -> some View {
        Button(intent: LogAgainIntent(option: meal.id)) {
            if title {
                Label("Eaten", systemImage: "checkmark").font(.roboto(.subheadline, weight: .semibold)).frame(maxWidth: .infinity)
            } else {
                Image(systemName: "checkmark").font(.roboto(.subheadline, weight: .bold)).frame(width: 22, height: 22)
            }
        }
        .tint(accent).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        .accessibilityLabel(label(meal))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Planned meals", systemImage: "calendar").font(.roboto(.caption, weight: .semibold)).foregroundStyle(accent)
            Text(entry.calories == nil ? "Open Leanr to sync" : "Nothing left planned for today. Plan ahead from Today in Leanr.")
                .font(.roboto(.caption)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
