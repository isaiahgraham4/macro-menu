import SwiftUI

enum AppTab: Hashable { case today, find, map, meal, myFoods }

/// Which tab is showing, and requests to open Find filtered to one restaurant.
@MainActor @Observable
final class Navigator {
    var tab = AppTab.today
    /// A chain id for Find to filter to; Find clears it once applied.
    var findChain: String?
    /// Changing this rebuilds the Find tab, returning it to its main screen.
    private(set) var findStack = UUID()
    var todayStack = UUID()

    func showOptions(at chain: String) {
        findChain = chain; findStack = UUID(); tab = .find
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = AppStore()
    @State private var location = LocationStore()
    @State private var nav = Navigator()
    @State private var settings = false
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
            Tab("My foods", systemImage: "bookmark", value: .myFoods) { screen(MyFoodsView()) }
        }
        .tint(accent)
        .onChange(of: accentRaw) { store.refreshWidgets() }
        .onChange(of: proteinColour) { store.refreshWidgets() }
        .onChange(of: carbsColour) { store.refreshWidgets() }
        .onChange(of: fatColour) { store.refreshWidgets() }
        .onChange(of: scenePhase) { if scenePhase == .active { store.refreshWidgets() } }
        .onOpenURL { url in
            if url.scheme == "leanr", url.host == "today" {
                settings = false; nav.todayStack = UUID(); nav.tab = .today
            }
        }
        .font(.roboto())
        .environment(store)
        .environment(location)
        .environment(nav)
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: Binding(get: { !onboardingCompleted }, set: { if !$0 { onboardingCompleted = true } })) {
            LeanrOnboarding { onboardingCompleted = true }
                .environment(store).tint(accent)
                .preferredColorScheme(appearance.colorScheme)
        }
        .sheet(isPresented: $settings) {
            NavigationStack { SettingsView() }.tint(accent).font(.roboto()).environment(store).environment(location).environment(nav).preferredColorScheme(appearance.colorScheme)
        }
        .safeAreaInset(edge: .top) {
            if let error = store.loadError { Text(error).font(.roboto(.caption)).padding().frame(maxWidth: .infinity).background(.red.opacity(0.12)) }
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
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
