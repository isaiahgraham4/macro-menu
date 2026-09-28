import Foundation
import Observation

enum FoodValidationError: LocalizedError {
    case invalidFood
    var errorDescription: String? { "Enter a food name and non-negative nutrition values." }
}

struct SavedFood: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var serving = "1 serving"
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        [calories, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 }
    }
}

struct FoodBackup: Codable {
    var version = 1
    var foods: [SavedFood] = []

    static func decode(_ data: Data) throws -> FoodBackup {
        let backup = try JSONDecoder().decode(Self.self, from: data)
        guard backup.version == 1,
              backup.foods.allSatisfy(\.isValid),
              Set(backup.foods.map(\.id)).count == backup.foods.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return backup
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

@MainActor @Observable
final class FoodStore {
    private(set) var foods: [SavedFood] = []
    private(set) var loadError: String?
    private let url: URL

    init(url: URL = URL.applicationSupportDirectory.appending(path: "MacroMenu/foods.json")) {
        self.url = url
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                foods = try FoodBackup.decode(Data(contentsOf: url)).foods
            }
        } catch {
            loadError = "Your saved foods could not be opened. Your original file has been preserved. \(error.localizedDescription)"
        }
    }

    private func persist(_ updated: [SavedFood]) throws {
        guard loadError == nil else { throw CocoaError(.fileReadCorruptFile) }
        let data = try FoodBackup(foods: updated).encoded()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        foods = updated
    }

    func save(_ food: SavedFood) throws {
        guard food.isValid else { throw FoodValidationError.invalidFood }
        var updated = foods
        if let index = updated.firstIndex(where: { $0.id == food.id }) {
            updated[index] = food
        } else {
            updated.append(food)
        }
        try persist(updated)
    }

    func delete(at offsets: IndexSet) throws {
        try persist(foods.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
    }

    // Keep existing foods; matching IDs are updated from the selected backup.
    func merge(_ backup: FoodBackup) throws {
        let validated = try FoodBackup.decode(backup.encoded())
        var updated = foods
        for food in validated.foods {
            if let index = updated.firstIndex(where: { $0.id == food.id }) {
                updated[index] = food
            } else {
                updated.append(food)
            }
        }
        try persist(updated)
    }
}
