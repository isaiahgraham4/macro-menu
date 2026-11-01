import SwiftUI

/// Shows what's in `store.moments` over the app, one at a time. They wait a beat, so a sheet can close and the figures
/// can finish counting first. The goal weight fills the screen; everything else is a card that leaves by itself.
struct MomentsOverlay: ViewModifier {
    let store: AppStore
    let openWeeklyReview: () -> Void
    @State private var showing: Moment?
    /// The moment whose share image is open; its card waits until the sheet closes.
    @State private var sharing: Moment?
    @State private var yearReview: YearReview?
    /// One followed another, so there's no need to wait as long.
    @State private var following = false
    private static let wait = Duration.seconds(1.1)
    private static let gap = Duration.seconds(0.4)
    private static let cardTime = Duration.seconds(3)

    func body(content: Content) -> some View {
        content
            .overlay {
                if let showing, !showing.fillsScreen { MomentConfetti().transition(.opacity) }
            }
            .overlay(alignment: .bottom) {
                if let showing {
                    if case .goalReached(let goal) = showing {
                        GoalReachedView(goal: goal, done: finish, share: { sharing = showing }).transition(.opacity)
                    } else {
                        MomentCard(moment: showing, dismiss: finish, open: { open(showing) }, share: { sharing = showing })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.2), value: showing)
            .sensoryFeedback(.impact(weight: .light), trigger: store.mealsLoggedPulse)
            .sensoryFeedback(.success, trigger: showing) { _, new in new != nil }
            .sensoryFeedback(.error, trigger: store.refusedPulse)
            .sensoryFeedback(.error, trigger: store.errorMessage) { _, new in new != nil }
            .sheet(item: $sharing, onDismiss: { if showing?.fillsScreen != true { finish() } }) { moment in
                NavigationStack { MomentSharePreview(moment: moment) }
            }
            .sheet(item: $yearReview) { review in NavigationStack { YearReviewView(review: review).environment(store) } }
            .task(id: store.moments.first) {
                guard let next = store.moments.first else { return }
                try? await Task.sleep(for: following ? Self.gap : Self.wait)
                guard !Task.isCancelled else { return }
                showing = next
                if case .goalReached = next { return }
                try? await Task.sleep(for: Self.cardTime)
                if !Task.isCancelled && sharing == nil { finish() }
            }
            .onChange(of: store.moments.isEmpty) { if store.moments.isEmpty { showing = nil; following = false } }
            #if DEBUG
            // `-demoMoments` plays one of each at launch, to try them without reaching them.
            .task {
                guard CommandLine.arguments.contains("-demoMoments") else { return }
                try? await Task.sleep(for: .seconds(2))
                store.moments = [.targets([Moment.Hit(name: "Protein", value: 152, target: 150, unit: "g")]), .allTargets(4), .streak(7),
                                 .streakSaved(12), .meals(100), .steps(10240, goal: 8000), .week(logged: 5, onTarget: 4, protein: 3), .year(2026),
                                 .weighIn(moved: 4.2, losing: true, progress: 0.6, remaining: 2.8, goal: 75),
                                 .goalReached(WeightGoal(kg: 75, startKg: 82, set: Date()))]
            }
            #endif
    }

    private func open(_ moment: Moment) {
        finish()
        if case .year(let year) = moment {
            yearReview = YearReview.make(store.data, year: year, restaurants: Set(store.catalog.chains.map(\.id)))
        } else {
            openWeeklyReview()
        }
    }

    private func finish() {
        showing = nil
        following = true
        if !store.moments.isEmpty { store.moments.removeFirst() }
    }
}

private extension Moment {
    var fillsScreen: Bool { if case .goalReached = self { true } else { false } }
}

private struct MomentConfetti: View {
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if !reduceMotion {
            Confetti(colours: confettiColours(accent: AppAccent.resolved(accentRaw).color, dark: scheme == .dark),
                     count: 60, power: 700, origin: UnitPoint(x: 0.5, y: 0.78))
        }
    }
}

/// The app colour with the worktop's own timber and paper, so the flecks look like part of the counter.
private func confettiColours(accent: Color, dark: Bool) -> [Color] {
    [accent, Color(red: 0.89, green: 0.77, blue: 0.59), Color(red: 0.64, green: 0.52, blue: 0.37),
     dark ? Color(red: 0.97, green: 0.95, blue: 0.89) : accent.opacity(0.6)]
}
let boardInk = Color(red: 0.23, green: 0.17, blue: 0.10)

/// A target, milestone or weigh-in on a small cutting board that rises from the bottom of the screen.
private struct MomentCard: View {
    let moment: Moment
    let dismiss: () -> Void
    /// Opens what the card is about, for the weekly review.
    let open: () -> Void
    let share: () -> Void
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var appeared = false
    private var accent: Color { AppAccent.resolved(accentRaw).color }
    private var copy: Moment.Copy { moment.copy }
    private var title: String { copy.title }
    private var detail: String { copy.detail }

    var body: some View {
        FoldRow { fold in
            VStack(alignment: .leading, spacing: 12) {
                // The icon sits beside the words, or above them at the largest text sizes where there's no room beside.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
                layout {
                    Image(systemName: copy.icon).font(.title).foregroundStyle(accent)
                        .symbolEffect(.bounce, value: appeared).frame(width: 40).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let figure = copy.figure {
                            Text(title).font(.roboto(.subheadline, weight: .medium))
                            CountingNumber(appeared ? figure.value : 0, step: figure.step) { "\($0.number) \(figure.unit)" }
                                .font(.roboto(.title, weight: .bold))
                                .animation(reduceMotion ? nil : .easeOut(duration: 1), value: appeared)
                        } else {
                            Text(title).font(.display(.title3)).balanced()
                        }
                        Text(detail).font(.roboto(.subheadline))
                    }
                    // Takes the lines it needs, so a long title wraps at the largest text sizes rather than being cut short.
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if copy.shareable {
                        Button(action: share) {
                            Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless).tint(accent).accessibilityLabel("Share as an image")
                    }
                }
                if let progress = copy.progress {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(boardInk.opacity(0.14))
                            Capsule().fill(accent).frame(width: geometry.size.width * (appeared ? progress : 0))
                        }
                    }
                    .frame(height: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1), value: appeared)
                    .accessibilityHidden(true)
                }
            }
            .foregroundStyle(boardInk)
            .padding(20)
            .background { CuttingBoard() }
            .frame(maxWidth: 420)
            .contentShape(Rectangle())
            .onTapGesture(perform: moment.opensReview ? open : dismiss)
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: moment.opensReview ? "Open the review" : "Dismiss", moment.opensReview ? open : dismiss)
            .padding(.horizontal, 16)
            .leftOfFold(fold).frame(maxWidth: .infinity)
        }
        .padding(.bottom, 92)
        .onAppear {
            appeared = true
            AccessibilityNotification.Announcement("\(title) \(detail)").post()
        }
    }
}

/// Leanr's one big moment: the first time a weigh-in takes your trend to your goal weight.
private struct GoalReachedView: View {
    let goal: WeightGoal
    let done: () -> Void
    let share: () -> Void
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var appeared = false
    @State private var confetti = true
    private var change: Double { abs(goal.startKg - goal.kg) }

    var body: some View {
        ZStack {
            LeanrBackground()
            FoldRow { fold in
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "party.popper.fill").font(.system(size: 56)).foregroundStyle(.tint)
                            .symbolEffect(.bounce, value: appeared)
                            .accessibilityHidden(true)
                        Text("Goal reached").font(.display())
                        CountingNumber(appeared ? change : 0, step: 0.1) { "\($0.number) kg" }
                            .font(.roboto(.largeTitle, weight: .bold))
                            .animation(reduceMotion ? nil : .easeOut(duration: 1.2), value: appeared)
                        Text("\(goal.kg < goal.startKg ? "lost" : "gained") since you started at \(goal.startKg.number) kg. You're at \(goal.kg.number) kg.")
                            .font(.roboto(.headline)).balanced()
                    }
                    .multilineTextAlignment(.center)
                    .foregroundStyle(boardInk)
                    .padding(32).frame(maxWidth: .infinity)
                    .background { CuttingBoard() }
                    .accessibilityElement(children: .combine)
                    Button(action: share) { Label("Share as an image", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    Button(action: done) { Text("Done").frame(maxWidth: .infinity).padding(.vertical, 8) }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                .frame(maxWidth: 420).padding(.horizontal, 24)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                .leftOfFold(fold).frame(maxWidth: .infinity)
            }
            if confetti && !reduceMotion {
                Confetti(colours: confettiColours(accent: AppAccent.resolved(accentRaw).color, dark: scheme == .dark), count: 150, power: 1300, origin: UnitPoint(x: 0.5, y: 0.4))
            }
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { withAnimation(.spring(duration: 0.4, bounce: 0.3)) { appeared = true } }
        .task {
            try? await Task.sleep(for: .seconds(Confetti.seconds))
            confetti = false
        }
    }
}

/// Paper flecks thrown up from one point, which drift down and fade.
private struct Confetti: View {
    static let seconds = 3.5
    let colours: [Color]
    let power: Double
    let origin: UnitPoint

    init(colours: [Color], count: Int, power: Double, origin: UnitPoint) {
        self.colours = colours; self.power = power; self.origin = origin
        _pieces = State(initialValue: (0..<count).map { _ in Piece() })
    }

    private struct Piece {
        var angle = Double.random(in: 0..<(2 * .pi))
        var speed = Double.random(in: 0.15...1)
        var spin = Double.random(in: -9...9)
        var flutter = Double.random(in: 4...11)
        var drift = Double.random(in: -24...24)
        var size = CGSize(width: Double.random(in: 5...8), height: Double.random(in: 8...13))
        var colour = Int.random(in: 0..<4)
    }
    @State private var pieces: [Piece]
    @State private var start = Date.now

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSince(start)
                let drag = 3.2, fall = 170.0
                let from = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
                for piece in pieces {
                    // Thrown out fast, slowed by the air, then falling steadily.
                    let thrown = (1 - exp(-drag * time)) / drag * piece.speed * power
                    let x = from.x + cos(piece.angle) * thrown + piece.drift * sin(time * 2)
                    let y = from.y + sin(piece.angle) * thrown + fall * time
                    var fleck = context
                    fleck.opacity = min(1, max(0, (Self.seconds - time) / 1.2))
                    fleck.translateBy(x: x, y: y)
                    fleck.rotate(by: .radians(piece.spin * time))
                    fleck.scaleBy(x: 1, y: cos(piece.flutter * time))
                    fleck.fill(Path(CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2, width: piece.size.width, height: piece.size.height)),
                               with: .color(colours[piece.colour % colours.count]))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The animation when Leanr opens from cold. It lives as long as the app does, so coming back to an app that's still
/// running shows nothing.
struct LaunchOverlay: ViewModifier {
    /// False during first-run onboarding, which opens straight over the app.
    let showing: Bool
    @State private var launching = true
    func body(content: Content) -> some View {
        content.overlay {
            if launching && showing { LaunchAnimation { launching = false } }
        }
    }
}

private struct LaunchAnimation: View {
    let finished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var leaf = false
    @State private var word = false
    @State private var leaving = false
    private static let letters = Array("TAKEAWISE").map(String.init)

    var body: some View {
        ZStack {
            LeanrBackground()
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.system(size: 40)).foregroundStyle(AppAccent.emerald)
                    .scaleEffect(leaf || reduceMotion ? 1 : 0.3)
                    .rotationEffect(.degrees(leaf || reduceMotion ? 0 : -50))
                    .opacity(leaf || reduceMotion ? 1 : 0)
                HStack(spacing: 2) {
                    ForEach(Self.letters.indices, id: \.self) { index in
                        Text(Self.letters[index]).font(.display(.largeTitle))
                            .offset(y: word || reduceMotion ? 0 : 18)
                            .opacity(word || reduceMotion ? 1 : 0)
                            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.25).delay(Double(index) * 0.045), value: word)
                    }
                }
            }
            .scaleEffect(leaving && !reduceMotion ? 1.08 : 1)
        }
        .opacity(leaving ? 0 : 1)
        .accessibilityHidden(true)
        .task {
            withAnimation(.spring(duration: 0.45, bounce: 0.35)) { leaf = true }
            try? await Task.sleep(for: .milliseconds(120))
            word = true
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 300 : 900))
            withAnimation(.easeIn(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
            finished()
        }
    }
}
