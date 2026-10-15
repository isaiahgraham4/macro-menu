import SwiftUI
import UserNotifications

/// Offered when someone comes back to Leanr after a few days away with no reminders set up: pick what to be nudged about.
struct ReminderPromptView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var meals: Set<MealTime> = [.breakfast, .lunch, .dinner]
    @State private var water = true
    @State private var denied = false
    @State private var working = false

    private func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
    private var waterDetail: String {
        let schedule = MealReminders.WaterSchedule()
        return "Every \(schedule.everyHours) hours, \(clock(schedule.from)) to \(clock(schedule.until)). Stops once you've reached your target."
    }

    var body: some View {
        NavigationStack {
            LeanrList {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "bell.badge").font(.system(size: 34)).foregroundStyle(.tint)
                        Text("Want a nudge to keep logging?")
                            .font(.roboto(.title2, weight: .bold))
                        Text("Leanr can remind you about meals and water. Reminders only go out if you haven't already logged, and you can change or stop them any time in Settings.")
                            .font(.roboto(.subheadline)).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
                Section {
                    ForEach(MealReminders.meals) { meal in
                        row(title: MealReminders.title(meal),
                            detail: meal == .snacks ? "\(clock(MealReminders.minutes(meal))), only if nothing's logged all day" : clock(MealReminders.minutes(meal)),
                            on: meals.contains(meal)) {
                            if meals.contains(meal) { meals.remove(meal) } else { meals.insert(meal) }
                        }
                    }
                    row(title: "Water", detail: waterDetail, on: water) { water.toggle() }
                }
                Section {
                    Button {
                        working = true
                        Task {
                            let granted = await MealReminders.enable(meals, water: water)
                            working = false
                            UserDefaults.standard.set(Date(), forKey: ReminderPrompt.askedKey)
                            if granted {
                                MealReminders.refresh(store.data, goals: store.goals, logReminders: Premium.isUnlocked)
                                dismiss()
                            } else { denied = true }
                        }
                    } label: {
                        Text("Turn on reminders").font(.roboto(.headline)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || (meals.isEmpty && !water))
                    Button("Not now") {
                        UserDefaults.standard.set(Date(), forKey: ReminderPrompt.askedKey)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Notifications are off for Leanr", isPresented: $denied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    dismiss()
                }
                Button("Not now", role: .cancel) { dismiss() }
            } message: { Text("Turn on notifications for Leanr in the Settings app to get reminders.") }
        }
        .interactiveDismissDisabled(working)
        .onDisappear {
            // Swiping the sheet away counts as asking, so it isn't offered again straight away.
            if UserDefaults.standard.object(forKey: ReminderPrompt.askedKey) == nil {
                UserDefaults.standard.set(Date(), forKey: ReminderPrompt.askedKey)
            }
        }
    }

    private func row(title: String, detail: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.roboto(.body, weight: .medium)).foregroundStyle(.primary)
                    Text(detail).font(.roboto(.caption)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
