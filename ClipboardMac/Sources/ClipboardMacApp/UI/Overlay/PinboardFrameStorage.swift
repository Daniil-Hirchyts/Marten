import ClipboardCore
import CoreData
import SwiftUI

/// Manages frame storage with intelligent publishing to avoid unnecessary re-renders
/// Only publishes changes when frame count or keys change, not on every frame update
final class PinboardFrameStorage: ObservableObject {
    // MARK: - Published Properties (trigger re-renders only when needed)

    /// Content-space frames - published only when count/keys change
    @Published private(set) var tabFrames: [NSManagedObjectID: CGRect] = [:]

    /// Local-space frames - published only when count/keys change
    @Published private(set) var localTabFrames: [NSManagedObjectID: CGRect] = [:]

    /// Content width - published when significantly changed
    @Published private(set) var contentWidth: CGFloat = 0

    // MARK: - Non-Published Properties (always up-to-date, no re-renders)

    /// Latest content-space frames (always current, doesn't trigger re-renders)
    private(set) var latestTabFrames: [NSManagedObjectID: CGRect] = [:]

    /// Latest local-space frames (always current, doesn't trigger re-renders)
    private(set) var latestLocalTabFrames: [NSManagedObjectID: CGRect] = [:]

    /// Latest scroll offset (always current, doesn't trigger re-renders)
    private(set) var scrollOffset: CGFloat = 0

    // MARK: - State Flags

    /// Whether updates should be suppressed (e.g., during drag)
    var suppressUpdates: Bool = false

    // MARK: - Update Methods

    /// Updates content-space frames
    /// - Parameter frames: New frame dictionary
    /// - Parameter tabSpacing: Spacing between tabs for width calculation
    func updateTabFrames(_ frames: [NSManagedObjectID: CGRect], tabSpacing: CGFloat) {
        // Always store latest (no re-render)
        latestTabFrames = frames

        // Skip reactive updates if suppressed
        guard !suppressUpdates else { return }

        // Only publish if count or keys changed
        let countChanged = frames.count != tabFrames.count
        let keysChanged = Set(frames.keys) != Set(tabFrames.keys)

        if countChanged || keysChanged {
            tabFrames = frames
            updateContentWidth(from: frames, countChanged: countChanged)
        }
    }

    /// Updates local-space frames
    /// - Parameter frames: New frame dictionary
    func updateLocalTabFrames(_ frames: [NSManagedObjectID: CGRect]) {
        // Always store latest (no re-render)
        latestLocalTabFrames = frames

        // Skip reactive updates if suppressed
        guard !suppressUpdates else { return }

        // Only publish if count or keys changed
        let countChanged = frames.count != localTabFrames.count
        let keysChanged = Set(frames.keys) != Set(localTabFrames.keys)

        if countChanged || keysChanged {
            localTabFrames = frames
        }
    }

    /// Updates scroll offset (never published)
    /// - Parameter offset: New scroll offset
    func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
    }

    /// Updates content width based on frames
    /// - Parameter frames: Frame dictionary to measure
    /// - Parameter countChanged: Whether frame count changed
    private func updateContentWidth(from frames: [NSManagedObjectID: CGRect], countChanged: Bool) {
        if !frames.isEmpty {
            let minX = frames.values.map { $0.minX }.min() ?? 0
            let maxX = frames.values.map { $0.maxX }.max() ?? 0
            let measuredWidth = maxX - minX

            // Always update if count changed, otherwise only if significant change
            if measuredWidth > 0 && (countChanged || abs(contentWidth - measuredWidth) > 10) {
                contentWidth = measuredWidth
            }
        } else {
            // Reset content width when there are no frames
            contentWidth = 0
        }
    }

    /// Resets all cached frames
    func reset() {
        tabFrames = [:]
        localTabFrames = [:]
        latestTabFrames = [:]
        latestLocalTabFrames = [:]
        contentWidth = 0
        scrollOffset = 0
    }
}
