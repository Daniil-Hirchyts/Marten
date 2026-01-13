import ApplicationServices
import AppKit
import Foundation

public final class PermissionManager: ObservableObject {
    @Published public private(set) var hasAccessibility = false
    @Published public private(set) var hasInputMonitoring = false

    private var timer: Timer?

    public init() {
        refresh()
    }

    @discardableResult
    public func checkAccessibility(prompt: Bool = false) -> Bool {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ]
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibility = trusted
        return trusted
    }

    public func requestAccessibility() {
        _ = checkAccessibility(prompt: true)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    public func checkInputMonitoring(prompt: Bool = false) -> Bool {
        let granted = prompt ? CGRequestListenEventAccess() : CGPreflightListenEventAccess()
        hasInputMonitoring = granted
        return granted
    }

    public func refresh() {
        _ = checkAccessibility(prompt: false)
        _ = checkInputMonitoring(prompt: false)
    }

    public func startMonitoring(interval: TimeInterval = 1.0) {
        stopMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
}
