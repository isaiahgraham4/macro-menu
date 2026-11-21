import SwiftUI

/// Where the photo and the macros card sit on a photo story, in the story's own 360 × 640 points.
struct PhotoLayout: Equatable {
    /// 1 fills the story; more zooms in.
    var zoom: CGFloat = 1
    /// How far the photo is moved from centre.
    var pan: CGSize = .zero
    var cardCentre: CGPoint
    var cardWidth: CGFloat

    /// The same 360 × 640 as `MealShareCard.size`, spelled out so this plain value type needs no main actor.
    static let story = CGSize(width: 360, height: 640)

    /// The Clear card's words straight across the photo; any other design as a half-width card in the bottom corner.
    static func standard(for design: ShareDesign) -> PhotoLayout {
        let s = story
        if design.isTransparent { return PhotoLayout(cardCentre: CGPoint(x: s.width / 2, y: s.height / 2), cardWidth: s.width) }
        let w = s.width * 0.5, h = w * s.height / s.width
        return PhotoLayout(cardCentre: CGPoint(x: 18 + w / 2, y: s.height - 18 - h / 2), cardWidth: w)
    }

    /// How small and big the card may go: the Clear card's words stay readable, a solid card never hides the whole photo.
    static func widthRange(for design: ShareDesign) -> ClosedRange<CGFloat> {
        design.isTransparent ? story.width * 0.45 ... story.width : story.width * 0.25 ... story.width * 0.9
    }

    static let zoomRange: ClosedRange<CGFloat> = 1 ... 4

    var cardHeight: CGFloat { cardWidth * Self.story.height / Self.story.width }

    /// Keeps the card's centre on the story and the photo covering it, with no gaps at the edges.
    func clamped(photo: CGSize, design: ShareDesign) -> PhotoLayout {
        var l = self
        let s = Self.story
        l.zoom = min(max(zoom, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let range = Self.widthRange(for: design)
        l.cardWidth = min(max(cardWidth, range.lowerBound), range.upperBound)
        l.cardCentre = CGPoint(x: min(max(cardCentre.x, 0), s.width), y: min(max(cardCentre.y, 0), s.height))
        if photo.width > 0, photo.height > 0 {
            let fill = max(s.width / photo.width, s.height / photo.height) * l.zoom
            let spareX = max(0, (photo.width * fill - s.width) / 2), spareY = max(0, (photo.height * fill - s.height) / 2)
            l.pan = CGSize(width: min(max(pan.width, -spareX), spareX), height: min(max(pan.height, -spareY), spareY))
        }
        return l
    }
}

/// Full-screen editing of a photo story: drag and pinch the macros card to put it where you want it, or drag and pinch
/// the photo to frame the food. Done hands back the layout and the photo (turned, if it was rotated).
struct PhotoStoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAccent.storageKey) private var accentRaw = AppAccent.standard.rawValue
    var card: UIImage
    var design: ShareDesign
    var onDone: (PhotoLayout, UIImage) -> Void

    @State private var photo: UIImage
    @State private var layout: PhotoLayout
    @State private var target: Target = .macros
    /// The layout when the current drag or pinch began, so each gesture moves from where things were.
    @State private var dragStart: PhotoLayout?
    @State private var pinchStart: PhotoLayout?
    @State private var snap = Snap()

    enum Target: String, CaseIterable { case macros = "Macros", photo = "Photo" }

    /// Which centre lines the card is sitting on, shown as guides while dragging.
    struct Snap: Equatable { var x = false; var y = false }

    init(photo: UIImage, card: UIImage, design: ShareDesign, layout: PhotoLayout, onDone: @escaping (PhotoLayout, UIImage) -> Void) {
        self.card = card; self.design = design; self.onDone = onDone
        _photo = State(initialValue: photo); _layout = State(initialValue: layout)
    }

    private var accent: Color { AppAccent.resolvedColor(accentRaw) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                canvas
                controls
            }
            .padding()
            .navigationTitle("Edit photo").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(layout, photo); dismiss() }.fontWeight(.semibold)
                }
            }
            .sensoryFeedback(.selection, trigger: snap) { old, new in (new.x && !old.x) || (new.y && !old.y) }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { geo in
            let s = PhotoLayout.story
            let k = min(geo.size.width / s.width, geo.size.height / s.height)
            PhotoStory(photo: photo, card: card, design: design, layout: layout)
                .scaleEffect(k, anchor: .topLeading)
                .frame(width: s.width * k, height: s.height * k, alignment: .topLeading)
                .overlay { guides(k: k) }
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(Rectangle())
                .gesture(drag(k: k).simultaneously(with: pinch))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement()
                .accessibilityLabel(target == .macros ? "Macros card on your photo" : "Your photo")
                .accessibilityHint(target == .macros ? "Swipe up or down to resize the card. Use the actions to move it." : "Swipe up or down to zoom.")
                .accessibilityAdjustableAction { direction in
                    let step: CGFloat = direction == .increment ? 1.1 : 1 / 1.1
                    update { target == .macros ? ($0.cardWidth *= step) : ($0.zoom *= step) }
                }
                .accessibilityAction(named: "Move up") { nudge(0, -40) }
                .accessibilityAction(named: "Move down") { nudge(0, 40) }
                .accessibilityAction(named: "Move left") { nudge(-40, 0) }
                .accessibilityAction(named: "Move right") { nudge(40, 0) }
        }
    }

    /// Thin centre lines while the card is lined up with the middle of the story.
    private func guides(k: CGFloat) -> some View {
        ZStack {
            if snap.x { Rectangle().fill(accent).frame(width: 1.5).frame(maxHeight: .infinity) }
            if snap.y { Rectangle().fill(accent).frame(height: 1.5).frame(maxWidth: .infinity) }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: snap)
    }

    private func drag(k: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let base = dragStart ?? layout
                if dragStart == nil { dragStart = layout }
                let dx = value.translation.width / k, dy = value.translation.height / k
                var next = layout
                switch target {
                case .macros:
                    var centre = CGPoint(x: base.cardCentre.x + dx, y: base.cardCentre.y + dy)
                    let mid = CGPoint(x: PhotoLayout.story.width / 2, y: PhotoLayout.story.height / 2)
                    let sx = abs(centre.x - mid.x) < 6, sy = abs(centre.y - mid.y) < 6
                    if sx { centre.x = mid.x }
                    if sy { centre.y = mid.y }
                    snap = Snap(x: sx, y: sy)
                    next.cardCentre = centre
                case .photo:
                    next.pan = CGSize(width: base.pan.width + dx, height: base.pan.height + dy)
                }
                layout = next.clamped(photo: photo.size, design: design)
            }
            .onEnded { _ in dragStart = nil; snap = Snap() }
    }

    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = pinchStart ?? layout
                if pinchStart == nil { pinchStart = layout }
                var next = layout
                switch target {
                case .macros: next.cardWidth = base.cardWidth * value.magnification
                case .photo: next.zoom = base.zoom * value.magnification
                }
                layout = next.clamped(photo: photo.size, design: design)
            }
            .onEnded { _ in pinchStart = nil }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 14) {
            Picker("Move", selection: $target) {
                ForEach(Target.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Image(systemName: target == .macros ? "textformat.size.smaller" : "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: sizeBinding, in: sizeRange).tint(accent)
                    .accessibilityLabel(target == .macros ? "Card size" : "Photo zoom")
                Image(systemName: target == .macros ? "textformat.size.larger" : "plus.magnifyingglass").foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button(action: rotate) { Label("Rotate", systemImage: "rotate.right").frame(maxWidth: .infinity) }
                Button { withAnimation(.snappy) { layout = .standard(for: design) } } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .disabled(layout == .standard(for: design))
            }
            .buttonStyle(.bordered).controlSize(.regular).tint(accent)

            Text(target == .macros ? "Drag the card to move it. Pinch to resize." : "Drag the photo to frame your food. Pinch to zoom.")
                .font(.roboto(.caption)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .font(.roboto(.subheadline))
    }

    private var sizeRange: ClosedRange<CGFloat> {
        target == .macros ? PhotoLayout.widthRange(for: design) : PhotoLayout.zoomRange
    }

    private var sizeBinding: Binding<CGFloat> {
        Binding {
            target == .macros ? layout.cardWidth : layout.zoom
        } set: { value in
            update { target == .macros ? ($0.cardWidth = value) : ($0.zoom = value) }
        }
    }

    private func update(_ change: (inout PhotoLayout) -> Void) {
        var next = layout
        change(&next)
        layout = next.clamped(photo: photo.size, design: design)
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        update {
            switch target {
            case .macros: $0.cardCentre.x += dx; $0.cardCentre.y += dy
            case .photo: $0.pan.width += dx; $0.pan.height += dy
            }
        }
    }

    /// Turns the photo a quarter clockwise and frames it fresh, since the old framing no longer fits it.
    private func rotate() {
        photo = photo.rotatedClockwise
        update { $0.zoom = 1; $0.pan = .zero }
    }
}

extension UIImage {
    /// The picture turned a quarter clockwise, drawn upright so its orientation is plain `.up`.
    var rotatedClockwise: UIImage {
        let format = UIGraphicsImageRendererFormat.default(); format.scale = scale
        let turned = CGSize(width: size.height, height: size.width)
        return UIGraphicsImageRenderer(size: turned, format: format).image { ctx in
            ctx.cgContext.translateBy(x: turned.width / 2, y: turned.height / 2)
            ctx.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
