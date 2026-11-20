import Foundation
import Vision
import AppKit
// Usage: ocr <image>...  -> one JSON line per image: {"file":..., "lines":[{"t":text,"x":..,"y":..,"w":..,"h":..}]}, y from the top, 0...1
for path in CommandLine.arguments.dropFirst() {
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    let lines = (req.results ?? []).compactMap { o -> [String: Any]? in
        guard let c = o.topCandidates(1).first else { return nil }
        let b = o.boundingBox
        return ["t": c.string, "x": b.minX, "y": 1 - b.maxY, "w": b.width, "h": b.height]
    }
    let data = try! JSONSerialization.data(withJSONObject: ["file": (path as NSString).lastPathComponent, "lines": lines])
    print(String(data: data, encoding: .utf8)!)
}
