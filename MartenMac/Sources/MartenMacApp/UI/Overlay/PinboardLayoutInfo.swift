import CoreData
import SwiftUI

struct PinboardLayoutInfo: Equatable {
    var tabFrames: [NSManagedObjectID: CGRect] = [:]
    var overlayPinboardFrames: [NSManagedObjectID: CGRect] = [:]
    var allOverlayFrame: CGRect? = nil
    var editorOverlayFrame: CGRect? = nil
    var scrollOffset: CGFloat? = nil
    var contentWidth: CGFloat? = nil

    mutating func merge(_ other: PinboardLayoutInfo) {
        tabFrames.merge(other.tabFrames, uniquingKeysWith: { _, new in new })
        overlayPinboardFrames.merge(
            other.overlayPinboardFrames, uniquingKeysWith: { _, new in new })

        if let allOverlayFrame = other.allOverlayFrame {
            self.allOverlayFrame = allOverlayFrame
        }
        if let editorOverlayFrame = other.editorOverlayFrame {
            self.editorOverlayFrame = editorOverlayFrame
        }
        if let scrollOffset = other.scrollOffset {
            self.scrollOffset = scrollOffset
        }
        if let contentWidth = other.contentWidth {
            self.contentWidth = contentWidth
        }
    }

    mutating func recomputeDerived() {
        guard !tabFrames.isEmpty else {
            contentWidth = 0
            return
        }
        let minX = tabFrames.values.map { $0.minX }.min() ?? 0
        let maxX = tabFrames.values.map { $0.maxX }.max() ?? 0
        contentWidth = max(0, maxX - minX)
    }
}

struct PinboardLayoutInfoKey: PreferenceKey {
    static var defaultValue: PinboardLayoutInfo = PinboardLayoutInfo()

    static func reduce(value: inout PinboardLayoutInfo, nextValue: () -> PinboardLayoutInfo) {
        value.merge(nextValue())
        value.recomputeDerived()
    }
}

struct PinboardContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}
