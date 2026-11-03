import SwiftUI

/// Takeaway roulette: spin a wheel of restaurants and it picks a dinner that fits what's left today.
struct RouletteView: View {
    @Environment(AppStore.self) private var store
    @Environment(LocationStore.self) private var location
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DietFilter.storageKey) private var dietRaw = ""
    @State private var query = FindQuery()
    @State private var slices: [Roulette.Slice] = []
    /// Restaurants chosen for the wheel, kept between visits. None chosen is every restaurant.
    @AppStorage(Roulette.storageKey) private var chosenRaw = ""
    @State private var ready = false
    @State private var angle = 0.0
    @State private var spinning = false
    @State private var winner: MealMatch?
    /// The order last landed on, which stays after `winner` clears, so a new spin can go elsewhere.
    @State private var last: MealMatch?

    /// How long the wheel turns, and how many whole turns it makes on the way.
    private static let spinTime = 4.0
    private static let turns = 6
    /// A moment to see the slice under the pointer, before the list moves to the order.
    private static let hold = Duration.milliseconds(700)

    /// The menu items on the wheel: the app's menus only, since your own foods aren't a restaurant to go to.
    private var chains: [Chain] { store.catalog.chains.filter { $0.id != "mine" && !Roulette.notDinner.contains($0.id) } }
    /// Restaurants Maps found none of within 15 km. Empty until location is allowed.
    private var outOfReach: [String] { chains.map(\.id).filter { location.places[$0]?.isEmpty == true } }
    private var loggedToday: Int { store.data.logs[dayKey(Date())]?.count ?? 0 }
    /// Chosen restaurants still on the menu.
    private var chosen: Set<String> { Set(chosenRaw.split(separator: ",").map(String.init)).intersection(chains.map(\.id)) }
    private var onWheel: Set<String> { Roulette.onWheel(chains.map(\.id), chosen: chosen, outOfReach: Set(outOfReach)) }
    /// Chosen restaurants with no dinner that fits, said under the chips so a missing slice isn't a mystery.
    private var noneFit: [String] {
        guard ready, !spinning else { return [] }
        let landed = Set(slices.map(\.chain))
        return chains.filter { chosen.contains($0.id) && !landed.contains($0.id) }.map(\.name)
    }

    /// What the wheel is worked out from. It holds still while spinning and while it's pointing at a winner.
    private struct Key: Equatable {
        var query: FindQuery, onWheel: Set<String>, foods: Int, held: Bool
    }
    private var key: Key { Key(query: query, onWheel: onWheel, foods: store.catalog.foods.count, held: spinning || winner != nil) }

    var body: some View {
        ScrollViewReader { scroller in
            LeanrList {
                wheelSection
                if let winner {
                    Section("Tonight's dinner") {
                        OrderMatchCard(match: winner, protein: query.protein, mealTime: .dinner).id("winner")
                    }
                }
                restaurantsSection.disabled(spinning)
                limitsSection.disabled(spinning)
            }
            .onChange(of: winner?.id) { _, new in
                guard new != nil else { return }
                withAnimation(reduceMotion ? nil : .smooth) { scroller.scrollTo("winner", anchor: .center) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            BottomActionBar {
                Button(action: spin) {
                    Text(spinning ? "Spinning…" : winner == nil ? "Spin" : "Spin again").frame(maxWidth: .infinity)
                }
                .disabled(spinning || slices.isEmpty)
            }
        }
        .navigationTitle("Takeaway roulette").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: winner?.id) { _, new in new != nil }
        .onChange(of: loggedToday, initial: true) { startFromToday() }
        .onChange(of: dietRaw) { query.diet = DietFilter(raw: dietRaw) }
        .onChange(of: query) { winner = nil }
        .onChange(of: chosenRaw) { winner = nil }
        .task(id: key) { await refresh() }
        .task(id: location.location?.timestamp) {
            if location.isAuthorized { await location.load(chains.map(\.id)) }
        }
    }

    @ViewBuilder private var wheelSection: some View {
        Section {
            if ready && slices.isEmpty {
                ContentUnavailableView("No dinners fit", systemImage: "fork.knife", description: Text(query.calories > 0
                    ? "Try more calories, less protein or more restaurants."
                    : "Today's calories are used up. Raise the limit below to spin anyway."))
            } else {
                Text(summary).font(.roboto(.subheadline, weight: .medium)).multilineTextAlignment(.center)
                    .balanced().frame(maxWidth: .infinity).listRowBackground(Color.clear).listRowSeparator(.hidden)
                FoldRow { fold in
                    RouletteWheel(angle: angle, names: slices.map { store.chainName($0.chain) })
                        .frame(maxWidth: 340).frame(maxWidth: .infinity).leftOfFold(fold)
                }
                .contentShape(Rectangle()).onTapGesture(perform: spin)
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
        }
    }

    private var limitsSection: some View {
        Section {
            FoldRow { fold in
                let pair = AnyLayout.columns(spacing: 10, fold: fold)
                pair {
                    StatField(title: "Calories up to", unit: "Cal", value: $query.calories)
                    StatField(title: "Protein at least", unit: "g", value: $query.protein)
                }
            }
            .listRowSeparator(.hidden)
            OptionalNumberField(title: "Carbs up to (g)", value: $query.carbs)
            OptionalNumberField(title: "Fat up to (g)", value: $query.fat)
            NavigationLink { DietNeedsView() } label: {
                LabeledContent {
                    Text(query.diet.isEmpty ? "None" : query.diet.summary).lineLimit(2).multilineTextAlignment(.trailing)
                } label: { Label("Dietary needs", systemImage: "leaf") }
            }
        } header: { Text("Limits for tonight") } footer: {
            Text("Starts from what's left today, up to one and a half typical meals. Limits leave out items with missing values.")
        }
    }

    private var restaurantsSection: some View {
        Section {
            // Every restaurant in view at once, so choosing a few takes a tap each and no scrolling.
            FlowLayout(spacing: 8) {
                Chip(title: "All", selected: chosen.isEmpty) { chosenRaw = "" }
                ForEach(chains) { chain in
                    Chip(title: chain.name, selected: chosen.contains(chain.id)) { toggle(chain.id) }
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("Restaurants")
                Spacer()
                if !chosen.isEmpty { Text("\(chosen.count) of \(chains.count) on the wheel").textCase(nil).monospacedDigit() }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if chosen.isEmpty {
                    Text(location.isAuthorized ? "Every restaurant within 15 km is on the wheel. Choose some to spin between just those."
                         : "Every restaurant is on the wheel. Choose some to spin between just those.")
                } else {
                    Text("Only the restaurants you choose are on the wheel, and they stay chosen next time.")
                }
                if !noneFit.isEmpty {
                    Text("Nothing at \(noneFit.formatted(.list(type: .or))) fits these limits.")
                }
            }
        }
    }

    private func toggle(_ chain: String) {
        var picked = chosen
        if picked.contains(chain) { picked.remove(chain) } else { picked.insert(chain) }
        chosenRaw = picked.sorted().joined(separator: ",")
    }

    /// The limits in words, above the wheel.
    private var summary: String {
        var parts = ["Up to \(query.calories.number) Cal", "at least \(query.protein.number) g protein"]
        if let carbs = query.carbs { parts.append("\(carbs.number) g carbs") }
        if let fat = query.fat { parts.append("\(fat.number) g fat") }
        return parts.joined(separator: " · ")
    }

    /// Sets the limits from what's left today, on opening and after anything is logged, so a second spin doesn't count the first dinner twice over.
    private func startFromToday() {
        let diet = DietFilter(raw: dietRaw)
        query = Roulette.limits(store.data, goals: store.goals, diet: diet) ?? FindQuery(calories: 0, protein: 0, customise: false, diet: diet)
    }

    private func refresh() async {
        guard !key.held else { return }
        // Empty chains in a query means every restaurant, so a wheel with none on it is settled here.
        guard !key.onWheel.isEmpty else { slices = []; ready = true; return }
        var request = query
        request.chains = key.onWheel
        let foods = store.catalog.foods
        let work = Task.detached(priority: .userInitiated) { Roulette.slices(foods, query: request) }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard !Task.isCancelled else { return }
        slices = result; ready = true
    }

    private func spin() {
        var random = SystemRandomNumberGenerator()
        guard !spinning, let pick = Roulette.spin(slices, after: last, using: &random) else { return }
        // Lands anywhere on the slice but its edges, so the pointer never sits on the line between two.
        let stop = Roulette.landing(from: angle, slice: pick.slice, count: slices.count, turns: Self.turns, offset: .random(in: -0.35...0.35))
        last = pick.order
        winner = nil
        if reduceMotion {
            angle = stop
            land(pick.order)
        } else {
            spinning = true
            withAnimation(.timingCurve(0.12, 0.7, 0.12, 1, duration: Self.spinTime)) { angle = stop } completion: {
                Task {
                    try? await Task.sleep(for: Self.hold)
                    land(pick.order)
                }
            }
        }
    }

    private func land(_ order: MealMatch) {
        spinning = false
        winner = order
        AccessibilityNotification.Announcement("\(store.chainName(order.chain)): \(order.items.map(\.food.name).joined(separator: " and ")), \(order.total.cal.number) Cal").post()
    }
}

/// The wheel, turned to `angle`, with a tap on the selection haptic for each slice that passes the pointer.
private struct RouletteWheel: View, Animatable {
    var angle: Double
    let names: [String]

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        ZStack(alignment: .top) {
            WheelFace(names: names).rotationEffect(.degrees(angle))
            Pointer().fill(.primary).frame(width: 22, height: 26).offset(y: -4)
        }
        .aspectRatio(1, contentMode: .fit)
        .sensoryFeedback(.selection, trigger: Roulette.slice(at: angle, count: names.count))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wheel of \(names.count) restaurant\(names.count == 1 ? "" : "s")")
    }
}

/// The slices and their names. Apart from the wheel, so it isn't redrawn for each frame of a spin.
private struct WheelFace: View {
    let names: [String]
    @Environment(\.self) private var environment
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    private static let board = Color(red: 0.89, green: 0.77, blue: 0.59)
    private static let paper = Color(red: 0.97, green: 0.95, blue: 0.89)

    /// The app colour takes turns with the timber, like the confetti: macro colours mean something else.
    /// A wheel with an odd number of slices ends on paper, so the same colours never meet at the top.
    private func isPaper(_ index: Int) -> Bool { names.count % 2 == 1 && index == names.count - 1 }
    private func fill(_ index: Int) -> AnyShapeStyle {
        if isPaper(index) { return AnyShapeStyle(Self.paper) }
        return index % 2 == 0 ? AnyShapeStyle(.tint) : AnyShapeStyle(Self.board)
    }
    private func ink(_ index: Int) -> Color { index % 2 == 0 && !isPaper(index) ? accentInk : boardInk }
    /// White or timber, whichever reads better on the app colour as it is now: the green is far lighter in dark mode.
    private var accentInk: Color {
        let accent = AppAccent.resolved(accentRaw).color.resolve(in: environment)
        return 0.2126 * accent.linearRed + 0.7152 * accent.linearGreen + 0.0722 * accent.linearBlue <= 0.24 ? .white : boardInk
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height), radius = side / 2
            let sweep = 360 / Double(max(names.count, 1))
            ZStack {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    WheelSlice(start: Double(index) * sweep, sweep: sweep).fill(fill(index))
                    // Read from the rim in, along the middle of the slice.
                    Text(name.uppercased()).font(.display(size: side * (names.count > 12 ? 0.05 : 0.058))).foregroundStyle(ink(index))
                        .lineLimit(1).minimumScaleFactor(0.5)
                        .frame(width: radius * 0.68, alignment: .trailing)
                        .offset(x: radius * 0.56)
                        .rotationEffect(.degrees((Double(index) + 0.5) * sweep - 90))
                }
                Circle().strokeBorder(boardInk.opacity(0.25), lineWidth: 1)
                Circle().fill(Color(.secondarySystemGroupedBackground)).frame(width: side * 0.16, height: side * 0.16)
                Image(systemName: "fork.knife").font(.system(size: side * 0.055)).foregroundStyle(.tint)
            }
            .frame(width: side, height: side)
        }
    }
}

/// One slice, measured clockwise from the top of the wheel.
private struct WheelSlice: Shape {
    let start: Double, sweep: Double
    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: centre)
        path.addArc(center: centre, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(start - 90), endAngle: .degrees(start + sweep - 90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The pointer at the top of the wheel, tip down.
private struct Pointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
