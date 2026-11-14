import SwiftUI

@main
struct LeanrWatchApp: App {
    @State private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchHome().environment(model)
        }
        .backgroundTask(.watchConnectivity) { await model.finishTransfers() }
    }
}

/// Three pages: what's left today, things to log with a tap, and water. The Digital Crown moves between them.
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
            .tint(today.accentColour)
        } else {
            // Scrolls, so the larger text sizes still fit on a 40mm watch.
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: "iphone").font(.title2).foregroundStyle(.tint)
                    Text("Open Leanrrr on your iPhone").font(.headline).multilineTextAlignment(.center)
                    Text("Today's calories and your usual meals appear here once it has synced.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

/// Calories left in a ring, with protein, water and calories burnt underneath. The ring takes whatever height the figures
/// leave, so it fills a 49mm Ultra and still fits a 40mm SE at any text size.
struct TodayPage: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    let today: WatchSnapshot

    var body: some View {
        VStack(spacing: 6) {
            CaloriesRing(today: today)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .top, spacing: 2) {
                figure("Protein", "\(today.protein.rounded().formatted())\(today.proteinTarget.map { "/\($0.rounded().formatted())" } ?? "") g", today.proteinTint)
                figure("Water", Self.water(today.water), .cyan)
                if let energy = today.energy { figure("Burnt", "\(energy.rounded().formatted()) Cal", .orange) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("Today")
    }

    private func figure(_ title: String, _ value: String, _ colour: Color) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(colour))
            Text(value).font(.footnote.weight(.semibold)).monospacedDigit().privacySensitive()
        }
        .lineLimit(1).minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    static func water(_ millilitres: Double) -> String {
        millilitres < 1000 ? "\(Int(millilitres.rounded())) mL" : "\((millilitres / 1000).formatted(.number.precision(.fractionLength(0...2)))) L"
    }
}

/// The calories ring, drawn to whatever square it's given. With the wrist down it dims to an outline, as Always On expects.
struct CaloriesRing: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    let today: WatchSnapshot

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height), line = max(6, side * 0.09)
            ZStack {
                Circle().stroke(.quaternary, lineWidth: line).opacity(dimmed ? 0.5 : 1)
                if let target = today.calorieTarget, target > 0 {
                    Circle().trim(from: 0, to: min(1, today.calories / target))
                        .stroke(today.calories > target ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint), style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .opacity(dimmed ? 0.55 : 1)
                }
                VStack(spacing: 0) {
                    Text(abs(today.caloriesLeft ?? today.calories).rounded().formatted())
                        .font(.system(size: side * 0.26, weight: .bold, design: .rounded)).monospacedDigit()
                        .privacySensitive()
                    Text(today.caloriesLeft.map { $0 >= 0 ? "Cal left" : "Cal over" } ?? "Cal eaten")
                        .font(.system(size: max(11, side * 0.11))).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.5)
                .padding(line * 1.6)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(today.caloriesLeft.map { $0 >= 0 ? "\($0.rounded().formatted()) calories left" : "\((-$0).rounded().formatted()) calories over" }
                            ?? "\(today.calories.rounded().formatted()) calories eaten")
    }
}

/// Usual meals and pinned foods, each logged with a tap.
struct LogPage: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed
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
                            // One line on every size: "g P" where "g protein" won't fit.
                            ViewThatFits(in: .horizontal) {
                                Text("\(option.calories.rounded().formatted()) Cal · \(option.protein.rounded().formatted()) g protein")
                                Text("\(option.calories.rounded().formatted()) Cal · \(option.protein.rounded().formatted()) g P")
                            }
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: option.loggedToday ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(option.loggedToday || dimmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
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

/// A glass of water with one tap, the same size as on the iPhone. The add button is the wide one, so it's the easy target.
struct WaterPage: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.isLuminanceReduced) private var dimmed
    let today: WatchSnapshot

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(TodayPage.water(today.water)).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("of \(TodayPage.water(today.waterTarget))").font(.caption2).foregroundStyle(.secondary)
            ProgressView(value: min(1, today.water / max(today.waterTarget, 1))).tint(.cyan).opacity(dimmed ? 0.55 : 1)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button { model.addWater(-today.glass) } label: { Image(systemName: "minus").frame(minHeight: 28) }
                    .frame(width: 48).tint(.gray)
                    .disabled(today.water <= 0).accessibilityLabel("Take off a glass")
                Button { model.addWater(today.glass) } label: {
                    Label(TodayPage.water(today.glass), systemImage: "drop.fill").lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .tint(.cyan).accessibilityLabel("Add a glass of water, \(TodayPage.water(today.glass))")
            }
        }
        .navigationTitle("Water")
    }
}
