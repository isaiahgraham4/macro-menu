import SwiftUI

/// Today's water: a bar against the target, chips for the usual amounts, and a sheet for any other amount.
struct WaterRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The day being looked at on Today.
    let date: Date
    @State private var picking = false
    /// The last amount added from the sheet, offered as a chip of its own.
    @AppStorage("waterLastAmount") private var lastAmount = 0.0

    private var total: Double { Water.total(store.data, on: dayKey(date)) }
    private var target: Double { Water.target(store.data) }
    private var glass: Double { Water.glass(store.data) }

    /// A chip per quick amount, then Other. Compact drops "mL" from amounts under a litre, for narrower phones.
    private func amountChips(compact: Bool = false) -> some View {
        HStack(spacing: 8) {
            ForEach(Water.quickAmounts(glass: glass, recent: lastAmount > 0 ? lastAmount : nil), id: \.self) { amount in
                Button(compact && amount < 1000 ? "+\(Int(amount.rounded()))" : "+\(Water.text(amount))") {
                    store.addWater(amount, on: date, undoable: true)
                }
                .fixedSize()
                .accessibilityLabel("Add \(Water.text(amount)) of water")
            }
            Button("Other") { picking = true }.fixedSize().accessibilityLabel("Add another amount of water")
        }
        .font(.roboto(.subheadline, weight: .medium)).monospacedDigit().lineLimit(1)
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).tint(.cyan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(spacing: 14) {
                    Image(systemName: "drop.fill").font(.title2).foregroundStyle(.cyan).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Water").font(.roboto(.headline))
                        Text("\(Water.text(total)) of \(Water.text(target))").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit().rolling(total)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Button { store.addWater(-glass, on: date) } label: {
                        Image(systemName: "minus.circle").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(total <= 0).accessibilityLabel("Take off a glass of water")
                    Button { store.addWater(glass, on: date) } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Add a glass of water, \(Water.text(glass))")
                }.buttonStyle(.borderless)
            }
            ProgressView(value: Water.progress(total: total, target: target)).tint(.cyan).figureChange(total)
                .accessibilityLabel("Water today").accessibilityValue("\(Water.text(total)) of \(Water.text(target))")
            // All on one line when they fit, shorter labels when they don't, and scrolling at large text sizes.
            ViewThatFits(in: .horizontal) {
                amountChips()
                amountChips(compact: true)
                ScrollView(.horizontal, showsIndicators: false) { amountChips(compact: true) }
            }
            if total >= target && target > 0 {
                Text("Target reached.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $picking) {
            WaterAmountSheet(date: date, start: lastAmount > 0 ? lastAmount : glass) { lastAmount = $0 }
        }
    }
}

/// Any amount of water, added or taken off: a slider in 50 mL steps, a field for an exact figure, and common containers.
struct WaterAmountSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let start: Double
    /// Told the amount added, so Today can offer it again as a chip.
    var added: (Double) -> Void
    @State private var amount = 250.0
    @State private var takingOff = false
    @State private var loaded = false
    @FocusState private var typing: Bool

    /// Everyday containers, in millilitres.
    private static let containers: [(String, Double)] = [
        ("Cup", 200), ("Can", 375), ("Bottle", 600), ("Sports bottle", 750), ("1 L bottle", 1000), ("1.5 L bottle", 1500)
    ]

    private var total: Double { Water.total(store.data, on: dayKey(date)) }
    private var target: Double { Water.target(store.data) }
    private var valid: Bool { amount.isFinite && amount >= 1 && amount <= Water.singleLimit && (!takingOff || total > 0) }
    private var after: Double { min(Water.dayLimit, max(0, total + (takingOff ? -amount : amount))) }

    var body: some View {
        NavigationStack {
            LeanrList {
                Section {
                    Picker("Add or take off", selection: $takingOff) {
                        Text("Add").tag(false)
                        Text("Take off").tag(true)
                    }
                    .pickerStyle(.segmented)
                    VStack(spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(amount >= 1000 ? (amount / 1000).formatted(.number.precision(.fractionLength(0...2))) : "\(Int(amount.rounded()))")
                                .font(.display(size: 56)).monospacedDigit().contentTransition(.numericText(value: amount))
                            Text(amount >= 1000 ? "L" : "mL").font(.roboto(.title3, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .animation(.snappy, value: amount)
                        Text("Then \(Water.text(after)) of \(Water.text(target)) \(dayName)")
                            .font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    HStack(spacing: 12) {
                        Button { nudge(-Water.pickerStep) } label: { Image(systemName: "minus") }
                            .accessibilityLabel("50 mL less")
                        Slider(value: sliderValue, in: Water.pickerRange, step: Water.pickerStep)
                            .tint(.cyan).accessibilityLabel("Amount").accessibilityValue(Water.text(amount))
                        Button { nudge(Water.pickerStep) } label: { Image(systemName: "plus") }
                            .accessibilityLabel("50 mL more")
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.circle)
                    HStack {
                        Text("Exact amount")
                        Spacer()
                        TextField("mL", value: $amount, format: .number.precision(.fractionLength(0)))
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 90).focused($typing)
                        Text("mL").foregroundStyle(.secondary)
                    }
                }
                Section("Containers") {
                    ForEach(Self.containers, id: \.1) { name, size in
                        Button { amount = size; typing = false } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                Text(Water.text(size)).foregroundStyle(.secondary).monospacedDigit()
                                if amount == size { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(takingOff ? "Take off water" : "Add water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { typing = false } }
            }
            .safeAreaInset(edge: .bottom) {
                BottomActionBar {
                    Button(takingOff ? "Take off \(Water.text(amount))" : "Add \(Water.text(amount))") { save() }.disabled(!valid)
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            guard !loaded else { return }
            loaded = true
            amount = min(Water.singleLimit, max(Water.pickerStep, start.rounded()))
        }
    }

    /// The slider only reaches 2 L; a typed amount above that keeps the slider at its end without changing the amount.
    private var sliderValue: Binding<Double> {
        Binding(get: { min(Water.pickerRange.upperBound, max(Water.pickerRange.lowerBound, amount)) }, set: { amount = $0; typing = false })
    }

    private func nudge(_ step: Double) {
        typing = false
        let snapped = (amount / Water.pickerStep).rounded() * Water.pickerStep
        amount = min(Water.singleLimit, max(Water.pickerStep, snapped + step))
    }

    private var dayName: String {
        Calendar.current.isDateInToday(date) ? "today" : "on " + date.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func save() {
        guard valid else { store.refuse("Enter an amount from 1 to 5,000 mL"); return }
        let rounded = amount.rounded()
        guard store.addWater(takingOff ? -rounded : rounded, on: date, undoable: true) else { return }
        if !takingOff { added(rounded) }
        dismiss()
    }
}

/// The daily water target and the size of a glass.
struct WaterSettings: View {
    @Environment(AppStore.self) private var store
    @State private var target = Water.defaultTarget
    @State private var glass = Water.defaultGlass
    @State private var loaded = false

    private var valid: Bool { Water.targetRange.contains(target) && Water.glassRange.contains(glass) }
    private var changed: Bool { target != Water.target(store.data) || glass != Water.glass(store.data) }

    var body: some View {
        LeanrList {
            Section {
                NumberField(title: "Daily target (mL)", value: $target, places: 0)
                NumberField(title: "One glass (mL)", value: $glass, places: 0)
                if changed { Button("Save") { if store.setWater(target: target.rounded(), glass: glass.rounded()) { store.notice = "Water settings saved" } }.disabled(!valid) }
            } footer: {
                Text("The plus on Today adds one glass. The chips under the bar add a bottle, a litre or the last other amount you added, and Other picks anything up to 5 L. If Apple Health is connected, each day's total is saved to Health as water.")
            }
            if !valid { Section { Text("Use a target from 250 to 10,000 mL and a glass from 50 to 2,000 mL.").foregroundStyle(.secondary) } }
        }
        .navigationTitle("Water")
        .onAppear {
            guard !loaded else { return }
            loaded = true; target = Water.target(store.data); glass = Water.glass(store.data)
        }
    }
}
