import SwiftUI

/// Today's water: a bar against the target, a tap to add a glass, and a menu for a bottle or any other amount.
struct WaterRow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The day being looked at on Today.
    let date: Date
    @State private var custom = false
    @State private var customText = ""

    private var total: Double { Water.total(store.data, on: dayKey(date)) }
    private var target: Double { Water.target(store.data) }
    private var glass: Double { Water.glass(store.data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(spacing: 14) {
                    Image(systemName: "drop.fill").font(.title2).foregroundStyle(.cyan).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Water").font(.roboto(.headline))
                        Text("\(Water.text(total)) of \(Water.text(target))").font(.roboto(.caption)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Button { store.addWater(-glass, on: date) } label: {
                        Image(systemName: "minus.circle").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .disabled(total <= 0).accessibilityLabel("Take off a glass of water")
                    Menu {
                        ForEach(Water.bottleSizes, id: \.self) { size in
                            Button("Add \(Water.text(size))") { store.addWater(size, on: date) }
                        }
                        Button("Add another amount…") { customText = ""; custom = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44).contentShape(Rectangle())
                    } primaryAction: {
                        store.addWater(glass, on: date)
                    }
                    .accessibilityLabel("Add a glass of water, \(Water.text(glass))")
                    .accessibilityHint("Hold for other amounts.")
                }.buttonStyle(.borderless)
            }
            ProgressView(value: Water.progress(total: total, target: target)).tint(.cyan)
                .accessibilityLabel("Water today").accessibilityValue("\(Water.text(total)) of \(Water.text(target))")
            if total >= target && target > 0 {
                Text("Target reached.").font(.roboto(.caption)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .alert("Add water", isPresented: $custom) {
            TextField("Millilitres", text: $customText).keyboardType(.numberPad)
            Button("Add") {
                if let amount = Double(customText.trimmingCharacters(in: .whitespaces)), amount > 0, amount <= 5000 {
                    store.addWater(amount, on: date)
                } else {
                    store.notice = "Enter an amount from 1 to 5,000 mL"
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("How many millilitres?") }
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
                Text("A tap on Today adds one glass. Hold the plus for a bottle or any other amount. If Apple Health is connected, each day's total is saved to Health as water.")
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
