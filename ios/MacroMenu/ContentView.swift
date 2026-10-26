import SwiftUI
import UserNotifications
import AppIntents

enum AppTab: Hashable { case today, find, map, meal, progress }

/// Which tab is showing, and requests to open Find filtered to one restaurant.
@MainActor @Observable
final class Navigator {
    var tab = AppTab.today
    /// A chain id for Find to filter to; Find clears it once applied.
    var findChain: String?
    /// Changing this rebuilds the Find tab, returning it to its main screen.
    private(set) var findStack = UUID()
    var todayStack = UUID()
    /// Set by the Scan control: Today opens the barcode scanner, after closing whatever sheet is up.
    var scanRequested = false
    /// A sheet a feature tip asks ContentView to open.
    var requestedSheet: RequestedSheet?
    enum RequestedSheet { case settings, reminders }
    /// Set when the weekly review notification is tapped.
    var showWeeklyReview = false
    /// A food or search opened from Siri or Visual Intelligence, shown over the current tab.
    var opened: Opened?
    enum Opened: Identifiable {
        case food(Food), search(String)
        var id: String { switch self { case .food(let food): "food:" + food.id; case .search(let text): "search:" + text } }
    }

    func showOptions(at chain: String) {
        findChain = chain; findStack = UUID(); tab = .find
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppServices.store
    @State private var location = LocationStore()
    @State private var nav = AppServices.nav
    @State private var health = AppServices.health
    @State private var cloud = AppServices.cloud
    @State private var settings = false
    @State private var reminderPrompt = false
    @AppStorage("leanr.onboarding.completed") private var onboardingCompleted = false
    @AppStorage(MacroColours.proteinKey) private var proteinColour = "blue"
    @AppStorage(MacroColours.carbsKey) private var carbsColour = "orange"
    @AppStorage(MacroColours.fatKey) private var fatColour = "red"
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    private var accent: Color { AppAccent.resolved(accentRaw).color }
    var body: some View {
        TabView(selection: $nav.tab) {
            Tab("Today", systemImage: "calendar", value: .today) { screen(TodayView()).id(nav.todayStack) }
            Tab("Find", systemImage: "magnifyingglass", value: .find) { screen(FindView()).id(nav.findStack) }
            Tab("Map", systemImage: "map", value: .map) { screen(NearbyView()) }
            Tab("Meal", systemImage: "fork.knife", value: .meal) { screen(MealView()) }.badge(store.data.tray.count)
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) { screen(ProgressTabView()) }
        }
        .tint(accent)
        .onChange(of: accentRaw) { store.refreshWidgets() }
        .onChange(of: proteinColour) { store.refreshWidgets() }
        .onChange(of: carbsColour) { store.refreshWidgets() }
        .onChange(of: fatColour) { store.refreshWidgets() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { UserDefaults.standard.set(Date(), forKey: ReminderPrompt.lastActiveKey) }
            if scenePhase == .active {
                checkReminderPrompt()
                AppServices.logQueued()
                // Siri recognises the foods you've pinned or logged recently by name.
                LeanrShortcuts.updateAppShortcutParameters()
                if Premium.subscriptionsEnabled { Task { await Purchases.shared.refresh() } }
                store.refreshWidgets()
                cloud.schedule(after: 0)
                AppServices.rebookReminders()
                Task { await health.refresh() }
                Task { await AppServices.checkMenu() }
            }
        }
        .task {
            FeatureTips.noteLaunch(onboardingCompleted: onboardingCompleted)
            // A cold launch doesn't report a scene phase change, so the first visit after days away is checked here.
            checkReminderPrompt()
            await cloud.sync()
            AppServices.rebookReminders()
            await health.refresh()
        }
        .onChange(of: nav.scanRequested) {
            // The scanner opens over Today, so anything already covering it is closed first.
            if nav.scanRequested { settings = false; reminderPrompt = false; nav.showWeeklyReview = false }
        }
        .onChange(of: nav.requestedSheet) {
            switch nav.requestedSheet {
            case .settings: settings = true
            case .reminders: reminderPrompt = true
            case nil: break
            }
            nav.requestedSheet = nil
        }
        .onOpenURL { url in
            if url.scheme == "leanr", url.host == "today" {
                settings = false; nav.todayStack = UUID(); nav.tab = .today
            } else if url.scheme == "leanr", url.host == "progress" {
                settings = false; nav.tab = .progress
            } else if url.scheme == "leanr", url.host == "scan" {
                nav.opened = nil; nav.tab = .today; nav.scanRequested = true
            }
        }
        .font(.roboto())
        .environment(store)
        .environment(location)
        .environment(nav)
        .environment(health)
        .environment(cloud)
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
            LeanrOnboarding { onboardingCompleted = true }
                .environment(store).environment(location).environment(health).tint(accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .sheet(item: $nav.opened) { opened in
            NavigationStack {
                Group {
                    switch opened {
                    case .food(let food): FoodDetailView(food: food)
                    case .search(let text): BrowseView(initialSearch: text)
                    }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { nav.opened = nil } } }
            }.tint(accent).font(.roboto()).environment(store).environment(location).environment(nav)
                .environment(health).environment(cloud).preferredColorScheme(appearance.colorScheme)
        }
        .sheet(isPresented: $reminderPrompt) {
            ReminderPromptView().environment(store).tint(accent).font(.roboto()).preferredColorScheme(appearance.colorScheme)
        }
        .sheet(isPresented: $nav.showWeeklyReview) {
            NavigationStack {
                WeeklyReviewView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { nav.showWeeklyReview = false } } }
            }.tint(accent).font(.roboto()).environment(store).preferredColorScheme(appearance.colorScheme)
        }
        .sheet(isPresented: $settings) {
            NavigationStack { SettingsView() }.tint(accent).font(.roboto()).environment(store).environment(location).environment(nav)
                .environment(health).environment(cloud).preferredColorScheme(appearance.colorScheme)
        }
        .safeAreaInset(edge: .top) {
            if let error = store.loadError { Text(error).font(.roboto(.caption)).padding().frame(maxWidth: .infinity).background(.red.opacity(0.12)) }
        }
        .overlay(alignment: .top) {
            if let step = store.undo {
                HStack(spacing: 14) {
                    Text(store.notice ?? step.label).font(.roboto(.subheadline, weight: .semibold)).lineLimit(2)
                    Button("Undo") { store.undoLast() }.font(.roboto(.subheadline, weight: .bold))
                }
                .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule()).padding(.top, 8).padding(.horizontal, 16)
                .accessibilityAddTraits(.updatesFrequently)
                .task(id: step.id) { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { store.dismissUndo(step.id); store.notice = nil } }
            } else if let notice = store.notice {
                Text(notice).font(.roboto(.subheadline, weight: .semibold)).padding(.horizontal,20).padding(.vertical,12)
                    .background(.regularMaterial, in: Capsule()).padding(.top,8)
                    .accessibilityAddTraits(.updatesFrequently)
                    .task(id: notice) { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { store.notice = nil } }
                    .onTapGesture { store.notice = nil }
            }
        }
        .alert("Couldn’t complete that", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    /// A tab's root screen with Settings at the top right.
    /// Offers reminders to someone coming back after a few days away with none set up. The last visit is stamped when Leanr
    /// goes to the background, and again here, so a first launch has no earlier visit and never asks straight away.
    private func checkReminderPrompt() {
        let defaults = UserDefaults.standard
        var last = defaults.object(forKey: ReminderPrompt.lastActiveKey) as? Date
        defaults.set(Date(), forKey: ReminderPrompt.lastActiveKey)
        #if DEBUG
        // `-demoAway` behaves as if Leanr was last opened five days ago, to try the reminders prompt.
        if CommandLine.arguments.contains("-demoAway") { last = Date().addingTimeInterval(-5 * 24 * 3600) }
        #endif
        guard onboardingCompleted, !reminderPrompt, !settings, nav.opened == nil, !nav.showWeeklyReview else { return }
        var asked = defaults.object(forKey: ReminderPrompt.askedKey) as? Date
        #if DEBUG
        if CommandLine.arguments.contains("-demoAway") { asked = nil }
        #endif
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if ReminderPrompt.shouldShow(now: Date(), lastActive: last, lastAsked: asked, anyReminderOn: MealReminders.anyOn,
                                         notificationsDenied: status == .denied, canChoose: Premium.isUnlocked) { reminderPrompt = true }
        }
    }

    private func screen(_ root: some View) -> some View {
        NavigationStack {
            root.toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings")
                }
            }
        }
    }
}
#Preview { ContentView() }
