import AppKit
import ClipboardCore
import CoreData

struct DragState {
    let itemIDs: [NSManagedObjectID]
    let primaryItemID: NSManagedObjectID
    var pointerLocation: CGPoint
    let baseCenter: CGPoint
    var translation: CGSize
}

enum PinboardDropTarget: Equatable {
    case all
    case pinboard(NSManagedObjectID)
}

/// Capture a card region from the overlay window as an `NSImage`.
/// The `cardRect` is in the overlay's SwiftUI coordinate space (top-left origin),
/// which maps to the flipped NSHostingView's coordinate system.
/// Insets the rect slightly to avoid capturing edges of adjacent cards.
@MainActor
func captureCardSnapshot(from window: NSWindow, cardRect: CGRect) -> NSImage? {
    guard let contentView = window.contentView else { return nil }
    let insetRect = cardRect.insetBy(dx: 2, dy: 2)
    let clampedRect = insetRect.intersection(contentView.bounds)
    guard !clampedRect.isEmpty, clampedRect.width > 1, clampedRect.height > 1 else { return nil }
    guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: clampedRect) else { return nil }
    contentView.cacheDisplay(in: clampedRect, to: bitmapRep)
    let image = NSImage(size: clampedRect.size)
    image.addRepresentation(bitmapRep)
    return image
}
