import ClipboardCore
import CoreData
import SwiftUI

/// Comprehensive frame manager that handles frame storage, caching, and computation
/// Encapsulates all frame-related logic to reduce complexity in the main view
final class PinboardFrameManager: ObservableObject {
    // MARK: - Published Properties (trigger re-renders only when needed)

    /// Tab frames in PinboardTabBar local space - published only when count/keys change
    @Published private(set) var tabFrames: [NSManagedObjectID: CGRect] = [:]

    /// Content width - published when significantly changed
    @Published private(set) var contentWidth: CGFloat = 0

    // MARK: - Non-Published Properties (always up-to-date, no re-renders)

    /// Latest tab frames (always current, doesn't trigger re-renders)
    private(set) var latestTabFrames: [NSManagedObjectID: CGRect] = [:]

    // MARK: - Cached Ordered Frames

    /// Cached ordered frames (local-space) for placeholder rendering during drag
    private(set) var cachedOrderedFrames: [(item: Pinboard, frame: CGRect)]?

    // MARK: - State Flags

    /// Whether updates should be suppressed (e.g., during drag)
    var suppressUpdates: Bool = false

    /// Whether frame reporting is needed
    var shouldReportFrames: Bool = true

    // MARK: - Update Methods

    /// Updates content-space frames and invalidates caches if needed
    /// - Parameter frames: New frame dictionary
    /// - Returns: True if caches were invalidated
    @discardableResult
    func updateTabFrames(_ frames: [NSManagedObjectID: CGRect]) -> Bool {
        // Always store latest (no re-render)
        latestTabFrames = frames

        // Skip reactive updates if suppressed
        guard !suppressUpdates else { return false }

        // Only publish if count or keys changed
        let countChanged = frames.count != tabFrames.count
        let keysChanged = Set(frames.keys) != Set(tabFrames.keys)

        updateContentWidth(from: frames, countChanged: countChanged)

        if countChanged || keysChanged {
            tabFrames = frames
            invalidateCaches()
            return true
        }

        return false
    }

    // MARK: - Cache Management

    /// Sets cached ordered frames (used during drag initialization)
    func setCachedOrderedFrames(_ orderedFrames: [(item: Pinboard, frame: CGRect)]) {
        cachedOrderedFrames = orderedFrames
    }

    /// Invalidates all cached ordered frames
    func invalidateCaches() {
        cachedOrderedFrames = nil
    }

    /// Clears cached frames (called after drag ends)
    func clearCaches() {
        cachedOrderedFrames = nil
    }

    /// Updates content width based on frames deterministically.
    /// Measures actual content width from frame bounds.
    /// - Parameter frames: Frame dictionary to measure
    /// - Parameter countChanged: Whether frame count changed
    private func updateContentWidth(from frames: [NSManagedObjectID: CGRect], countChanged: Bool) {
        guard !frames.isEmpty else {
            contentWidth = 0
            return
        }

        let minX = frames.values.map { $0.minX }.min() ?? 0
        let maxX = frames.values.map { $0.maxX }.max() ?? 0
        let measuredWidth = maxX - minX

        guard measuredWidth > 0 else { return }

        // Always update on count change (pinboard added/removed)
        // Otherwise update only when width actually differs (deterministic)
        if countChanged || contentWidth == 0 || contentWidth != measuredWidth {
            contentWidth = measuredWidth
        }
    }

    /// Resets all state
    func reset() {
        tabFrames = [:]
        latestTabFrames = [:]
        contentWidth = 0
        cachedOrderedFrames = nil
        suppressUpdates = false
        shouldReportFrames = true
    }
}
