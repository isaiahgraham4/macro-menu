import SwiftUI

@main
struct LeanrWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchHome().environment(model)
        }
    }
}

/// Three pages: what's left today, things to log with a tap, and water.
struct WatchHome: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        if let today = model.today {
            TabView {
                TodayPage(today: today)
                LogPage(today: today)
                WaterPage(today: today)
            }
            .tabViewStyle(.verticalPage)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "iphone").font(.title2).foregroundStyle(.tint)
                Text("Open Leanr on your iPhone").font(.headline).multilineTextAlignment(.center)
                Text("Today's calories and your usual meals appear here once it has synced.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

/// Calories left in a ring, with protein and water underneath.
struct TodayPage: View {
    let today: WatchSnapshot

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                if let target = today.calorieTarget, target > 0 {
                    Circle().trim(from: 0, to: min(1, today.calories / target))
                        .stroke(today.calories > target ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    if let left = today.caloriesLeft {
                        Text(abs(left).rounded().formatted()).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                        Text(left >= 0 ? "Cal left" : "Cal over").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(today.calories.rounded().formatted()).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                        Text("Cal eaten").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 110, height: 110)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(today.caloriesLeft.map { $0 >= 0 ? "\($0.rounded().formatted()) calories left" : "\((-$0).rounded().formatted()) calories over" }
                                ?? "\(today.calories.rounded().formatted()) calories eaten")
            HStack {
                figure("Protein", "\(today.protein.rounded().formatted())\(today.proteinTarget.map { "/\($0.rounded().formatted())" } ?? "") g")
                figure("Water", Self.water(today.water))
            }
        }
        .navigationTitle("Today")
    }

    private func figure(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func water(_ millilitres: Double) -> String {
        millilitres < 1000 ? "\(Int(millilitres.rounded())) mL" : "\((millilitres / 1000).formatted(.number.precision(.fractionLength(0...2)))) L"
    }
}

/// Usual meals and pinned foods, each logged with a tap.
struct LogPage: View {
    @Environment(WatchModel.self) private var model
    let today: WatchSnapshot

    var body: some View {
        List {
            if today.options.isEmpty {
                Text("Pin foods or log the same meal a few times on your iPhone, and they'll be here to log with a tap.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(today.options) { option in
                Button { model.log(option) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.headline).lineLimit(2)
                            Text("\(option.calories.rounded().formatted()) Cal · \(option.protein.rounded().formatted()) g protein")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: option.loggedToday ? "checkmark.circle.fill" : "plus.circle.fill")
                            .foregroundStyle(option.loggedToday ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    }
                }
                .accessibilityLabel("Log \(option.name)\(option.loggedToday ? ", already logged today" : "")")
            }
        }
        .navigationTitle("Log")
        .overlay(alignment: .bottom) {
            if let confirmation = model.confirmation {
                Text(confirmation).font(.footnote.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .task(id: confirmation) { try? await Task.sleep(for: .seconds(2)); model.confirmation = nil }
            }
        }
    }
}

/// A glass of water with one tap, the same size as on the iPhone.
struct WaterPage: View {
    @Environment(WatchModel.self) private var model
    let today: WatchSnapshot

    var body: some View {
        VStack(spacing: 8) {
            Text(TodayPage.water(today.water)).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text("of \(TodayPage.water(today.waterTarget))").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: min(1, today.water / max(today.waterTarget, 1))).tint(.cyan)
            HStack {
                Button { model.addWater(-today.glass) } label: { Image(systemName: "minus") }
                    .disabled(today.water <= 0).accessibilityLabel("Take off a glass")
                Button { model.addWater(today.glass) } label: { Label(TodayPage.water(today.glass), systemImage: "drop.fill") }
                    .tint(.cyan).accessibilityLabel("Add a glass of water, \(TodayPage.water(today.glass))")
            }
        }
        .navigationTitle("Water")
    }
}
