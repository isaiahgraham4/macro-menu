import Foundation
import CoreGraphics
import Vision

/// Names the foods in a photo with Apple's built-in image classifier. It runs on the device, needs no Apple Intelligence and
/// no download, and sends nothing anywhere. It can't count or read brands, so every row is checked by the user.
enum MealVision {
    /// The whole photo, then each quarter of it: a plate with a burger, chips and a drink reads better a part at a time.
    static func scoredFoods(in image: CGImage) async throws -> [(food: SeenFood, score: Double)] {
        try await Task.detached(priority: .userInitiated) {
            let whole = try readings(in: image)
            var tiles: [[VisionFoodLabels.Reading]] = []
            let width = image.width, height = image.height
            if min(width, height) >= 200 {
                for (column, row) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let part = CGRect(x: column * width / 2, y: row * height / 2, width: width / 2, height: height / 2)
                    if let crop = image.cropping(to: part) { tiles.append(try readings(in: crop)) }
                }
            }
            return VisionFoodLabels.scored(whole: whole, tiles: tiles)
        }.value
    }

    private static func readings(in image: CGImage) throws -> [VisionFoodLabels.Reading] {
        let request = VNClassifyImageRequest()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).filter { $0.confidence >= 0.04 }
            .map { VisionFoodLabels.Reading(identifier: $0.identifier, confidence: Double($0.confidence)) }
    }
}

extension MealVision {
    static func foods(in image: CGImage) async throws -> [SeenFood] { try await scoredFoods(in: image).map(\.food) }
}
