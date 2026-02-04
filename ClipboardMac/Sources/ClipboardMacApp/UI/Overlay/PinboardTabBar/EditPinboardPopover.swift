import SwiftUI

extension PinboardTabBar {
    @ViewBuilder
    func placeholderView() -> some View {
        if let dropTarget,
            let localFrame = frameManager.latestTabFrames[dropTarget.item.objectID],
            isPlaceholderVisible(at: dropTarget.placeholderX)
        {
            let height = max(0, localFrame.height)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: .controlAccentColor))
                .frame(width: placeholderWidth, height: height)
                .offset(x: dropTarget.placeholderX - placeholderWidth / 2, y: 0)
                .transition(.opacity)
        }
    }

    func isPlaceholderVisible(at x: CGFloat) -> Bool {
        guard !scrollViewBounds.isEmpty else { return true }
        let margin: CGFloat = 10
        return x >= scrollViewBounds.minX - margin && x <= scrollViewBounds.maxX + margin
    }

    @ViewBuilder
    func dragPreviewView() -> some View {
        if let dragState,
            let draggedItem = pinboards.first(where: { $0.objectID == dragState.itemID }),
            let localFrame = frameManager.latestTabFrames[draggedItem.objectID]
        {
            PinboardTabPreview(
                title: draggedItem.name,
                colorHex: draggedItem.colorHex,
                iconName: draggedItem.iconName
            )
                .frame(width: localFrame.width, height: localFrame.height)
                .position(
                    x: dragState.pointerLocation.x - dragState.cursorOffset.width,
                    y: dragState.pointerLocation.y - dragState.cursorOffset.height
                )
                .opacity(dragOpacity)
                .animation(Animation.easeOut(duration: 0.1), value: dragOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
