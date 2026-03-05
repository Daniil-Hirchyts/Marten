import CoreGraphics

struct PinboardTabBarLayoutMetrics {
    let availableTabsWidth: CGFloat
    let effectiveContentWidth: CGFloat
    let viewportWidth: CGFloat
    let groupWidth: CGFloat
    let isScrollDisabled: Bool

    init(
        parentWidth: CGFloat,
        addButtonWidth: CGFloat,
        interControlSpacing: CGFloat,
        measuredContentWidth: CGFloat,
        lastNonZeroContentWidth: CGFloat,
        scrollContentPadding: CGFloat,
        fallbackContentWidth: CGFloat
    ) {
        let resolvedAddButtonWidth = max(0, addButtonWidth)
        let resolvedSpacing = max(0, interControlSpacing)
        let resolvedPadding = max(0, scrollContentPadding)
        let resolvedFallbackContentWidth = max(0, fallbackContentWidth)

        availableTabsWidth = max(0, parentWidth - resolvedAddButtonWidth - resolvedSpacing)

        if measuredContentWidth > 0 {
            effectiveContentWidth = measuredContentWidth
        } else if lastNonZeroContentWidth > 0 {
            effectiveContentWidth = lastNonZeroContentWidth
        } else {
            effectiveContentWidth = resolvedFallbackContentWidth
        }

        let contentWithPadding = effectiveContentWidth + (resolvedPadding * 2)
        viewportWidth = min(contentWithPadding, availableTabsWidth)
        groupWidth = viewportWidth + resolvedSpacing + resolvedAddButtonWidth
        isScrollDisabled = availableTabsWidth <= 0 || contentWithPadding <= availableTabsWidth
    }
}
