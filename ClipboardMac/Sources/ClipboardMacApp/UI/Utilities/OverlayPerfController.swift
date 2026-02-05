import Foundation

@MainActor
final class OverlayPerfController: ObservableObject {
#if DEBUG
    private let frameMonitor = OverlayFrameMonitor()

    func start() {
        OverlayPerfMetrics.shared.start()
        frameMonitor.start()
    }

    func stop() {
        frameMonitor.stop()
        OverlayPerfMetrics.shared.stop()
    }
#else
    func start() {}
    func stop() {}
#endif
}

