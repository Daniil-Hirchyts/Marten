import AppKit
import Carbon.HIToolbox
import ClipboardCore
import Foundation

public enum PasteFormat {
    case preserved
    case plainText
}

public enum PasteEngineError: Error {
    case accessibilityPermissionDenied
    case emptyStack
    case missingPlainText
}

public final class PasteEngine {
    private let pasteboard: NSPasteboard
    private let activeAppTracker: ActiveAppTracker
    private let assetStore: AssetStore
    private let permissionManager: PermissionManager

    public init(
        pasteboard: NSPasteboard = .general,
        activeAppTracker: ActiveAppTracker = ActiveAppTracker(),
        assetStore: AssetStore = .shared,
        permissionManager: PermissionManager = PermissionManager()
    ) {
        self.pasteboard = pasteboard
        self.activeAppTracker = activeAppTracker
        self.assetStore = assetStore
        self.permissionManager = permissionManager
    }

    public func recordFrontmostApp() {
        activeAppTracker.recordFrontmostApp()
    }

    public func pasteItem(_ item: ClipItem, format: PasteFormat = .preserved) async throws {
        try await writeToPasteboard(item, format: format)
        await MainActor.run {
            activeAppTracker.reactivateRecordedApp()
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        try await sendPasteKeystroke()
    }

    public func pasteStack(_ session: StackSession, format: PasteFormat = .preserved) async throws {
        let entries = session.entries?.sorted { $0.position < $1.position } ?? []
        guard !entries.isEmpty else {
            throw PasteEngineError.emptyStack
        }

        await MainActor.run {
            activeAppTracker.reactivateRecordedApp()
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        for (index, entry) in entries.enumerated() {
            guard let item = entry.clipItem else { continue }

            try await writeToPasteboard(item, format: format)
            try await sendPasteKeystroke()

            if index < entries.count - 1, session.modeValue == .combined {
                try await insertSeparator(session.separator)
            }

            if index < entries.count - 1 {
                try await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    private func writeToPasteboard(_ item: ClipItem, format: PasteFormat) async throws {
        try await MainActor.run {
            NotificationCenter.default.post(name: .clipboardWillWrite, object: nil)
            pasteboard.clearContents()

            switch format {
            case .plainText:
                guard let plainText = item.plainTextContent, !plainText.isEmpty else {
                    throw PasteEngineError.missingPlainText
                }
                pasteboard.setString(plainText, forType: .string)
            case .preserved:
                let pasteboardItem = NSPasteboardItem()
                let sorted = item.representations?.sorted { $0.displayOrder < $1.displayOrder } ?? []
                for rep in sorted {
                    try addRepresentation(rep, to: pasteboardItem)
                }
                pasteboard.writeObjects([pasteboardItem])
            }
        }
    }

    private func addRepresentation(_ representation: ClipRepresentation, to pasteboardItem: NSPasteboardItem) throws {
        let type = NSPasteboard.PasteboardType(representation.uti)

        if let textData = representation.textData, let text = String(data: textData, encoding: .utf8) {
            switch representation.kindValue {
            case .fileURL:
                let url = URL(fileURLWithPath: text)
                pasteboardItem.setString(url.absoluteString, forType: type)
                return
            case .url:
                pasteboardItem.setString(text, forType: type)
                return
            case .plainText:
                pasteboardItem.setString(text, forType: .string)
                pasteboardItem.setString(text, forType: type)
                return
            default:
                break
            }
        }

        if let data = representation.binaryData {
            pasteboardItem.setData(data, forType: type)
            return
        }

        if let data = representation.textData {
            pasteboardItem.setData(data, forType: type)
            return
        }

        if let assetRef = representation.assetRef {
            let data = try assetStore.load(assetRef: assetRef, fileExtension: representation.fileExtension)
            pasteboardItem.setData(data, forType: type)
        }
    }

    private func insertSeparator(_ separator: String) async throws {
        await MainActor.run {
            NotificationCenter.default.post(name: .clipboardWillWrite, object: nil)
            pasteboard.clearContents()
            pasteboard.setString(separator, forType: .string)
        }
        try await sendPasteKeystroke()
    }

    private func sendPasteKeystroke() async throws {
        guard permissionManager.checkAccessibility(prompt: false) else {
            throw PasteEngineError.accessibilityPermissionDenied
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: true)
        cmdDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Command), keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
    }
}
