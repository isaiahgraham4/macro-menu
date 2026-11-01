// Draws every Takeawise app icon: the lowercase t with the leaf growing from its foot.
// Run from ios/: swift Scripts/app-icon.swift
// Pass a path to write a single preview of the mark there instead: swift Scripts/app-icon.swift /tmp/mark.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// The stem, foot, leaf and stalk as one outline on a 1024 grid, y down. The left arm is added separately.
private func body() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(313, 298))
    p.addArc(center: P(377.5, 298), radius: 64.5, startAngle: .pi, endAngle: 0, clockwise: false)
    p.addLine(to: P(442, 610))
    p.addCurve(to: P(456, 676), control1: P(442, 640), control2: P(446, 676))
    p.addCurve(to: P(464, 660), control1: P(461, 676), control2: P(463, 670))
    p.addCurve(to: P(760, 318), control1: P(484, 480), control2: P(560, 345))
    p.addCurve(to: P(575, 557), control1: P(745, 440), control2: P(690, 525))
    p.addCurve(to: P(495, 660), control1: P(530, 568), control2: P(497, 590))
    p.addCurve(to: P(570, 738), control1: P(495, 712), control2: P(520, 735))
    p.addCurve(to: P(473, 767), control1: P(545, 755), control2: P(510, 767))
    p.addCurve(to: P(313, 610), control1: P(380, 767), control2: P(313, 705))
    p.closeSubpath()
    return p
}

/// The vein cut out of the leaf.
private func vein() -> CGPath {
    let p = CGMutablePath()
    p.move(to: P(623, 427))
    p.addCurve(to: P(523, 548), control1: P(585, 462), control2: P(553, 500))
    p.addCurve(to: P(509, 544), control1: P(517, 556), control2: P(506, 553))
    p.addCurve(to: P(623, 427), control1: P(528, 490), control2: P(565, 445))
    p.closeSubpath()
    return p
}

private let arm = CGPath(roundedRect: CGRect(x: 198, y: 388, width: 200, height: 104), cornerWidth: 52, cornerHeight: 52, transform: nil)

/// Moves the mark, whose outline runs 198...760 by 233...767, to the middle of the icon and a little larger.
private let placement = CGAffineTransform(translationX: 512, y: 512).scaledBy(x: 1.12, y: 1.12).translatedBy(x: -479, y: -500)

private func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

private func icon(background: UInt32, mark: UInt32, size: Int = 1024) -> CGImage {
    // No alpha channel: App Store Connect refuses icons that have one.
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(background))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: CGFloat(size) / 1024, y: -CGFloat(size) / 1024)
    context.concatenate(placement)
    context.setFillColor(color(mark))
    context.addPath(body())
    context.addPath(arm)
    context.fillPath(using: .winding)
    context.setFillColor(color(background))
    context.addPath(vein())
    context.fillPath()
    return context.makeImage()!
}

private func write(_ image: CGImage, to path: String) {
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(path)") }
}

if CommandLine.arguments.count > 1 {
    write(icon(background: 0xFFFFFF, mark: 0x0B0B0B), to: CommandLine.arguments[1])
    exit(0)
}

private let themes: [(file: String, background: UInt32, mark: UInt32, folders: [String])] = [
    ("Light", 0xFFFFFF, 0x0B0B0B, ["AppIcon.appiconset", "IconPreviewDefault.imageset"]),
    ("Black", 0x000000, 0xFCF2E3, ["AppIcon.appiconset", "IconPreviewDefault.imageset"]),
    ("Cream", 0xF5EEDF, 0x5C663C, ["AppIconCream.appiconset", "IconPreviewCream.imageset"]),
    ("Forest", 0x293929, 0xFBF6ED, ["AppIconForest.appiconset", "IconPreviewForest.imageset"]),
    ("Midnight", 0x142334, 0xDCEDF8, ["AppIconMidnight.appiconset", "IconPreviewMidnight.imageset"]),
    ("Plum", 0x4E283B, 0xFDDFDA, ["AppIconPlum.appiconset", "IconPreviewPlum.imageset"]),
    ("Sage", 0xADBA9F, 0x2A392A, ["AppIconSage.appiconset", "IconPreviewSage.imageset"]),
    ("Terracotta", 0xA44C31, 0xFBF6ED, ["AppIconTerracotta.appiconset", "IconPreviewTerracotta.imageset"]),
]

for theme in themes {
    let image = icon(background: theme.background, mark: theme.mark)
    // The file names stay Leanr: the asset catalog's Contents.json points at them.
    for folder in theme.folders { write(image, to: "MacroMenu/Assets.xcassets/\(folder)/Leanr-\(theme.file)-1024.png") }
    if theme.file == "Black" { write(image, to: "LeanrWatch/Assets.xcassets/AppIcon.appiconset/Leanr-Black-1024.png") }
}
