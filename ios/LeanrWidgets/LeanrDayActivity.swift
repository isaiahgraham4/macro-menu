import ActivityKit
import SwiftUI
import WidgetKit

/// Calories left today, kept in view on the Lock Screen and in the Dynamic Island.
struct LeanrDayActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LeanrDayAttributes.self) { context in
            DayActivityLockScreen(state: context.state)
                .padding(16)
                .widgetURL(URL(string: "leanr://today"))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DayRing(state: state, lineWidth: 5).frame(width: 44, height: 44).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(state.figure).font(.roboto(.title2, weight: .bold)).monospacedDigit()
                        Text(state.caption).font(.roboto(.caption)).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) { DayProtein(state: state) }
            } compactLeading: {
                Image(systemName: "leaf.fill").foregroundStyle(state.color)
            } compactTrailing: {
                Text(state.figure).font(.roboto(.caption, weight: .bold)).monospacedDigit().foregroundStyle(state.color)
            } minimal: {
                DayRing(state: state, lineWidth: 3)
            }
            .widgetURL(URL(string: "leanr://today"))
            .keylineTint(state.color)
        }
    }
}

private struct DayRing: View {
    let state: LeanrDayAttributes.ContentState
    let lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.3), lineWidth: lineWidth)
            Circle().trim(from: 0, to: state.progress)
                .stroke(state.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

private struct DayProtein: View {
    let state: LeanrDayAttributes.ContentState
    var body: some View {
        if let target = state.proteinTarget {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Protein").font(.roboto(.caption, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.protein.rounded().formatted()) / \(target.rounded().formatted()) g").font(.roboto(.caption)).monospacedDigit()
                }
                Gauge(value: min(state.protein, target), in: 0...max(target, 1)) { EmptyView() }
                    .gaugeStyle(.linearCapacity).tint(state.color).accessibilityHidden(true)
            }
        }
    }
}

private struct DayActivityLockScreen: View {
    let state: LeanrDayAttributes.ContentState
    var body: some View {
        HStack(spacing: 16) {
            DayRing(state: state, lineWidth: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.figure).font(.roboto(.title2, weight: .bold)).monospacedDigit()
                    Text(state.caption).font(.roboto(.subheadline)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Label("Leanr", systemImage: "leaf.fill").labelStyle(.iconOnly).font(.caption).foregroundStyle(state.color)
                }
                DayProtein(state: state)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
