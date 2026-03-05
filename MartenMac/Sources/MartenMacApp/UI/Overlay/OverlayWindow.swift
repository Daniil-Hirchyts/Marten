import AppKit
import MartenCore
import MartenMacServices
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private struct ActivationObserverRecord {
        let center: NotificationCenter
        let token: NSObjectProtocol
    }

    private enum AnimationConstants {
        static let showDuration: TimeInterval = 0.22
        static let showTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.4, 1)
        static let hideDuration: TimeInterval = 0.16
        static let hideTimingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
        static let cursorShowDuration: TimeInterval = 0.24
        static let cursorShowTimingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        static let cursorHideDuration: TimeInterval = 0.18
        static let cursorHideTimingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        static let cursorMorphSize = CGSize(width: 180, height: 140)
        static let minimumDuration: TimeInterval = 0.16
        static let maximumDuration: TimeInterval = 0.34
        static let travelSpeedPointsPerSecond: CGFloat = 2_400
        static let activationObserverStartDelay: TimeInterval = 0.01
    }

    private let panel: NSPanel
    private var viewModel: OverlayViewModel?
    private var isVisible = false
    private var outsideClickMonitor: Any?
    private var activationObservers: [ActivationObserverRecord] = []
    private weak var hotkeyManager: HotkeyManager?
    private let eventBroadcaster: any MartenEventBroadcaster
    private let screenSharingManager: ScreenSharingManager
    private let layoutSettings: OverlayLayoutSettings
    private var lastCursorAnchor: CGPoint?
    private var cancellables: Set<AnyCancellable> = []

    init(
        persistence: PersistenceController,
        pasteEngine: any PasteEngineProtocol,
        permissionManager: PermissionManager,
        hotkeyManager: HotkeyManager?,
        eventBroadcaster: any MartenEventBroadcaster,
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
        panel.hasShadow = false
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
        let edge = layoutSettings.overlayScreenEdge
        let cursorLocation = NSEvent.mouseLocation
        let targetFrame: NSRect
        if edge == .cursor {
            targetFrame = OverlayFrameCalculator.cursorFrame(
                cursorLocation: cursorLocation,
                visibleFrame: screen.visibleFrame
            )
            lastCursorAnchor = cursorLocation
        } else {
            targetFrame = frame(for: screen)
            lastCursorAnchor = nil
        }
        let startFrame = showStartFrame(
            for: edge,
            targetFrame: targetFrame,
            visibleFrame: screen.visibleFrame,
            cursorLocation: cursorLocation
        )

        panel.setFrame(startFrame, display: true)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 0
        panel.appearance = nil // Inherit current system appearance

        panel.orderFrontRegardless()
        panel.makeKey()

        startOutsideClickMonitor()

        let showAnimation = showAnimation(for: edge)
        let showDuration = animationDuration(
            baseDuration: showAnimation.baseDuration,
            from: startFrame,
            to: targetFrame
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = showDuration
            context.timingFunction = showAnimation.timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(
                deadline: .now() + AnimationConstants.activationObserverStartDelay
            ) {
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

        let edge = layoutSettings.overlayScreenEdge
        let visibleFrame = panel.screen?.visibleFrame ?? preferredScreen()?.visibleFrame
        let endFrame: NSRect
        if let visibleFrame {
            endFrame = hideEndFrame(
                for: edge,
                currentFrame: panel.frame,
                visibleFrame: visibleFrame
            )
        } else {
            endFrame = panel.frame
        }

        let hideAnimation = hideAnimation(for: edge)
        let hideDuration = animationDuration(
            baseDuration: hideAnimation.baseDuration,
            from: panel.frame,
            to: endFrame
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hideDuration
            context.timingFunction = hideAnimation.timingFunction
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finalizeHide(resetState: resetState, completion: completion)
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

    private func showAnimation(
        for edge: OverlayScreenEdge
    ) -> (baseDuration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        if edge == .cursor {
            return (
                baseDuration: AnimationConstants.cursorShowDuration,
                timingFunction: AnimationConstants.cursorShowTimingFunction
            )
        }
        return (
            baseDuration: AnimationConstants.showDuration,
            timingFunction: AnimationConstants.showTimingFunction
        )
    }

    private func hideAnimation(
        for edge: OverlayScreenEdge
    ) -> (baseDuration: TimeInterval, timingFunction: CAMediaTimingFunction) {
        if edge == .cursor {
            return (
                baseDuration: AnimationConstants.cursorHideDuration,
                timingFunction: AnimationConstants.cursorHideTimingFunction
            )
        }
        return (
            baseDuration: AnimationConstants.hideDuration,
            timingFunction: AnimationConstants.hideTimingFunction
        )
    }

    private func animationDuration(
        baseDuration: TimeInterval,
        from startFrame: NSRect,
        to endFrame: NSRect
    ) -> TimeInterval {
        let dx = endFrame.midX - startFrame.midX
        let dy = endFrame.midY - startFrame.midY
        let distance = hypot(dx, dy)
        let travelDuration = TimeInterval(distance / AnimationConstants.travelSpeedPointsPerSecond)
        let candidate = max(baseDuration, travelDuration)
        return min(
            AnimationConstants.maximumDuration,
            max(AnimationConstants.minimumDuration, candidate)
        )
    }

    private func showStartFrame(
        for edge: OverlayScreenEdge,
        targetFrame: NSRect,
        visibleFrame: NSRect,
        cursorLocation: CGPoint
    ) -> NSRect {
        switch edge {
        case .cursor:
            return cursorMorphFrame(
                for: targetFrame,
                anchorPoint: cursorLocation,
                collapsedSize: AnimationConstants.cursorMorphSize
            )
        case .bottom, .top, .left, .right:
            return fullyOffscreenFrame(for: targetFrame, edge: edge, visibleFrame: visibleFrame)
        }
    }

    private func hideEndFrame(
        for edge: OverlayScreenEdge,
        currentFrame: NSRect,
        visibleFrame: NSRect
    ) -> NSRect {
        switch edge {
        case .cursor:
            let anchor = lastCursorAnchor ?? CGPoint(x: currentFrame.midX, y: currentFrame.midY)
            return cursorMorphFrame(
                for: currentFrame,
                anchorPoint: anchor,
                collapsedSize: AnimationConstants.cursorMorphSize
            )
        case .bottom, .top, .left, .right:
            return fullyOffscreenFrame(for: currentFrame, edge: edge, visibleFrame: visibleFrame)
        }
    }

    private func fullyOffscreenFrame(
        for frame: NSRect,
        edge: OverlayScreenEdge,
        visibleFrame: NSRect
    ) -> NSRect {
        var offscreenFrame = frame
        switch edge {
        case .bottom:
            offscreenFrame.origin.y = visibleFrame.minY - frame.height
        case .top:
            offscreenFrame.origin.y = visibleFrame.maxY
        case .left:
            offscreenFrame.origin.x = visibleFrame.minX - frame.width
        case .right:
            offscreenFrame.origin.x = visibleFrame.maxX
        case .cursor:
            break
        }
        return offscreenFrame
    }

    private func cursorMorphFrame(
        for targetFrame: NSRect,
        anchorPoint: CGPoint,
        collapsedSize: CGSize
    ) -> NSRect {
        let normalizedAnchorX = min(
            1,
            max(0, (anchorPoint.x - targetFrame.minX) / max(targetFrame.width, 1))
        )
        let normalizedAnchorY = min(
            1,
            max(0, (anchorPoint.y - targetFrame.minY) / max(targetFrame.height, 1))
        )

        return NSRect(
            x: anchorPoint.x - (collapsedSize.width * normalizedAnchorX),
            y: anchorPoint.y - (collapsedSize.height * normalizedAnchorY),
            width: collapsedSize.width,
            height: collapsedSize.height
        )
    }

    private func finalizeHide(resetState: Bool, completion: (() -> Void)?) {
        panel.orderOut(nil)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
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

    private func handleLayoutSettingsChange() {
        guard isVisible else { return }
        guard layoutSettings.overlayScreenEdge != .cursor else { return }
        updateVisibleFrame(animated: true)
    }

    private func handleScreenParametersChange() {
        guard isVisible else { return }
        guard layoutSettings.overlayScreenEdge != .cursor else { return }
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
                            // During native drag handoff we intentionally keep the panel alive
                            // but fully transparent; hiding here can invalidate the drag source.
                            if self.isTemporarilyTransparentForDrag {
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
                        // During native drag handoff we intentionally keep the panel alive
                        // but fully transparent; hiding here can invalidate the drag source.
                        if self.isTemporarilyTransparentForDrag {
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

    private var isTemporarilyTransparentForDrag: Bool {
        isVisible && panel.alphaValue <= 0.01
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

    // Keep animation endpoints intact even when they are fully off-screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

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
