import AppKit
import Foundation
import OSLog

public final class PasteboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var timer: Timer?
    private var isMonitoring = false
    private var suppressToken: UUID?
    private var changeCountAtSuppression: Int?
    private var lastActivity: Date?
    private var currentInterval: TimeInterval?

    public var pollInterval: TimeInterval = 0.4
    public var adaptivePollingEnabled = true
    public var fastPollInterval: TimeInterval = 0.4
    public var idlePollInterval: TimeInterval = 1.5
    public var idleThreshold: TimeInterval = 5.0
    public var isEnabled = true
    public var onClipboardChange: ((NSPasteboard) -> Void)?

    public init() {}

    public func start() {
        guard !isMonitoring else { return }
        lastChangeCount = pasteboard.changeCount
        isMonitoring = true
        lastActivity = Date()

        let interval = adaptivePollingEnabled ? fastPollInterval : pollInterval
        scheduleTimer(interval: interval)

        Logger.pasteboard.info("Pasteboard monitor started")
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        currentInterval = nil
        Logger.pasteboard.info("Pasteboard monitor stopped")
    }

    public func pause() {
        isEnabled = false
    }

    public func resume() {
        isEnabled = true
    }

    /// Suppresses the next clipboard change detection and returns a token.
    /// The suppression only applies to the immediate next change after this call.
    /// Using a versioned token system prevents race conditions where multiple
    /// changes could cause missed detections.
    @discardableResult
    public func suppressNextChange() -> UUID {
        let token = UUID()
        suppressToken = token
        changeCountAtSuppression = pasteboard.changeCount
        return token
    }

    /// Cancels an active suppression if the provided token matches the current one.
    public func cancelSuppression(token: UUID) {
        if suppressToken == token {
            suppressToken = nil
            changeCountAtSuppression = nil
        }
    }

    private func checkForChanges() {
        guard isEnabled else { return }

        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else {
            handleIdleTransition()
            return
        }

        lastChangeCount = currentCount

        // Only suppress if we have a token and this is the immediate next change
        // (changeCount is exactly one more than when suppression was requested)
        if let suppressionCount = changeCountAtSuppression,
           currentCount == suppressionCount + 1 {
            suppressToken = nil
            changeCountAtSuppression = nil
            return
        }
        
        // Clear stale suppression tokens (if change count has moved beyond expected)
        if suppressToken != nil {
            suppressToken = nil
            changeCountAtSuppression = nil
        }

        lastActivity = Date()
        if adaptivePollingEnabled {
            applyIntervalIfNeeded(fastPollInterval)
        }

        onClipboardChange?(pasteboard)
    }

    private func handleIdleTransition() {
        guard adaptivePollingEnabled else { return }
        guard let lastActivity else { return }
        if Date().timeIntervalSince(lastActivity) >= idleThreshold {
            applyIntervalIfNeeded(idlePollInterval)
        }
    }

    private func applyIntervalIfNeeded(_ interval: TimeInterval) {
        guard currentInterval != interval else { return }
        scheduleTimer(interval: interval)
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        currentInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }

        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}
