import Foundation
import CoreGraphics
import Vision
import CoreImage

/// Names the foods in a photo with Apple's built-in image classifier. It runs on the device, needs no Apple Intelligence and
/// no download, and sends nothing anywhere. It can't count or read brands, so every row is checked by the user.
enum MealVision {
    /// The whole photo, then each thing on the plate on its own: Vision cuts out each separate item, so a burger, chips and a
    /// drink are each read by themselves. When it can't tell the items apart, the four quarters of the photo are read instead.
    static func scoredFoods(in image: CGImage) async throws -> [(food: SeenFood, score: Double)] {
        try await Task.detached(priority: .userInitiated) {
            let whole = try readings(in: image)
            var tiles: [[VisionFoodLabels.Reading]] = []
            let parts = cutOuts(in: image)
            if !parts.isEmpty {
                for part in parts { tiles.append(try readings(in: part)) }
            } else if min(image.width, image.height) >= 200 {
                let width = image.width, height = image.height
                for (column, row) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                    let part = CGRect(x: column * width / 2, y: row * height / 2, width: width / 2, height: height / 2)
                    if let crop = image.cropping(to: part) { tiles.append(try readings(in: crop)) }
                }
            }
            return VisionFoodLabels.scored(whole: whole, tiles: tiles)
        }.value
    }

    /// Each separate thing in the photo, cut out on its own from Vision's foreground masks, background removed.
    /// Empty when Vision finds fewer than two (a single plate it can't split, or the simulator, which can't run it).
    static func cutOuts(in image: CGImage, limit: Int = 6) -> [CGImage] {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let result = request.results?.first, result.allInstances.count >= 2 else { return [] }
        let context = CIContext()
        var crops: [CGImage] = []
        for instance in result.allInstances.prefix(limit) {
            guard let buffer = try? result.generateMaskedImage(ofInstances: IndexSet(integer: instance), from: handler, croppedToInstancesExtent: true) else { continue }
            let cut = CIImage(cvPixelBuffer: buffer)
            // Crumbs and specks are too small to read.
            guard cut.extent.width >= 64, cut.extent.height >= 64, let crop = context.createCGImage(cut, from: cut.extent) else { continue }
            crops.append(crop)
        }
        return crops.count >= 2 ? crops : []
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
