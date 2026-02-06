import AppKit
import ClipboardCore
import ClipboardMacServices
import SwiftUI

@MainActor
final class ItemEditorWindowController {
    private let panel: NSPanel
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
        panel = ItemEditorPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isMovable = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.minSize = NSSize(width: 480, height: 360)
        panel.maxSize = NSSize(width: 1200, height: 900)
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
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        // Make hosting view fully transparent - no background
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = panel.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        isVisible = true
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
        .ignoresSafeArea()

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]
        // Make hosting view fully transparent - no background
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = panel.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        isVisible = true
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.onClose?()
                self.onSave = nil
                self.onClose = nil
            }
        }
    }
}

private final class ItemEditorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(contentView)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }

        super.keyDown(with: event)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if let contentView = contentView {
            contentView.frame = NSRect(x: 0, y: 0, width: frameRect.width, height: frameRect.height)
        }
    }
}
