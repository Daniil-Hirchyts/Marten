import Foundation

#if DEBUG
import CoreVideo

final class OverlayFrameMonitor {
    private var displayLink: CVDisplayLink?
    private var lastVideoTime: Int64 = 0
    private var lastVideoTimeScale: Int32 = 0

    func start() {
        guard displayLink == nil else { return }
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        displayLink = link
        guard let displayLink else { return }

        CVDisplayLinkSetOutputCallback(displayLink, { _, inNow, _, _, _, ctx in
            let monitor = Unmanaged<OverlayFrameMonitor>.fromOpaque(ctx!).takeUnretainedValue()
            monitor.handleFrame(now: inNow.pointee)
            return kCVReturnSuccess
        }, Unmanaged.passUnretained(self).toOpaque())

        CVDisplayLinkStart(displayLink)
    }

    func stop() {
        guard let displayLink else { return }
        CVDisplayLinkStop(displayLink)
        self.displayLink = nil
        lastVideoTime = 0
        lastVideoTimeScale = 0
    }

    private func handleFrame(now: CVTimeStamp) {
        let videoTime = now.videoTime
        let scale = now.videoTimeScale

        guard videoTime > 0, scale > 0 else { return }
        if lastVideoTime == 0 {
            lastVideoTime = videoTime
            lastVideoTimeScale = scale
            return
        }

        let delta = videoTime - lastVideoTime
        let seconds = Double(delta) / Double(scale)
        lastVideoTime = videoTime
        lastVideoTimeScale = scale

        DispatchQueue.main.async {
            OverlayPerfMetrics.shared.recordFrame(deltaSeconds: seconds)
        }
    }
}
#endif

