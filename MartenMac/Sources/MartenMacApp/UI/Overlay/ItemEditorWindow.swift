import AppKit
import MartenCore
import MartenMacServices
import SwiftUI

@MainActor
final class ItemEditorWindowController: NSObject {
    private let window: NSWindow
    private var isVisible = false
    private var onSave: ((String) -> Void)?
    private var onClose: (() -> Void)?
    private let clipItemEditor: any ClipItemEditing
    private let appleIntelligence: any AppleIntelligenceTextTransforming

    init(
        clipItemEditor: any ClipItemEditing,
        appleIntelligence: any AppleIntelligenceTextTransforming
    ) {
        self.clipItemEditor = clipItemEditor
        self.appleIntelligence = appleIntelligence
        let initialFrame = NSRect(x: 0, y: 0, width: 720, height: 520)
        window = ItemEditorWindow(
            contentRect: initialFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 360)
        window.maxSize = NSSize(width: 1200, height: 900)
        window.backgroundColor = .windowBackgroundColor
        window.level = .popUpMenu
        
        super.init()
        window.delegate = self
    }

    func show(item: ClipItem, onSave: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        guard !isVisible else { return }

        self.onSave = onSave
        self.onClose = onClose

        let contentView = ItemEditorContentView(
            item: item,
            clipItemEditor: clipItemEditor,
            appleIntelligence: appleIntelligence,
            mode: .edit,
            onCancel: { [weak self] in
                self?.hide()
            },
            onSave: { [weak self] newText in
                onSave(newText)
                self?.hide()
            }
        )

        window.title = Self.windowTitle(for: item)
        installContent(contentView)
        present()
    }

    func showNewTextItem(onSave: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        guard !isVisible else { return }

        self.onSave = onSave
        self.onClose = onClose

        let contentView = ItemEditorContentView(
            item: nil,
            clipItemEditor: clipItemEditor,
            appleIntelligence: appleIntelligence,
            mode: .createNew,
            onCancel: { [weak self] in
                self?.hide()
            },
            onSave: { [weak self] newText in
                onSave(newText)
                self?.hide()
            }
        )

        window.title = "New Text Item"
        installContent(contentView)
        present()
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.window.orderOut(nil)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onClose?()
                self.onSave = nil
                self.onClose = nil
            }
        }
    }

    // MARK: - Private

    private func installContent(_ contentView: some View) {
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        window.center()
    }

    private func present() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        isVisible = true
    }

    private static func windowTitle(for item: ClipItem) -> String {
        switch item.itemTypeValue {
        case .image:
            if let customTitle = item.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                !customTitle.isEmpty
            {
                return customTitle
            }
            if let primaryText = item.primaryText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !primaryText.isEmpty {
                return primaryText
            }
            if let path = ItemEditorHelpers.fileURLPath(from: item) {
                return URL(fileURLWithPath: path).lastPathComponent
            }
            return "Image"
        case .file:
            return item.managedFileDisplayName ?? "File"
        case .code:
            return "Code"
        case .url:
            return "URL"
        case .color:
            return "Color"
        case .richText:
            return "Rich Text"
        case .text:
            return "Text"
        case .mixed:
            return "Mixed Content"
        }
    }
}

extension ItemEditorWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isVisible = false
        onClose?()
        onSave = nil
        onClose = nil
    }
}

private final class ItemEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape to close
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }
}
