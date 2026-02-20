import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard let lastRow = rows.last else { return .zero }

        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: lastRow.maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)

        for row in rows {
            for element in row.elements {
                element.subview.place(
                    at: CGPoint(x: bounds.minX + element.x, y: bounds.minY + element.y),
                    proposal: .unspecified
                )
            }
        }
    }

    private struct Row {
        var elements: [Element] = []
        var width: CGFloat = 0
        var maxY: CGFloat = 0
    }

    private struct Element {
        var subview: LayoutSubview
        var x: CGFloat
        var y: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        let maxWidth = proposal.width ?? .infinity

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var currentRowElements: [Element] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, !currentRowElements.isEmpty {
                rows.append(
                    Row(
                        elements: currentRowElements,
                        width: currentX - spacing,
                        maxY: currentY + rowHeight
                    )
                )

                currentY += rowHeight + spacing
                currentX = 0
                rowHeight = 0
                currentRowElements = []
            }

            currentRowElements.append(Element(subview: subview, x: currentX, y: currentY))
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        if !currentRowElements.isEmpty {
            rows.append(
                Row(
                    elements: currentRowElements,
                    width: currentX - spacing,
                    maxY: currentY + rowHeight
                )
            )
        }

        return rows
    }
}
