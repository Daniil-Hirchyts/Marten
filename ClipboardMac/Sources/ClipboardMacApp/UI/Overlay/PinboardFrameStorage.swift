import ClipboardCore
import CoreData
import SwiftUI

/// Comprehensive frame manager that handles frame storage, caching, and computation
/// Encapsulates all frame-related logic to reduce complexity in the main view
final class PinboardFrameManager: ObservableObject {
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

    // MARK: - Cached Ordered Frames

    /// Cached ordered frames (content-space) to avoid repeated sorting during drag
    private(set) var cachedOrderedFrames: [(item: Pinboard, frame: CGRect)]?

    /// Cached local-space ordered frames for placeholder rendering during drag
    private(set) var cachedLocalOrderedFrames: [(item: Pinboard, frame: CGRect)]?

    // MARK: - State Flags

    /// Whether updates should be suppressed (e.g., during drag)
    var suppressUpdates: Bool = false

    /// Whether frame reporting is needed
    var shouldReportFrames: Bool = true

    // MARK: - Update Methods

    /// Updates content-space frames and invalidates caches if needed
    /// - Parameter frames: New frame dictionary
    /// - Parameter tabSpacing: Spacing between tabs for width calculation
    /// - Returns: True if caches were invalidated
    @discardableResult
    func updateTabFrames(_ frames: [NSManagedObjectID: CGRect], tabSpacing: CGFloat) -> Bool {
        // Always store latest (no re-render)
        latestTabFrames = frames

        // Skip reactive updates if suppressed
        guard !suppressUpdates else { return false }

        // Only publish if count or keys changed
        let countChanged = frames.count != tabFrames.count
        let keysChanged = Set(frames.keys) != Set(tabFrames.keys)

        if countChanged || keysChanged {
            tabFrames = frames
            updateContentWidth(from: frames, countChanged: countChanged)
            invalidateCaches()
            return true
        }

        return false
    }

    /// Updates local-space frames and invalidates caches if needed
    /// - Parameter frames: New frame dictionary
    /// - Returns: True if caches were invalidated
    @discardableResult
    func updateLocalTabFrames(_ frames: [NSManagedObjectID: CGRect]) -> Bool {
        // Always store latest (no re-render)
        latestLocalTabFrames = frames

        // Skip reactive updates if suppressed
        guard !suppressUpdates else { return false }

        // Only publish if count or keys changed
        let countChanged = frames.count != localTabFrames.count
        let keysChanged = Set(frames.keys) != Set(localTabFrames.keys)

        if countChanged || keysChanged {
            localTabFrames = frames
            invalidateLocalCache()
            return true
        }

        return false
    }

    /// Updates scroll offset (never published)
    /// - Parameter offset: New scroll offset
    func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset

        // Turn off frame reporting after initial capture
        if shouldReportFrames {
            shouldReportFrames = false
        }
    }

    // MARK: - Cache Management

    /// Sets cached ordered frames (used during drag initialization)
    func setCachedFrames(
        orderedFrames: [(item: Pinboard, frame: CGRect)],
        localOrderedFrames: [(item: Pinboard, frame: CGRect)]
    ) {
        cachedOrderedFrames = orderedFrames
        cachedLocalOrderedFrames = localOrderedFrames
    }

    /// Invalidates all cached ordered frames
    func invalidateCaches() {
        cachedOrderedFrames = nil
        cachedLocalOrderedFrames = nil
    }

    /// Invalidates only local cached frames
    func invalidateLocalCache() {
        cachedLocalOrderedFrames = nil
    }

    /// Clears cached frames (called after drag ends)
    func clearCaches() {
        cachedOrderedFrames = nil
        cachedLocalOrderedFrames = nil
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

    /// Resets all state
    func reset() {
        tabFrames = [:]
        localTabFrames = [:]
        latestTabFrames = [:]
        latestLocalTabFrames = [:]
        contentWidth = 0
        scrollOffset = 0
        cachedOrderedFrames = nil
        cachedLocalOrderedFrames = nil
        suppressUpdates = false
        shouldReportFrames = true
    }
}
