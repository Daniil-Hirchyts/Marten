import AppKit
import Carbon.HIToolbox
import MartenCore
import Foundation
import OSLog

public protocol PasteEngineProtocol: AnyObject {
    func recordFrontmostApp()
    func pasteItem(_ item: ClipItem, format: PasteFormat) async throws
    func pasteStack(_ session: StackSession, format: PasteFormat) async throws -> PasteStackResult
    func copyItemToMarten(_ item: ClipItem, format: PasteFormat) async throws
    func copyStackToMarten(_ session: StackSession) async throws
    func pastePlainText(_ text: String) async throws
    func copyPlainTextToMarten(_ text: String) async throws
}

public protocol ActiveAppTracking: AnyObject {
    func recordFrontmostApp()
    func reactivateRecordedApp()
    var recordedBundleID: String? { get }
}

public protocol AccessibilityPermissionChecking: AnyObject {
    func checkAccessibility(prompt: Bool) -> Bool
}

public protocol PasteKeystrokeSending: AnyObject {
    func send(configuration: PasteEngineConfiguration) async throws
}

public protocol TargetActivationChecking: AnyObject {
    func isTargetAppFrontmost(targetBundleID: String) async -> Bool
    func waitForTargetActivation(targetBundleID: String, timeout: TimeInterval) async -> Bool
}

public final class SystemPasteKeystrokeSender: PasteKeystrokeSending {
    public init() {}

    public func send(configuration: PasteEngineConfiguration) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw PasteEngineError.eventSourceUnavailable
        }

        let cmdDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: configuration.pasteKeystroke.modifierKeyCode,
            keyDown: true
        )
        cmdDown?.flags = configuration.pasteKeystroke.modifierFlags
        let vDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: configuration.pasteKeystroke.pasteKeyCode,
            keyDown: true
        )
        vDown?.flags = configuration.pasteKeystroke.modifierFlags
        let vUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: configuration.pasteKeystroke.pasteKeyCode,
            keyDown: false
        )
        vUp?.flags = configuration.pasteKeystroke.modifierFlags
        let cmdUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: configuration.pasteKeystroke.modifierKeyCode,
            keyDown: false
        )

        cmdDown?.post(tap: configuration.pasteKeystroke.postTap)
        vDown?.post(tap: configuration.pasteKeystroke.postTap)
        vUp?.post(tap: configuration.pasteKeystroke.postTap)
        cmdUp?.post(tap: configuration.pasteKeystroke.postTap)
    }
}

public final class SystemTargetActivationChecker: TargetActivationChecking {
    public init() {}

    public func isTargetAppFrontmost(targetBundleID: String) async -> Bool {
        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        return frontmost?.bundleIdentifier == targetBundleID
    }

    public func waitForTargetActivation(targetBundleID: String, timeout: TimeInterval) async -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication }
            if frontmost?.bundleIdentifier == targetBundleID {
                return true
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        let frontmost = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        return frontmost?.bundleIdentifier == targetBundleID
    }
}

public enum PasteFormat {
    case preserved
    case plainText
}

public enum PasteEngineError: Error {
    case accessibilityPermissionDenied
    case emptyStack
    case missingPlainText
    case targetActivationFailed
    case eventSourceUnavailable
}

public struct PasteEngineConfiguration: Equatable {
    public struct PasteKeystroke: Equatable {
        public var modifierKeyCode: CGKeyCode
        public var modifierFlags: CGEventFlags
        public var pasteKeyCode: CGKeyCode

        /// Tap location used for posting synthetic keyboard events via `CGEvent.post(tap:)`.
        ///
        /// ## Security Implications
        ///
        /// Posting at a session-level tap can deliver keystrokes to the frontmost application in
        /// the current user session. This is powerful and is gated by Accessibility permission.
        ///
        /// ## Why `.cgSessionEventTap`
        ///
        /// `.cgSessionEventTap` posts into the active login session’s event stream (via the
        /// WindowServer) and is generally the most compatible choice for “act like a user pressed
        /// paste” behavior. Other tap locations (e.g. `.cghidEventTap`) can behave differently
        /// depending on system policy and target application.
        public var postTap: CGEventTapLocation

        public init(
            modifierKeyCode: CGKeyCode,
            modifierFlags: CGEventFlags,
            pasteKeyCode: CGKeyCode,
            postTap: CGEventTapLocation
        ) {
            self.modifierKeyCode = modifierKeyCode
            self.modifierFlags = modifierFlags
            self.pasteKeyCode = pasteKeyCode
            self.postTap = postTap
        }

        public static let `default` = PasteKeystroke(
            modifierKeyCode: CGKeyCode(kVK_Command),
            modifierFlags: .maskCommand,
            pasteKeyCode: CGKeyCode(kVK_ANSI_V),
            postTap: .cgSessionEventTap
        )
    }

    public struct TargetActivation: Equatable {
        public var timeout: TimeInterval
        public var maxAttempts: Int
        public var retryDelay: TimeInterval

        public init(timeout: TimeInterval, maxAttempts: Int, retryDelay: TimeInterval) {
            self.timeout = timeout
            self.maxAttempts = maxAttempts
            self.retryDelay = retryDelay
        }

        public static let `default` = TargetActivation(
            timeout: 0.6, maxAttempts: 3, retryDelay: 0.15)
    }

    public var pasteKeystroke: PasteKeystroke
    public var targetActivation: TargetActivation
    public var interItemDelay: TimeInterval

    public init(
        pasteKeystroke: PasteKeystroke,
        targetActivation: TargetActivation,
        interItemDelay: TimeInterval
    ) {
        self.pasteKeystroke = pasteKeystroke
        self.targetActivation = targetActivation
        self.interItemDelay = interItemDelay
    }

    public static let `default` = PasteEngineConfiguration(
        pasteKeystroke: .default,
        targetActivation: .default,
        interItemDelay: 0.15
    )
}

/// Reason why a stack entry was skipped during paste
public enum SkipReason: CustomStringConvertible {
    case nilClipItem
    case writeFailed(Error)

    public var description: String {
        switch self {
        case .nilClipItem:
            return "Entry has no associated clip item"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        }
    }
}

/// Information about a skipped entry during stack paste
public struct SkippedEntry {
    public let position: Int
    public let reason: SkipReason

    public init(position: Int, reason: SkipReason) {
        self.position = position
        self.reason = reason
    }
}

/// Result of a paste stack operation
public struct PasteStackResult {
    public let successCount: Int
    public let skippedEntries: [SkippedEntry]

    public var hasSkippedEntries: Bool { !skippedEntries.isEmpty }

    public init(successCount: Int, skippedEntries: [SkippedEntry]) {
        self.successCount = successCount
        self.skippedEntries = skippedEntries
    }
}

/// Writes a `ClipItem` to the pasteboard and requests the target app to paste via a synthetic
/// keystroke.
///
/// ## Security Implications
///
/// This type injects keyboard events using `CGEvent` (`CGEvent.post(tap:)`). Keystroke injection
/// can be abused to type into arbitrary applications, so macOS gates it behind Accessibility
/// permission.
///
/// The engine attempts to minimize risk by reactivating the previously recorded frontmost app
/// (`ActiveAppTracker`) before sending the paste shortcut, but it cannot prevent the user from
/// changing focus at the exact moment events are posted.
public final class PasteEngine {
    private let pasteboard: NSPasteboard
    private let activeAppTracker: any ActiveAppTracking
    private let assetStore: AssetStore
    private let permissionManager: any AccessibilityPermissionChecking
    private let eventBroadcaster: MartenEventBroadcaster
    private let configuration: PasteEngineConfiguration
    private let keystrokeSender: any PasteKeystrokeSending
    private let activationChecker: any TargetActivationChecking
    private let pasteboardItemBuilder: PasteboardItemBuilder

    public init(
        pasteboard: NSPasteboard = .general,
        activeAppTracker: any ActiveAppTracking = ActiveAppTracker(),
        assetStore: AssetStore = .shared,
        permissionManager: any AccessibilityPermissionChecking = PermissionManager(),
        eventBroadcaster: MartenEventBroadcaster = MartenEventBroadcasterImpl(),
        configuration: PasteEngineConfiguration = .default,
        keystrokeSender: any PasteKeystrokeSending = SystemPasteKeystrokeSender(),
        activationChecker: any TargetActivationChecking = SystemTargetActivationChecker()
    ) {
        self.pasteboard = pasteboard
        self.activeAppTracker = activeAppTracker
        self.assetStore = assetStore
        self.permissionManager = permissionManager
        self.eventBroadcaster = eventBroadcaster
        self.configuration = configuration
        self.keystrokeSender = keystrokeSender
        self.activationChecker = activationChecker
        self.pasteboardItemBuilder = PasteboardItemBuilder(assetStore: assetStore)
    }

    public func recordFrontmostApp() {
        activeAppTracker.recordFrontmostApp()
    }

    public func copyItemToMarten(_ item: ClipItem, format: PasteFormat = .preserved) async throws
    {
        try await writeToPasteboard(item, format: format)
    }

    public func copyStackToMarten(_ session: StackSession) async throws {
        let entries = session.entries?.sorted { $0.position < $1.position } ?? []
        guard !entries.isEmpty else {
            throw PasteEngineError.emptyStack
        }

        let separator = session.separator
        let isCombined = session.modeValue == .combined
        let chunks = entries.compactMap { $0.clipItem }.map { item in
            item.plainTextContent ?? item.primaryText ?? ""
        }
        let joined =
            isCombined ? chunks.joined(separator: separator) : chunks.joined(separator: "\n")

        await MainActor.run {
            eventBroadcaster.publish(.clipboardWillWrite)
            pasteboard.clearContents()
            pasteboard.setString(joined, forType: .string)
        }
    }

    public func pastePlainText(_ text: String) async throws {
        Logger.paste.info("Starting plain text paste operation")
        await writePlainTextToPasteboard(text)
        await MainActor.run {
            activeAppTracker.reactivateRecordedApp()
        }
        let activated = await ensureTargetActivation()
        guard activated else {
            Logger.paste.error("Target activation failed during pastePlainText")
            throw PasteEngineError.targetActivationFailed
        }
        try await sendPasteKeystroke()
        Logger.paste.info("Plain text paste operation completed successfully")
    }

    public func copyPlainTextToMarten(_ text: String) async throws {
        await writePlainTextToPasteboard(text)
    }

    private func writePlainTextToPasteboard(_ text: String) async {
        await MainActor.run {
            eventBroadcaster.publish(.clipboardWillWrite)
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    public func pasteItem(_ item: ClipItem, format: PasteFormat = .preserved) async throws {
        Logger.paste.info("Starting paste operation")
        try await writeToPasteboard(item, format: format)
        await MainActor.run {
            activeAppTracker.reactivateRecordedApp()
        }
        let activated = await ensureTargetActivation()
        guard activated else {
            Logger.paste.error("Target activation failed during pasteItem")
            throw PasteEngineError.targetActivationFailed
        }
        try await sendPasteKeystroke()
        Logger.paste.info("Paste operation completed successfully")
    }

    @discardableResult
    public func pasteStack(_ session: StackSession, format: PasteFormat = .preserved) async throws
        -> PasteStackResult
    {
        Logger.paste.info("Starting stack paste operation (entries: \(session.entries?.count ?? 0))")
        let entries = session.entries?.sorted { $0.position < $1.position } ?? []
        guard !entries.isEmpty else {
            throw PasteEngineError.emptyStack
        }

        await MainActor.run {
            activeAppTracker.reactivateRecordedApp()
        }
        let activated = await ensureTargetActivation()
        guard activated else {
            throw PasteEngineError.targetActivationFailed
        }

        var successCount = 0
        var skippedEntries: [SkippedEntry] = []

        for (index, entry) in entries.enumerated() {
            guard let item = entry.clipItem else {
                let skipped = SkippedEntry(position: Int(entry.position), reason: .nilClipItem)
                skippedEntries.append(skipped)
                Logger.paste.warning(
                    "Skipping stack entry at position \(entry.position): \(SkipReason.nilClipItem.description)"
                )
                continue
            }

            if !(await isTargetAppFrontmost()) {
                await MainActor.run {
                    activeAppTracker.reactivateRecordedApp()
                }
                let reactivated = await ensureTargetActivation()
                guard reactivated else {
                    throw PasteEngineError.targetActivationFailed
                }
            }

            do {
                try await writeToPasteboard(item, format: format)
                try await sendPasteKeystroke()
                successCount += 1
            } catch {
                let skipped = SkippedEntry(
                    position: Int(entry.position), reason: .writeFailed(error))
                skippedEntries.append(skipped)
                Logger.paste.warning(
                    "Skipping stack entry at position \(entry.position): \(error.localizedDescription)"
                )
                continue
            }

            if index < entries.count - 1, session.modeValue == .combined {
                try await insertSeparator(session.separator)
            }

            if index < entries.count - 1 {
                let nanos = UInt64(max(configuration.interItemDelay, 0) * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
            }
        }

        if !skippedEntries.isEmpty {
            Logger.paste.info(
                "Paste stack completed: \(successCount) succeeded, \(skippedEntries.count) skipped")
        }

        return PasteStackResult(successCount: successCount, skippedEntries: skippedEntries)
    }

    private func writeToPasteboard(_ item: ClipItem, format: PasteFormat) async throws {
        try await MainActor.run {
            eventBroadcaster.publish(.clipboardWillWrite)
            pasteboard.clearContents()

            switch format {
            case .plainText:
                guard let plainText = item.plainTextContent, !plainText.isEmpty else {
                    throw PasteEngineError.missingPlainText
                }
                pasteboard.setString(plainText, forType: .string)
            case .preserved:
                let pasteboardItem = try pasteboardItemBuilder.buildPasteboardItem(from: item)
                pasteboard.writeObjects([pasteboardItem])
            }
        }
    }

    private func insertSeparator(_ separator: String) async throws {
        await MainActor.run {
            eventBroadcaster.publish(.clipboardWillWrite)
            pasteboard.clearContents()
            pasteboard.setString(separator, forType: .string)
        }
        try await sendPasteKeystroke()
    }

    private func sendPasteKeystroke() async throws {
        guard permissionManager.checkAccessibility(prompt: false) else {
            Logger.paste.error("Paste keystroke failed: Accessibility permission denied")
            await MainActor.run {
                eventBroadcaster.publish(
                    .pasteEngineValidationFailed(.accessibilityPermissionDenied))
            }
            throw PasteEngineError.accessibilityPermissionDenied
        }
        do {
            try await keystrokeSender.send(configuration: configuration)
        } catch PasteEngineError.eventSourceUnavailable {
            await MainActor.run {
                eventBroadcaster.publish(.pasteEngineValidationFailed(.eventSourceUnavailable))
            }
            throw PasteEngineError.eventSourceUnavailable
        }
    }

    private func ensureTargetActivation() async -> Bool {
        let targetBundleID = await MainActor.run { activeAppTracker.recordedBundleID }
        let attempts = max(configuration.targetActivation.maxAttempts, 1)
        for attempt in 1...attempts {
            let activated = await waitForTargetActivation(
                timeout: configuration.targetActivation.timeout)
            if activated {
                return true
            }
            if attempt < attempts {
                await MainActor.run {
                    eventBroadcaster.publish(
                        .pasteEngineWillRetryActivation(
                            attempt: attempt + 1,
                            targetBundleID: targetBundleID
                        )
                    )
                }
                let nanos = UInt64(
                    max(configuration.targetActivation.retryDelay, 0) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                await MainActor.run {
                    activeAppTracker.reactivateRecordedApp()
                }
            }
        }

        let activated = await isTargetAppFrontmost()
        if !activated {
            await MainActor.run {
                eventBroadcaster.publish(
                    .pasteEngineValidationFailed(
                        .targetActivationTimedOut(targetBundleID: targetBundleID)
                    )
                )
            }
        }
        return activated
    }

    private func isTargetAppFrontmost() async -> Bool {
        let targetBundleID = await MainActor.run { activeAppTracker.recordedBundleID }
        guard let targetBundleID else { return false }
        return await activationChecker.isTargetAppFrontmost(targetBundleID: targetBundleID)
    }

    private func waitForTargetActivation(timeout: TimeInterval) async -> Bool {
        let targetBundleID = await MainActor.run { activeAppTracker.recordedBundleID }
        guard let targetBundleID else { return false }
        return await activationChecker.waitForTargetActivation(
            targetBundleID: targetBundleID,
            timeout: timeout
        )
    }
}

extension PasteEngine: PasteEngineProtocol {}

extension ActiveAppTracker: ActiveAppTracking {}

extension PermissionManager: AccessibilityPermissionChecking {}
