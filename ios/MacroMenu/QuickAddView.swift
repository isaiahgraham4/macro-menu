import SwiftUI

/// Logs calories and macros on their own, for something eaten when you don't know what or how much it was.
/// Nothing is saved to My foods: it's one entry in the day's log.
struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var mealTime: MealTime
    @State private var calories: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var note = ""
    @State private var failed = false
    @FocusState private var focused: Bool
    /// Logs the portion to the meal time chosen here. Returns false if it couldn't be saved.
    let save: (Portion, MealTime) -> Bool

    init(mealTime: MealTime, save: @escaping (Portion, MealTime) -> Bool) {
        _mealTime = State(initialValue: mealTime)
        self.save = save
    }

    /// Calories worked out from the macros (4 per gram of protein and carbs, 9 per gram of fat), when none were typed.
    private var estimated: Double? {
        guard calories == nil, [protein, carbs, fat].contains(where: { ($0 ?? 0) > 0 }) else { return nil }
        return (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9
    }

    private var food: Food? {
        guard let energy = calories ?? estimated, energy > 0 else { return nil }
        let cal = energy.tenth
        let name = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = Food(name: name.isEmpty ? "Quick add" : name, kj: cal * 4.184, cal: cal, p: (protein ?? 0).tenth,
                         c: carbs?.tenth, f: fat?.tenth, serve: "Quick add")
        return value.isValid ? value : nil
    }

    var body: some View {
        LeanrForm {
            Section {
                Picker("Log to", selection: $mealTime) {
                    ForEach(MealTime.allCases) { Text($0.title).tag($0) }
                }
            }
            Section {
                field("Calories", unit: "Cal", value: $calories, prompt: estimated.map { "≈ \($0.number)" } ?? "0")
                field("Protein", unit: "g", value: $protein)
                field("Carbs", unit: "g", value: $carbs)
                field("Fat", unit: "g", value: $fat)
            } footer: {
                Text(estimated == nil ? "Leave blank what you don't know. No calories? They're worked out from the macros." : "Calories are worked out from your macros.")
            }
            Section {
                TextField("What was it? (optional)", text: $note)
            }
        }
        .navigationTitle("Quick add").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") {
                    guard let food else { return }
                    if save(Portion(food: food), mealTime) { dismiss() } else { failed = true }
                }.disabled(food == nil)
            }
            ToolbarItem(placement: .keyboard) { Button("Done") { focused = false } }
        }
        .alert("Couldn’t log this", isPresented: $failed) { Button("OK", role: .cancel) {} } message: {
            Text("Your data was not changed. Check available storage and any data recovery message in the app.")
        }
    }

    /// A number box that starts empty, so a blank reads as "don't know" rather than zero.
    private func field(_ title: String, unit: String, value: Binding<Double?>, prompt: String = "–") -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(prompt, value: value, format: decimalFormat())
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 100)
                .focused($focused).accessibilityLabel("\(title) in \(unit == "g" ? "grams" : "calories")")
            Text(unit).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
        }
    }
}
