import SwiftUI

struct TrackingCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date
    @State private var month = Date()
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var days: [Date] {
        (calendar.range(of: .day, in: .month, for: start) ?? 1..<1).compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }
    }
    private var offset: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = store.data.widgetCalories
            let streak = snapshot.streak(on: context.date)
            LeanrList {
                Section {
                    Label("\(streak) day\(streak == 1 ? "" : "s") in a row", systemImage: "flame.fill")
                        .font(.title2.bold()).foregroundStyle(.tint)
                    Text("Every day you log food counts. Staying within your target isn’t required.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if !snapshot.trackingDays.contains(dayKey(context.date)) {
                        Text(streak > 0 ? "Log today to continue your streak." : "Log food today to start your streak.")
                            .font(.subheadline.weight(.medium))
                    }
                }
                Section {
                    HStack {
                        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Previous month")
                        Spacer()
                        Text(start.formatted(.dateTime.month(.wide).year())).font(.headline)
                        Spacer()
                        Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .disabled(calendar.isDate(start, equalTo: context.date, toGranularity: .month))
                            .accessibilityLabel("Next month")
                    }.buttonStyle(.borderless)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                        ForEach(0..<7, id: \.self) { index in
                            Text(calendar.veryShortStandaloneWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 44) }
                        ForEach(days, id: \.self) { day in dayCell(day, now: context.date, snapshot: snapshot) }
                    }
                } footer: {
                    Text("Rings show calories eaten against that day’s target. A dot means food was logged. Tap a day to view its meals.")
                }
            }
        }
        .navigationTitle("Tracking calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { month = selectedDate }
    }

    private func move(_ amount: Int) {
        if let next = calendar.date(byAdding: .month, value: amount, to: start) { month = next }
    }

    private func dayCell(_ day: Date, now: Date, snapshot: WidgetCalories) -> some View {
        let key = dayKey(day)
        let logged = snapshot.trackingDays.contains(key)
        let eaten = snapshot.dailyCalories[key] ?? 0
        let goal = calendar.isDate(day, inSameDayAs: now) ? store.goals : (store.data.dayGoals[key] ?? store.goals)
        let target = goal.values["cal"]
        let progress = target.map { min(1, max(0, eaten / $0)) } ?? 0
        let future = day > calendar.startOfDay(for: now)
        return Button {
            selectedDate = day; dismiss()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.15), lineWidth: 3)
                    if progress > 0 {
                        Circle().trim(from: 0, to: progress)
                            .stroke(.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    Text("\(calendar.component(.day, from: day))")
                        .font(.system(size: 12, weight: calendar.isDateInToday(day) ? .bold : .regular))
                        .foregroundStyle(.primary)
                }.frame(height: 32).padding(.horizontal, 2)
                Circle().fill(logged ? Color.accentColor : .clear).frame(width: 4, height: 4)
            }.frame(maxWidth: .infinity, minHeight: 44).opacity(future ? 0.3 : 1)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(future)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(logged ? "tracked" : "not tracked"), \(eaten.number) calories\(target.map { " of \($0.number)" } ?? "")")
    }
}
