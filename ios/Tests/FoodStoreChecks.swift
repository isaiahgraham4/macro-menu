import Foundation

@main struct FoodStoreChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "foods.json")
        let store = FoodStore(url: url)
        var food = SavedFood(name: "Test food", calories: 120, protein: 10)
        try store.save(food)
        assert(FoodStore(url: url).foods == [food], "Saved food must survive reload")
        let backup = try FoodBackup.decode(FoodBackup(foods: store.foods).encoded())
        let other = FoodStore(url: root.appending(path: "other.json"))
        try other.merge(backup)
        assert(other.foods == [food], "Export/import must round trip")
        food.name = "Updated"
        try other.merge(FoodBackup(foods: [food]))
        assert(other.foods == [food], "Matching IDs must update without duplication")
        let extra = SavedFood(name: "Keep me")
        try other.save(extra)
        try other.merge(backup)
        assert(other.foods.count == 2 && other.foods.contains(extra))
        do {
            try other.merge(FoodBackup(version: 99, foods: []))
            assertionFailure("Unsupported backups must fail")
        } catch {}
        do {
            try other.merge(FoodBackup(foods: [food, food]))
            assertionFailure("Duplicate IDs must fail")
        } catch {}
        try other.delete(at: IndexSet(integer: 0))
        assert(FoodStore(url: root.appending(path: "other.json")).foods == [extra])
        let corrupt = Data("invalid".utf8)
        try corrupt.write(to: url)
        let broken = FoodStore(url: url)
        assert(broken.loadError != nil)
        do {
            try broken.save(food)
            assertionFailure("Unreadable saves must never be overwritten")
        } catch {}
        let preserved = try Data(contentsOf: url)
        assert(preserved == corrupt)
        print("Food storage checks passed")
    }
}
