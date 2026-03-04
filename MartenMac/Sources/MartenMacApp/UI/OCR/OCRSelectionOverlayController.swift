import AppKit
import CoreGraphics
import Foundation
import MartenMacServices

@MainActor
private enum OCRSelectionCursorAsset {
    private static let cursorDirectory =
        "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Versions/A/Resources/cursors/screenshotselection"
    private static let defaultHotSpot = CGPoint(x: 15, y: 15)
    private static let accentPadding: CGFloat = 4
    private static let accentBlurRadius: CGFloat = 2
    private static let accentColor = NSColor.white

    private static let cursorImageAndHotSpot: (image: NSImage, hotSpot: CGPoint) = {
        let imagePath = (cursorDirectory as NSString).appendingPathComponent("cursor.pdf")
        guard let image = NSImage(contentsOfFile: imagePath) else {
            return (NSImage(size: .zero), defaultHotSpot)
        }

        if image.size == .zero {
            image.size = CGSize(width: 32, height: 32)
        }

        let infoPath = (cursorDirectory as NSString).appendingPathComponent("info.plist")
        let hotSpot = cursorHotSpot(at: infoPath)
        let cursorImage = imageWithAccent(from: image)
        let adjustedHotSpot = CGPoint(
            x: hotSpot.x + accentPadding,
            y: hotSpot.y + accentPadding
        )
        return (cursorImage, adjustedHotSpot)
    }()

    static let selectionCursor: NSCursor = {
        let asset = cursorImageAndHotSpot
        guard asset.image.size != .zero else { return .crosshair }
        return NSCursor(image: asset.image, hotSpot: asset.hotSpot)
    }()

    static let selectionCursorImage: NSImage? = {
        let asset = cursorImageAndHotSpot
        return asset.image.size == .zero ? nil : asset.image
    }()

    static let selectionCursorHotSpot: CGPoint = cursorImageAndHotSpot.hotSpot

    private static func cursorHotSpot(at infoPath: String) -> CGPoint {
        guard
            let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any]
        else {
            return defaultHotSpot
        }

        let hotX = (info["hotx-scaled"] as? NSNumber)?.doubleValue
            ?? (info["hotx"] as? NSNumber)?.doubleValue
        let hotY = (info["hoty-scaled"] as? NSNumber)?.doubleValue
            ?? (info["hoty"] as? NSNumber)?.doubleValue

        guard let hotX, let hotY else {
            return defaultHotSpot
        }
        return CGPoint(x: hotX, y: hotY)
    }

    private static func imageWithAccent(from sourceImage: NSImage) -> NSImage {
        let paddedSize = CGSize(
            width: sourceImage.size.width + (accentPadding * 2),
            height: sourceImage.size.height + (accentPadding * 2)
        )
        let drawRect = CGRect(
            x: accentPadding,
            y: accentPadding,
            width: sourceImage.size.width,
            height: sourceImage.size.height
        )
        let sourceRect = CGRect(origin: .zero, size: sourceImage.size)

        let image = NSImage(size: paddedSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        CGRect(origin: .zero, size: paddedSize).fill()

        let accent = NSShadow()
        accent.shadowBlurRadius = accentBlurRadius
        accent.shadowOffset = .zero
        accent.shadowColor = accentColor

        NSGraphicsContext.saveGraphicsState()
        accent.set()
        sourceImage.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        sourceImage.draw(in: drawRect, from: sourceRect, operation: .sourceOver, fraction: 1)

        return image
    }
}

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
    func showProcessingState()
    func endSession()
}

@MainActor
final class OCRSelectionOverlayController: OCRSelectionPresenting {
    enum Result {
        case selected(OCRSelection)
        case cancelled
    }

    private var windows: [OCRSelectionWindow] = []
    private var completion: ((Result) -> Void)?
    private var didEndSession = true
    private var sessionID: UInt64 = 0
    private var keyDownMonitor: Any?
    private var didPushSelectionCursor = false

    func beginSelection(
        mode: OCRCaptureMode,
        staticSnapshots: [CGDirectDisplayID: CGImage],
        completion: @escaping (Result) -> Void
    ) {
        endSession()
        sessionID &+= 1
        let currentSessionID = sessionID
        self.completion = completion
        didEndSession = false
        OCRSelectionSessionState.setActive(true)

        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let displayID = screen.displayID else { return nil }
            return (screen, displayID)
        }
        guard !screens.isEmpty else {
            finish(result: .cancelled, notifyCompletion: true)
            return
        }

        var createdWindows: [OCRSelectionWindow] = []
        for (screen, displayID) in screens {
            let window = OCRSelectionWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.becomesKeyOnlyIfNeeded = true
            window.acceptsMouseMovedEvents = true
            window.ignoresMouseEvents = false
            window.sharingType = .none

            let view = OCRSelectionOverlayView(
                frame: CGRect(origin: .zero, size: screen.frame.size),
                displayID: displayID,
                displaySizeInPoints: screen.frame.size,
                backingScaleFactor: screen.backingScaleFactor
            )

            view.onSelection = { [weak self] selection in
                self?.finish(result: .selected(selection), notifyCompletion: true, sessionID: currentSessionID)
            }
            view.onCancel = { [weak self] in
                self?.finish(result: .cancelled, notifyCompletion: true, sessionID: currentSessionID)
            }

            window.contentView = view
            window.onEscape = { [weak self] in
                self?.finish(result: .cancelled, notifyCompletion: true, sessionID: currentSessionID)
            }
            window.onRightClick = { [weak self] in
                self?.finish(result: .cancelled, notifyCompletion: true, sessionID: currentSessionID)
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
                view.refreshCursorRects()
            }
        }
        let keyWindow = createdWindows.first { $0.frame.contains(currentMouseLocation) }
            ?? createdWindows.first
        keyWindow?.makeKeyAndOrderFront(nil)
        if let contentView = keyWindow?.contentView {
            keyWindow?.makeFirstResponder(contentView)
        }
        pushSelectionCursor()
        if let activeView = keyWindow?.contentView as? OCRSelectionOverlayView {
            activeView.refreshCursorRects()
            activeView.applySelectionCursorImmediately()
        }
        reassertSelectionCursorSoon()
        installKeyDownMonitor(for: currentSessionID)
    }

    func showProcessingState() {}

    func endSession() {
        finish(notifyCompletion: false)
    }

    private func finish(
        result: Result? = nil,
        notifyCompletion: Bool,
        sessionID expectedSessionID: UInt64? = nil
    ) {
        if let expectedSessionID, expectedSessionID != sessionID {
            return
        }
        guard !didEndSession else { return }

        didEndSession = true
        OCRSelectionSessionState.setActive(false)
        removeKeyDownMonitor()
        popSelectionCursor()

        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()

        let callback = completion
        completion = nil
        if notifyCompletion, let result {
            callback?(result)
        }
    }

    private func installKeyDownMonitor(for sessionID: UInt64) {
        removeKeyDownMonitor()
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.keyCode == 53 else { return event }
            self.finish(result: .cancelled, notifyCompletion: true, sessionID: sessionID)
            return nil
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }
    }

    private func pushSelectionCursor() {
        guard !didPushSelectionCursor else { return }
        OCRSelectionCursorAsset.selectionCursor.push()
        OCRSelectionCursorAsset.selectionCursor.set()
        didPushSelectionCursor = true
    }

    private func popSelectionCursor() {
        guard didPushSelectionCursor else { return }
        NSCursor.pop()
        didPushSelectionCursor = false
    }

    private func reassertSelectionCursorSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.didPushSelectionCursor else { return }
            OCRSelectionCursorAsset.selectionCursor.set()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.didPushSelectionCursor else { return }
            OCRSelectionCursorAsset.selectionCursor.set()
        }
    }
}

private final class OCRSelectionWindow: NSPanel {
    var onEscape: (() -> Void)?
    var onRightClick: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }

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

    let representedDisplayID: CGDirectDisplayID

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
        displayID: CGDirectDisplayID,
        displaySizeInPoints: CGSize,
        backingScaleFactor: CGFloat
    ) {
        self.representedDisplayID = displayID
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
            options: [.activeAlways, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        primePointerLocation(using: NSEvent.mouseLocation)
        refreshCursorRects()
        applySelectionCursorImmediately()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshCursorRects()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: OCRSelectionCursorAsset.selectionCursor)
    }

    override func cursorUpdate(with event: NSEvent) {
        applySelectionCursorImmediately()
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
        NSColor.clear.setFill()
        bounds.fill()

        if let selectionRect {
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            NSColor(calibratedWhite: 0.82, alpha: 0.18).setFill()
            selectionPath.fill()

            let outline = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
            NSColor(calibratedWhite: 0.92, alpha: 0.96).setStroke()
            outline.lineWidth = 2
            outline.stroke()

            let dash = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
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
        applySelectionCursorImmediately()
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        applySelectionCursorImmediately()
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
        applySelectionCursorImmediately()
        playHaptic()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPoint else { return }

        currentPoint = clampedPoint(convert(event.locationInWindow, from: nil))
        applySelectionCursorImmediately()
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
        guard dragStartPoint != nil, currentPoint != nil else {
            onCancel?()
            return
        }

        defer {
            self.dragStartPoint = nil
            self.lastHapticStep = nil
            self.lastHapticTimestamp = 0
        }

        guard let selectionGeometry else {
            onCancel?()
            return
        }
        let rect = selectionGeometry.captureRect

        guard rect.width >= 4, rect.height >= 4 else {
            onCancel?()
            return
        }

        let selection = OCRSelection(
            displayID: representedDisplayID,
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

    func refreshCursorRects() {
        discardCursorRects()
        window?.invalidateCursorRects(for: self)
        applySelectionCursorImmediately()
    }

    func applySelectionCursorImmediately() {
        OCRSelectionCursorAsset.selectionCursor.set()
    }

    private var selectionRect: CGRect? {
        selectionGeometry?.displayRect
    }

    private var selectionGeometry: (displayRect: CGRect, captureRect: CGRect)? {
        guard let dragStartPoint, let currentPoint else { return nil }

        let displayRect = CGRect(
            x: min(dragStartPoint.x, currentPoint.x),
            y: min(dragStartPoint.y, currentPoint.y),
            width: abs(dragStartPoint.x - currentPoint.x),
            height: abs(dragStartPoint.y - currentPoint.y)
        )
        guard displayRect.width > 0, displayRect.height > 0 else { return nil }

        return (displayRect, displayRect.integral)
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
            text = "\(Int(w))x\(Int(h))"
        } else {
            let globalPoint = CGPoint(
                x: window.frame.origin.x + localPoint.x,
                y: window.frame.origin.y + localPoint.y
            )
            text = "\(Int(globalPoint.x)),\(Int(globalPoint.y))"
        }
        let textAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
        ]
        let size = (text as NSString).size(withAttributes: textAttributes)
        let padding = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        let badgeSize = CGSize(
            width: size.width + padding.left + padding.right,
            height: size.height + padding.top + padding.bottom
        )

        var origin = CGPoint(x: localPoint.x + 6, y: localPoint.y + 6)
        origin.x = min(origin.x, bounds.width - badgeSize.width - 6)
        origin.y = min(origin.y, bounds.height - badgeSize.height - 6)
        origin.x = max(origin.x, 6)
        origin.y = max(origin.y, 6)

        let badgeRect = CGRect(origin: origin, size: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.82).setFill()
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
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
