import SwiftUI

@available(macOS 13.0, iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        if rows.isEmpty { return .zero }
        
        let width = proposal.width ?? rows.map { $0.width }.max() ?? 0
        let height = rows.last?.maxY ?? 0
        
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        
        for row in rows {
            for element in row.elements {
                let x = bounds.minX + element.x
                let y = bounds.minY + element.y
                element.subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
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
            
            if currentX + size.width > maxWidth && !currentRowElements.isEmpty {
                // New row
                rows.append(Row(elements: currentRowElements, width: currentX - spacing, maxY: currentY + rowHeight))
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
            rows.append(Row(elements: currentRowElements, width: currentX - spacing, maxY: currentY + rowHeight))
        }

        return rows
    }
}
