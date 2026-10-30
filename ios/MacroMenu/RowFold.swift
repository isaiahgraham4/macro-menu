import CoreGraphics

/// Where a fold crosses a row on a partly open iPhone Duo, in the row's coordinates.
struct RowFold: Equatable, Sendable {
    let left: CGFloat
    let right: CGFloat
    let rowWidth: CGFloat

    /// Enough for the date beside its arrow, or for two log buttons.
    private static let minimumSide: CGFloat = 180
    /// Half the widest middle label in a segmented control, plus a margin.
    private static let middleLabelClearance: CGFloat = 48

    /// Nil when the fold misses the row or leaves too little room on either side to be worth working around.
    init?(left: CGFloat, right: CGFloat, rowWidth: CGFloat) {
        guard left >= Self.minimumSide, rowWidth - right >= Self.minimumSide else { return nil }
        self.left = left
        self.right = right
        self.rowWidth = rowWidth
    }

    /// The width to lay out in, falling back to the measured row when the proposal is missing or unbounded.
    func width(proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite else { return rowWidth }
        return max(proposed, right)
    }

    /// Equal columns on each side of the fold, with the extra one on the left when the count is odd.
    func columns(width: CGFloat, count: Int, spacing: CGFloat) -> [(x: CGFloat, width: CGFloat)] {
        func side(from start: CGFloat, to end: CGFloat, count: Int) -> [(x: CGFloat, width: CGFloat)] {
            guard count > 0 else { return [] }
            let cell = max((end - start - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
            return (0..<count).map { (start + CGFloat($0) * (cell + spacing), cell) }
        }
        let onLeft = (count + 1) / 2
        return side(from: 0, to: left, count: onLeft) + side(from: right, to: self.width(proposed: width), count: count - onLeft)
    }

    /// How to narrow a three-part segmented control so its middle label misses the fold: the width, and whether the
    /// control stays against the row's leading edge. Nil when the label is already clear.
    var middleLabelFit: (width: CGFloat, leading: Bool)? {
        let middle = rowWidth / 2, clearance = Self.middleLabelClearance
        guard middle + clearance > left, middle - clearance < right else { return nil }
        return (left + right) / 2 >= middle ? (2 * (left - clearance), true) : (2 * (rowWidth - right - clearance), false)
    }
}
