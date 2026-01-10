import AppKit
import ClipboardCore
import SwiftUI

final class OverlayWindowController {
    private let panel: NSPanel
    private var isVisible = false

    init(
        persistence: PersistenceController = OverlayWindowController.defaultPersistence(),
        rootView: AnyView? = nil
    ) {
        let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 320)
        panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let contentView = rootView ?? AnyView(
            OverlayRootView()
                .environment(\.managedObjectContext, persistence.viewContext)
        )

        panel.contentView = NSHostingView(rootView: contentView)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    var isVisibleForTesting: Bool {
        isVisible
    }

    private func show() {
        guard let screen = NSScreen.main else { return }
        let targetFrame = frame(for: screen)
        let startFrame = targetFrame.offsetBy(dx: 0, dy: -20)

        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        }

        isVisible = true
    }

    private func hide() {
        let endFrame = panel.frame.offsetBy(dx: 0, dy: -20)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.isVisible = false
        }
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(visible.width * 0.8, 1200)
        let height: CGFloat = 320
        let x = visible.midX - (width / 2)
        let y = visible.minY + 40
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func defaultPersistence() -> PersistenceController {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return PersistenceController(inMemory: true)
        }
        return .shared
    }
}
