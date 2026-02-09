import AppKit
import MartenCore
import Combine
import Foundation
import OSLog

public final class PasteboardMonitor: ObservableObject {
    private let pasteboard = NSPasteboard.general
    private let ignoredAppsManager: IgnoredAppsManager
    private let activeAppTracker: ActiveAppTracker
    private var lastChangeCount = 0
    private var timer: Timer?
    private var isMonitoring = false
    private var suppressToken: UUID?
    private var changeCountAtSuppression: Int?
    private var lastActivity: Date?
    private var currentInterval: TimeInterval?
    private var isIdle = false
    private var pauseTimer: Timer?

    @Published public private(set) var isPaused: Bool = false

    public var pollInterval: TimeInterval = 0.4
    public var adaptivePollingEnabled = true
    public var fastPollInterval: TimeInterval = 0.4
    public var idlePollInterval: TimeInterval = 1.5
    public var idleThreshold: TimeInterval = 5.0
    public var onMartenChange: ((NSPasteboard) -> Void)?

    public var isEnabled: Bool {
        get { performOnMain { _isEnabled } }
        set { performOnMain { _isEnabled = newValue } }
    }

    private var _isEnabled = true

    public init(
        activeAppTracker: ActiveAppTracker = ActiveAppTracker(),
        ignoredAppsManager: IgnoredAppsManager = IgnoredAppsManager()
    ) {
        self.activeAppTracker = activeAppTracker
        self.ignoredAppsManager = ignoredAppsManager
    }

    public func start() {
        performOnMain {
            self.startOnMain()
        }
    }

    private func startOnMain() {
        guard !isMonitoring else { return }
        lastChangeCount = pasteboard.changeCount
        isMonitoring = true
        lastActivity = Date()

        let interval = adaptivePollingEnabled ? fastPollInterval : pollInterval
        scheduleTimer(interval: interval)

        Logger.pasteboard.info("Pasteboard monitor started")
    }

    public func stop() {
        performOnMain {
            self.stopOnMain()
        }
    }

    private func stopOnMain() {
        timer?.invalidate()
        timer = nil
        pauseTimer?.invalidate()
        pauseTimer = nil
        isMonitoring = false
        currentInterval = nil
        isPaused = false
        Logger.pasteboard.info("Pasteboard monitor stopped")
    }

    public func pause() {
        performOnMain {
            self.pauseOnMain()
        }
    }

    private func pauseOnMain() {
        _isEnabled = false
        isPaused = true
        Logger.pasteboard.info("Pasteboard capture paused")
    }

    public func resume() {
        performOnMain {
            self.resumeOnMain()
        }
    }

    private func resumeOnMain() {
        pauseTimer?.invalidate()
        pauseTimer = nil
        _isEnabled = true
        isPaused = false
        lastChangeCount = pasteboard.changeCount
        Logger.pasteboard.info("Pasteboard capture resumed")
    }

    /// Pauses capture for the given duration, or indefinitely when `duration` is `nil`.
    /// Invalidates any previously scheduled auto-resume timer before starting a new one.
    public func pauseForDuration(_ duration: TimeInterval?) {
        performOnMain {
            self.pauseForDurationOnMain(duration)
        }
    }

    private func pauseForDurationOnMain(_ duration: TimeInterval?) {
        pauseTimer?.invalidate()
        pauseTimer = nil
        pauseOnMain()
        guard let duration else { return }
        pauseTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) {
            [weak self] _ in
            self?.resumeOnMain()
        }
        if let timer = pauseTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    /// Suppresses the next clipboard change detection and returns a token.
    /// The suppression only applies to the immediate next change after this call.
    /// Using a versioned token system prevents race conditions where multiple
    /// changes could cause missed detections.
    @discardableResult
    public func suppressNextChange() -> UUID {
        performOnMain {
            let token = UUID()
            suppressToken = token
            changeCountAtSuppression = pasteboard.changeCount
            return token
        }
    }

    /// Cancels an active suppression if the provided token matches the current one.
    public func cancelSuppression(token: UUID) {
        performOnMain {
            if suppressToken == token {
                suppressToken = nil
                changeCountAtSuppression = nil
            }
        }
    }

    private func checkForChanges() {
        guard _isEnabled else { return }

        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else {
            handleIdleTransition()
            return
        }

        lastChangeCount = currentCount

        // Suppress any change that follows the suppression request.
        // clearContents() + write can bump changeCount by 2 in a single run-loop tick,
        // so we match any count greater than the snapshot taken at suppression time.
        if let suppressionCount = changeCountAtSuppression,
            currentCount > suppressionCount
        {
            Logger.pasteboard.info(
                "Suppressing change detection (token: \(String(describing: self.suppressToken), privacy: .public))"
            )
            suppressToken = nil
            changeCountAtSuppression = nil
            return
        }

        // Clear stale suppression tokens (if change count has moved beyond expected)
        if suppressToken != nil {
            Logger.pasteboard.warning("Clearing stale suppression token")
            suppressToken = nil
            changeCountAtSuppression = nil
        }

        activeAppTracker.recordFrontmostApp()
        if let bundleID = activeAppTracker.recordedBundleID,
            ignoredAppsManager.isIgnored(bundleIdentifier: bundleID)
        {
            Logger.pasteboard.info(
                "Skipping capture from ignored app: \(bundleID, privacy: .public)")
            return
        }

        lastActivity = Date()
        isIdle = false
        if adaptivePollingEnabled {
            applyIntervalIfNeeded(fastPollInterval)
        }

        Logger.pasteboard.info("Pasteboard change detected, changeCount: \(currentCount)")
        onMartenChange?(pasteboard)
    }

    private func handleIdleTransition() {
        guard adaptivePollingEnabled else { return }
        guard let lastActivity else { return }
        if Date().timeIntervalSince(lastActivity) >= idleThreshold, !isIdle {
            isIdle = true
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

    private func performOnMain<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }
}
