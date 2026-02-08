import AppKit
import ClipboardCore
import ClipboardMacServices
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private struct ActivationObserverRecord {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private let panel: NSPanel
    private var viewModel: OverlayViewModel?
    private var isVisible = false
    private var outsideClickMonitor: Any?
    private var activationObservers: [ActivationObserverRecord] = []
    private weak var hotkeyManager: HotkeyManager?
    private let eventBroadcaster: any ClipboardEventBroadcaster
    private let screenSharingManager: ScreenSharingManager
    private let layoutSettings: OverlayLayoutSettings
    private var cancellables: Set<AnyCancellable> = []

    init(
        persistence: PersistenceController,
        pasteEngine: any PasteEngineProtocol,
        permissionManager: PermissionManager,
        hotkeyManager: HotkeyManager?,
        eventBroadcaster: any ClipboardEventBroadcaster,
        screenSharingManager: ScreenSharingManager,
        overlayDependencies: OverlayDependencies,
        rootView: AnyView? = nil
    ) {
        self.hotkeyManager = hotkeyManager
        self.eventBroadcaster = eventBroadcaster
        self.screenSharingManager = screenSharingManager
        self.layoutSettings = OverlayLayoutSettings()
        let initialFrame = NSRect(x: 0, y: 0, width: 800, height: 320)
        panel = OverlayPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
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
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none

        viewModel = nil

        if let rootView {
            panel.contentView = NSHostingView(rootView: rootView)
        } else {
            let model = OverlayViewModel(
                persistence: persistence,
                pasteEngine: pasteEngine,
                permissionManager: permissionManager,
                soundPlayer: overlayDependencies.soundPlayer,
                closeOverlayForPaste: { [weak self] completion in
                guard let self else {
                    completion()
                    return
                }
                self.hide(resetState: false, completion: completion)
            })
            viewModel = model
            let contentView = OverlayRootView(persistence: persistence, dependencies: overlayDependencies)
                .environment(\.managedObjectContext, persistence.viewContext)
                .environment(\.clipboardEventBroadcaster, eventBroadcaster)
                .environmentObject(model)
            panel.contentView = NSHostingView(rootView: contentView)
        }

        screenSharingManager.$isScreenSharingModeActive
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.isVisible, !self.screenSharingManager.shouldShowOverlay {
                    self.hide()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleLayoutSettingsChange()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleScreenParametersChange()
            }
            .store(in: &cancellables)

        DistributedNotificationCenter.default().publisher(
            for: Notification.Name("AppleInterfaceThemeChangedNotification")
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleAppearanceChange()
            }
            .store(in: &cancellables)
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
        guard !isVisible else { return }
        guard screenSharingManager.shouldShowOverlay else { return }
        guard let screen = preferredScreen() else { return }
        let targetFrame = frame(for: screen)
        let showOffset = OverlayFrameCalculator.showOffset(for: layoutSettings.overlayScreenEdge)
        let startFrame = targetFrame.offsetBy(dx: showOffset.width, dy: showOffset.height)

        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        panel.appearance = nil // Inherit current system appearance

        panel.orderFrontRegardless()
        panel.makeKey()

        startOutsideClickMonitor()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            // Snappy Ease-Out: Fast start, smooth but quick stop
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            // Slightly reduced delay to match faster animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                self.startActivationObservers()
            }
        }

        isVisible = true
        eventBroadcaster.publish(.overlayDidShow)
    }

    func hideForPaste(completion: (() -> Void)? = nil) {
        hide(resetState: false, completion: completion)
    }

    private func hide(resetState: Bool = true, completion: (() -> Void)? = nil) {
        guard isVisible else {
            completion?()
            return
        }
        isVisible = false

        let hideOffset = OverlayFrameCalculator.hideOffset(for: layoutSettings.overlayScreenEdge)
        let endFrame = panel.frame.offsetBy(dx: hideOffset.width, dy: hideOffset.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            // Snappy Ease-In: Smooth start, fast exit
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.7, 0, 0.84, 0)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.panel.orderOut(nil)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if resetState {
                    self.viewModel?.resetState()
                }
                self.stopOutsideClickMonitor()
                self.stopActivationObservers()
                completion?()
            }
        }
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let edge = layoutSettings.overlayScreenEdge
        let frame = OverlayFrameCalculator.frame(
            visibleFrame: screen.visibleFrame,
            edge: edge,
            preferredHorizontalSize: layoutSettings.horizontalSize,
            preferredVerticalSize: layoutSettings.verticalSize
        )
        return frame
    }

    private func handleLayoutSettingsChange() {
        guard isVisible else { return }
        updateVisibleFrame(animated: true)
    }

    private func handleScreenParametersChange() {
        guard isVisible else { return }
        updateVisibleFrame(animated: true)
    }

    private func handleAppearanceChange() {
        panel.appearance = nil
        panel.contentView?.needsDisplay = true
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }
        return panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func updateVisibleFrame(animated: Bool) {
        guard let screen = preferredScreen() else { return }
        let targetFrame = frame(for: screen)
        guard !rectsApproximatelyEqual(panel.frame, targetFrame, tolerance: 0.5) else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] _ in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            if self.isVisible, !self.panel.frame.contains(location) {
                Task { @MainActor in
                    self.hide()
                }
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func startActivationObservers() {
        guard activationObservers.isEmpty else { return }
        let workspaceNC = NSWorkspace.shared.notificationCenter
        let nc = NotificationCenter.default
        let currentPID = ProcessInfo.processInfo.processIdentifier

        activationObservers.append(
            ActivationObserverRecord(
                center: workspaceNC,
                token: workspaceNC.addObserver(
                    forName: NSWorkspace.didActivateApplicationNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self else { return }
                    guard
                        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication
                    else {
                        return
                    }
                    if app.processIdentifier != currentPID {
                        Task { @MainActor in
                            // Don't hide if authenticating for pinboard unlock
                            if self.viewModel?.isAuthenticating == true {
                                return
                            }
                            if self.isVisible {
                                self.hide()
                            }
                        }
                    }
                }
            )
        )

        activationObservers.append(
            ActivationObserverRecord(
                center: nc,
                token: nc.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        // Don't hide if authenticating for pinboard unlock
                        if self.viewModel?.isAuthenticating == true {
                            return
                        }
                        if self.isVisible {
                            self.hide()
                        }
                    }
                }
            )
        )
    }

    private func stopActivationObservers() {
        for record in activationObservers {
            record.center.removeObserver(record.token)
        }
        activationObservers.removeAll()
    }

}

private final class OverlayPanel: NSPanel {
    @MainActor var onReturnKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeKey() {
        super.becomeKey()
        makeFirstResponder(contentView)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            if let firstResponder = firstResponder,
                !(firstResponder is NSTextView || firstResponder is NSTextField)
            {
                if let handler = objc_getAssociatedObject(self, &ReturnKeyHandlerKey)
                    as? (() -> Void)
                {
                    handler()
                    return
                }
                onReturnKey?()
                return
            }
        }

        if event.keyCode == 49 {
            if let handler = objc_getAssociatedObject(self, &SpaceKeyHandlerKey)
                as? ((NSEvent) -> Bool)
            {
                if handler(event) {
                    return
                }
            }
        }

        if event.keyCode == 53 {
            if let handler = objc_getAssociatedObject(self, &EscapeKeyHandlerKey)
                as? ((NSEvent) -> Bool)
            {
                if handler(event) {
                    return
                }
            }
        }


        // Backspace (51) and forward delete (117) keys
        if event.keyCode == 51 || event.keyCode == 117 {
            if let handler = objc_getAssociatedObject(self, &DeleteKeyHandlerKey)
                as? ((NSEvent) -> Bool)
            {
                if handler(event) {
                    return
                }
            }
        }

        // Arrow keys: Left(123), Right(124), Down(125), Up(126)
        if (123...126).contains(event.keyCode) {
            if let handler = objc_getAssociatedObject(self, &ArrowKeyHandlerKey)
                as? ((NSEvent) -> Bool)
            {
                if handler(event) {
                    return
                }
            }
        }

        super.keyDown(with: event)
    }
}
