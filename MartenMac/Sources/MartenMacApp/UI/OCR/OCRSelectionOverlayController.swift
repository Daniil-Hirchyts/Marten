import AppKit
import MartenMacServices
import CoreGraphics
import Foundation

struct OCRSelection {
    let displayID: CGDirectDisplayID
    let rectInDisplayPoints: CGRect
    let displaySizeInPoints: CGSize
    let backingScaleFactor: CGFloat
}

@MainActor
enum OCRSelectionSessionState {
    static let didChangeNotification = Notification.Name("OCRSelectionSessionState.didChange")

    private(set) static var isActive = false

    static func setActive(_ newValue: Bool) {
        guard isActive != newValue else { return }
        isActive = newValue
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

@MainActor
protocol OCRSelectionPresenting: AnyObject {
    func beginSelection(
        mode: OCRCaptureMode,
        staticSnapshots: [CGDirectDisplayID: CGImage],
        completion: @escaping (OCRSelectionOverlayController.Result) -> Void
    )
    func cancelSelection()
}

@MainActor
final class OCRSelectionOverlayController: OCRSelectionPresenting {
    enum Result {
        case selected(OCRSelection)
        case cancelled
    }

    private var windows: [OCRSelectionWindow] = []
    private var completion: ((Result) -> Void)?
    private var didFinish = false
    private var sessionID: UInt64 = 0
    private var keyDownMonitor: Any?

    func beginSelection(
        mode: OCRCaptureMode,
        staticSnapshots: [CGDirectDisplayID: CGImage],
        completion: @escaping (Result) -> Void
    ) {
        cancelSelection()
        sessionID &+= 1
        let currentSessionID = sessionID
        self.completion = completion
        didFinish = false
        OCRSelectionSessionState.setActive(true)

        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let displayID = screen.displayID else { return nil }
            return (screen, displayID)
        }
        guard !screens.isEmpty else {
            finish(.cancelled)
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        var createdWindows: [OCRSelectionWindow] = []
        for (screen, displayID) in screens {
            let window = OCRSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false

            let view = OCRSelectionOverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                mode: mode,
                staticSnapshot: staticSnapshots[displayID],
                displayID: displayID,
                displaySizeInPoints: screen.frame.size,
                backingScaleFactor: screen.backingScaleFactor
            )

            view.onSelection = { [weak self] selection in
                self?.finish(.selected(selection), sessionID: currentSessionID)
            }
            view.onCancel = { [weak self] in
                self?.finish(.cancelled, sessionID: currentSessionID)
            }

            window.contentView = view
            window.onEscape = { [weak self] in
                self?.finish(.cancelled, sessionID: currentSessionID)
            }
            window.onRightClick = { [weak self] in
                self?.finish(.cancelled, sessionID: currentSessionID)
            }

            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
            createdWindows.append(window)
        }

        windows = createdWindows
        let currentMouseLocation = NSEvent.mouseLocation
        for window in createdWindows {
            window.orderFrontRegardless()
            if let view = window.contentView as? OCRSelectionOverlayView {
                view.primePointerLocation(using: currentMouseLocation)
            }
        }
        let keyWindow = createdWindows.first { $0.frame.contains(currentMouseLocation) }
            ?? createdWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        if let contentView = keyWindow?.contentView {
            keyWindow?.makeFirstResponder(contentView)
        }
        installKeyDownMonitor(for: currentSessionID)
    }

    func cancelSelection() {
        finish(.cancelled, force: true)
    }

    private func finish(_ result: Result, force: Bool = false, sessionID expectedSessionID: UInt64? = nil) {
        if let expectedSessionID, expectedSessionID != sessionID {
            return
        }
        guard !didFinish || force else { return }
        didFinish = true
        OCRSelectionSessionState.setActive(false)
        removeKeyDownMonitor()

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        let callback = completion
        completion = nil
        if !force {
            callback?(result)
        }
    }

    private func installKeyDownMonitor(for sessionID: UInt64) {
        removeKeyDownMonitor()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }
            self.finish(.cancelled, sessionID: sessionID)
            return nil
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }
}

private final class OCRSelectionWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onRightClick: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

private final class OCRSelectionOverlayView: NSView {
    var onSelection: ((OCRSelection) -> Void)?
    var onCancel: (() -> Void)?

    private let mode: OCRCaptureMode
    private let staticSnapshot: CGImage?
    private let displayID: CGDirectDisplayID
    private let displaySizeInPoints: CGSize
    private let backingScaleFactor: CGFloat

    private var trackingArea: NSTrackingArea?
    private var dragStartPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var lastHapticStep: (width: Int, height: Int)?
    private var lastHapticTimestamp: TimeInterval = 0
    private let hapticStepSize: CGFloat = 10
    private let minimumHapticInterval: TimeInterval = 0.03

    override var acceptsFirstResponder: Bool { true }

    init(
        frame frameRect: CGRect,
        mode: OCRCaptureMode,
        staticSnapshot: CGImage?,
        displayID: CGDirectDisplayID,
        displaySizeInPoints: CGSize,
        backingScaleFactor: CGFloat
    ) {
        self.mode = mode
        self.staticSnapshot = staticSnapshot
        self.displayID = displayID
        self.displaySizeInPoints = displaySizeInPoints
        self.backingScaleFactor = backingScaleFactor
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        primePointerLocation(using: NSEvent.mouseLocation)
    }

    func primePointerLocation(using globalMouseLocation: CGPoint) {
        guard let window else { return }
        let localPoint = CGPoint(
            x: globalMouseLocation.x - window.frame.minX,
            y: globalMouseLocation.y - window.frame.minY
        )
        currentPoint = bounds.contains(localPoint) ? clampedPoint(localPoint) : nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if mode == .staticSnapshot, let staticSnapshot {
            drawSnapshot(staticSnapshot, in: bounds)
        } else {
            NSColor.clear.setFill()
            bounds.fill()
        }

        NSColor.black.withAlphaComponent(0.5).setFill()
        bounds.fill()

        if let selectionRect {
            if mode == .liveScreen, let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setBlendMode(.clear)
                context.fill(selectionRect)
                context.restoreGState()
            } else if mode == .staticSnapshot, let staticSnapshot,
                let context = NSGraphicsContext.current?.cgContext
            {
                context.saveGState()
                context.clip(to: selectionRect)
                drawSnapshot(staticSnapshot, in: bounds)
                context.restoreGState()
            }

            let outline = NSBezierPath(rect: selectionRect)
            NSColor.white.withAlphaComponent(0.95).setStroke()
            outline.lineWidth = 2
            outline.stroke()

            let dash = NSBezierPath(rect: selectionRect)
            dash.setLineDash([6, 4], count: 2, phase: 0)
            NSColor.black.withAlphaComponent(0.45).setStroke()
            dash.lineWidth = 1
            dash.stroke()
        }

        if let pointer = currentPoint {
            drawCoordinateBadge(at: pointer)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        currentPoint = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        dragStartPoint = point
        currentPoint = point
        lastHapticStep = (0, 0)
        lastHapticTimestamp = ProcessInfo.processInfo.systemUptime
        playHaptic()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint else { return }
        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        let step = hapticStep(for: currentPoint ?? dragStartPoint, from: dragStartPoint)
        if let previousStep = lastHapticStep, step != previousStep, (step.width > 0 || step.height > 0) {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastHapticTimestamp >= minimumHapticInterval {
                playHaptic()
                lastHapticTimestamp = now
            }
        }
        lastHapticStep = step
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard
            let dragStartPoint,
            let currentPoint = currentPoint
        else {
            onCancel?()
            return
        }

        defer {
            self.dragStartPoint = nil
            self.lastHapticStep = nil
            self.lastHapticTimestamp = 0
        }

        let rect = CGRect(
            x: min(dragStartPoint.x, currentPoint.x),
            y: min(dragStartPoint.y, currentPoint.y),
            width: abs(dragStartPoint.x - currentPoint.x),
            height: abs(dragStartPoint.y - currentPoint.y)
        ).integral

        guard rect.width >= 4, rect.height >= 4 else {
            onCancel?()
            return
        }

        let selection = OCRSelection(
            displayID: displayID,
            rectInDisplayPoints: rect,
            displaySizeInPoints: displaySizeInPoints,
            backingScaleFactor: backingScaleFactor
        )
        playHaptic()
        onSelection?(selection)
    }

    override func rightMouseDown(with event: NSEvent) {
        lastHapticStep = nil
        lastHapticTimestamp = 0
        onCancel?()
    }

    private var selectionRect: CGRect? {
        guard let dragStartPoint, let currentPoint else { return nil }
        let rect = CGRect(
            x: min(dragStartPoint.x, currentPoint.x),
            y: min(dragStartPoint.y, currentPoint.y),
            width: abs(dragStartPoint.x - currentPoint.x),
            height: abs(dragStartPoint.y - currentPoint.y)
        )
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func drawCoordinateBadge(at localPoint: CGPoint) {
        guard let window else { return }

        let text: String
        if let dragStart = dragStartPoint {
            let w = abs(dragStart.x - localPoint.x)
            let h = abs(dragStart.y - localPoint.y)
            text = "W:\(Int(w))  H:\(Int(h))"
        } else {
            let globalPoint = CGPoint(
                x: window.frame.origin.x + localPoint.x,
                y: window.frame.origin.y + localPoint.y
            )
            text = "x:\(Int(globalPoint.x))  y:\(Int(globalPoint.y))"
        }
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: textAttributes)
        let padding = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        let badgeSize = CGSize(
            width: size.width + padding.left + padding.right,
            height: size.height + padding.top + padding.bottom
        )

        var origin = CGPoint(x: localPoint.x + 8, y: localPoint.y + 8)
        origin.x = min(origin.x, bounds.width - badgeSize.width - 8)
        origin.y = min(origin.y, bounds.height - badgeSize.height - 8)
        origin.x = max(origin.x, 8)
        origin.y = max(origin.y, 8)

        let badgeRect = CGRect(origin: origin, size: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
        NSColor.black.setFill()
        badgePath.fill()

        let textOrigin = CGPoint(
            x: badgeRect.minX + padding.left,
            y: badgeRect.minY + padding.bottom
        )
        (text as NSString).draw(at: textOrigin, withAttributes: textAttributes)
    }

    private func hapticStep(for point: CGPoint, from origin: CGPoint) -> (width: Int, height: Int) {
        let widthSteps = Int(abs(point.x - origin.x) / hapticStepSize)
        let heightSteps = Int(abs(point.y - origin.y) / hapticStepSize)
        return (widthSteps, heightSteps)
    }

    private func playHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func drawSnapshot(_ snapshot: CGImage, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(snapshot, in: rect)
        context.restoreGState()
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
