import SwiftUI

/// Places cards in columns, each card going into the currently shortest column (masonry).
/// One column on iPhone; two on iPad and other regular-width layouts, without the gaps a grid
/// leaves when neighbouring cards have different heights.
struct CardColumns: Layout {
    var columns: Int
    var spacing: CGFloat = 16

    private func columnWidth(for width: CGFloat) -> CGFloat {
        let n = CGFloat(max(columns, 1))
        return max(0, (width - spacing * (n - 1)) / n)
    }

    /// Column index and y offset for each subview, plus the total height.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (positions: [(Int, CGFloat)], height: CGFloat) {
        let w = columnWidth(for: width)
        var heights = Array(repeating: CGFloat(0), count: max(columns, 1))
        var positions: [(Int, CGFloat)] = []
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: w, height: nil))
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let y = heights[column] == 0 ? 0 : heights[column] + spacing
            positions.append((column, y))
            heights[column] = y + size.height
        }
        return (positions, heights.max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = columnWidth(for: bounds.width)
        let (positions, _) = arrange(subviews, width: bounds.width)
        for (subview, (column, y)) in zip(subviews, positions) {
            let x = bounds.minX + CGFloat(column) * (w + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY + y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: nil))
        }
    }
}
