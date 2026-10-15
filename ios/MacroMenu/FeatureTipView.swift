import SwiftUI
import WidgetKit

/// The tip card at the top of Today. Closing it, or doing what it suggests, finishes that tip for good.
struct FeatureTipCard: View {
    let tip: FeatureTip
    let act: (FeatureTip.Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: tip.symbol)
                .font(.title3).foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                if let action = tip.action { act(action.does) } else { dismiss() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tip.title).font(.roboto(.headline)).foregroundStyle(.primary)
                    Text(tip.detail).font(.roboto(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    if let action = tip.action {
                        Text(action.label).font(.roboto(.subheadline, weight: .semibold)).foregroundStyle(.tint).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.vertical, 2)
    }
}

extension FeatureTips {
    /// Works out which tip to show now for what this person has and hasn't used, and records it.
    @MainActor static func current(store: AppStore, health: HealthSync, now: Date = Date()) async -> FeatureTip? {
        guard enabled else { return nil }
        let data = store.data
        var used = marked()
        if data.water?.isEmpty == false { used.insert(.water) }
        if health.enabled { used.insert(.health) }
        if (data.plans ?? [:]).values.contains(where: { !$0.isEmpty }) { used.insert(.plan) }
        if MealReminders.anyOn { used.insert(.reminders) }
        if !data.measurementLog.isEmpty { used.insert(.body) }
        if !(data.checkIns ?? []).isEmpty { used.insert(.checkIn) }
        if let widgets = try? await WidgetCenter.shared.currentConfigurations(), !widgets.isEmpty { used.insert(.widgets) }
        var available = Set(FeatureTip.allCases)
        if !health.isAvailable { available.remove(.health) }
        if !Premium.isUnlocked { available.remove(.reminders) }
        var state = load()
        #if DEBUG
        // `-demoTips` shows the first tip every time, as for a tester who has tried nothing, and keeps nothing.
        let demo = CommandLine.arguments.contains("-demoTips")
        if demo { state = FeatureTipState(firstSeen: now.addingTimeInterval(-5 * 24 * 3600), existingUser: true); used = [] }
        #else
        let demo = false
        #endif
        let loggedDays = data.logs.values.filter { !$0.isEmpty }.count
        let decision = decide(available: available, used: used, loggedDays: loggedDays, state: state, now: now)
        if !demo, decision.begins || !decision.finishing.isEmpty { save(apply(decision, to: state, now: now)) }
        return decision.show
    }

    /// The person dismissed the tip or acted on it.
    @MainActor static func finish(_ tip: FeatureTip, now: Date = Date()) {
        #if DEBUG
        if CommandLine.arguments.contains("-demoTips") { return }
        #endif
        save(finish(tip, in: load(), now: now))
    }
}
