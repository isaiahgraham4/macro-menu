import SwiftUI

/// The looks a share image can take. The last one picked is used next time.
enum ShareDesign: String, CaseIterable, Identifiable {
    case night, clear, paper, colour, docket

    static let storageKey = "shareDesign"
    /// A milestone card has no food list, so the receipt-style docket is for meals only.
    static let forMoments: [ShareDesign] = [.night, .clear, .paper, .colour]

    var id: Self { self }
    var name: String {
        switch self {
        case .night: "Night"
        case .clear: "Clear"
        case .paper: "Paper"
        case .colour: "Colour"
        case .docket: "Docket"
        }
    }

    /// No background at all: white type with a soft shadow, to lay over your own photo in a story.
    var isTransparent: Bool { self == .clear }

    /// What to say under the buttons when the usual hint doesn't fit the design.
    var hint: String? {
        isTransparent ? "It's see-through. Copy it, then paste it onto your own photo in a story." : nil
    }

    func palette(accent: Color) -> SharePalette {
        switch self {
        case .night:
            return SharePalette(background: Color(red: 0.07, green: 0.07, blue: 0.08), ink: .white, dim: .white.opacity(0.6), faint: .white.opacity(0.45),
                         brand: accent, scheme: .dark)
        case .clear:
            // Brighter secondary text than Night, since it sits on whatever photo it's pasted over.
            return SharePalette(background: nil, ink: .white, dim: .white.opacity(0.85), faint: .white.opacity(0.75), brand: .white, scheme: .dark, shadow: true)
        case .paper:
            let ink = Color(red: 0.11, green: 0.12, blue: 0.11)
            return SharePalette(background: Color(red: 0xF6 / 255, green: 0xF2 / 255, blue: 0xEA / 255), ink: ink, dim: ink.opacity(0.62),
                                faint: ink.opacity(0.5), brand: accent, scheme: .light, dots: true)
        case .colour:
            // The light-mode shade of the accent, which is dark enough for white text on it.
            return SharePalette(background: accent, ink: .white, dim: .white.opacity(0.78), faint: .white.opacity(0.62), brand: .white, scheme: .light,
                         plainBars: true)
        case .docket:
            let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
            return SharePalette(background: Color(red: 0.985, green: 0.98, blue: 0.965), ink: ink, dim: ink.opacity(0.6), faint: ink.opacity(0.45),
                                brand: ink, scheme: .light)
        }
    }
}

/// The colours one design draws with.
struct SharePalette {
    /// Nil for a see-through card.
    var background: Color?
    var ink: Color
    var dim: Color
    var faint: Color
    /// The LEANRRR mark and other accents.
    var brand: Color
    /// The appearance the card is drawn in, so the accent and macro colours pick the matching shade.
    var scheme: ColorScheme
    /// A soft shadow under the type, so it reads over a photo.
    var shadow = false
    /// The app's order-pad dot grid behind the card.
    var dots = false
    /// Macro bars in the ink colour: on a coloured card the macro colours would clash with it.
    var plainBars = false
}

/// Fits a card to the 9:16 story size and paints its design around it.
struct ShareSurface: ViewModifier {
    var palette: SharePalette

    func body(content: Content) -> some View {
        content
            .frame(width: MealShareCard.size.width, height: MealShareCard.size.height, alignment: .topLeading)
            .shadow(color: .black.opacity(palette.shadow ? 0.55 : 0), radius: palette.shadow ? 6 : 0, y: palette.shadow ? 1 : 0)
            .background {
                if let background = palette.background {
                    ZStack {
                        background
                        if palette.dots { OrderPadDots(ink: Color(red: 0.40, green: 0.31, blue: 0.20).opacity(0.16)) }
                    }
                }
            }
            .foregroundStyle(palette.ink)
            .environment(\.colorScheme, palette.scheme)
            // A picture, not a screen: the same size whatever text size the sharer uses.
            .dynamicTypeSize(.large)
    }
}

/// The order-pad dot grid from the app's background, for the Paper card.
struct OrderPadDots: View {
    var ink: Color
    var step = 20.0

    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: step / 2, through: size.width, by: step) {
                for y in stride(from: step / 2, through: size.height, by: step) {
                    dots.addEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
                }
            }
            context.fill(dots, with: .color(ink))
        }
    }
}

/// Grey squares behind a see-through card in the preview, so you can see it's clear. Not part of the image.
struct Checkerboard: View {
    var square = 12.0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.32)))
            var dark = Path()
            for (row, y) in stride(from: 0.0, to: size.height, by: square).enumerated() {
                for (column, x) in stride(from: 0.0, to: size.width, by: square).enumerated() where (row + column).isMultiple(of: 2) {
                    dark.addRect(CGRect(x: x, y: y, width: square, height: square))
                }
            }
            context.fill(dark, with: .color(Color(white: 0.24)))
        }
        .accessibilityHidden(true)
    }
}

/// A dashed line across a docket, like the tear lines on a receipt.
struct DashedRule: View {
    var colour: Color

    var body: some View {
        RuleLine().stroke(colour, style: StrokeStyle(lineWidth: 1, dash: [4, 3])).frame(height: 1)
    }

    private struct RuleLine: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

/// The row of designs under a share image's preview.
struct ShareDesignPicker: View {
    var designs: [ShareDesign]
    @Binding var selection: String
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue

    var body: some View {
        let accent = AppAccent.resolvedColor(accentRaw)
        HStack(spacing: 6) {
            ForEach(designs) { design in
                let selected = design.rawValue == selection
                Button { selection = design.rawValue } label: {
                    VStack(spacing: 6) {
                        swatch(design, accent: accent)
                            .frame(width: 40, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(selected ? accent : Color.primary.opacity(0.15), lineWidth: selected ? 2.5 : 1)
                            }
                        Text(design.name).font(.roboto(.caption, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(design.name) design")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    /// A tiny card in the design's colours: its paper, and "Aa" in its type.
    private func swatch(_ design: ShareDesign, accent: Color) -> some View {
        let palette = design.palette(accent: accent)
        return ZStack {
            if let background = palette.background { background } else { Checkerboard(square: 5) }
            if palette.dots { OrderPadDots(ink: Color(red: 0.40, green: 0.31, blue: 0.20).opacity(0.25), step: 8) }
            Text("Aa")
                .font(design == .docket ? .system(size: 15, weight: .bold, design: .monospaced) : .custom(AppFonts.display, size: 20))
                .foregroundStyle(palette.ink)
                .shadow(color: .black.opacity(palette.shadow ? 0.6 : 0), radius: 2)
        }
        .environment(\.colorScheme, palette.scheme)
    }
}
