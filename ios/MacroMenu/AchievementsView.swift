import SwiftUI

/// Every milestone reached so far, and the next of each kind to aim for.
struct AchievementsView: View {
    @Environment(AppStore.self) private var store
    @State private var sharing: Moment?

    var body: some View {
        let shelf = store.data.achievements()
        LeanrList {
            ForEach(Achievement.Group.allCases, id: \.self) { group in
                let rows = shelf.filter { $0.group == group }
                if !rows.isEmpty {
                    Section(group.rawValue) {
                        ForEach(rows) { row($0) }
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .sheet(item: $sharing) { moment in NavigationStack { MomentSharePreview(moment: moment) } }
    }

    private func row(_ achievement: Achievement) -> some View {
        let copy = achievement.moment.copy
        return HStack(spacing: 14) {
            Image(systemName: copy.icon).font(.title2)
                .foregroundStyle(achievement.earned ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary)).frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title).font(.roboto(.headline)).foregroundStyle(achievement.earned ? .primary : .secondary)
                if let left = achievement.left {
                    Text(left).font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                }
                if let progress = achievement.progress { ProgressView(value: progress).tint(.accentColor).accessibilityHidden(true) }
            }
            Spacer(minLength: 0)
            if achievement.earned && copy.shareable {
                Button { sharing = achievement.moment } label: {
                    Image(systemName: "square.and.arrow.up").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).accessibilityLabel("Share \(copy.title) as an image")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
