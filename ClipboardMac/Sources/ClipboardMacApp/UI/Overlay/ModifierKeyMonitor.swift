import AppKit
import Foundation

final class ModifierKeyMonitor: ObservableObject {
    @Published private(set) var isShiftPressed = false
    @Published private(set) var isCommandPressed = false

    private var localMonitor: Any?
    private var globalMonitor: Any?

    func start() {
        stop()
        updateFlags(NSEvent.modifierFlags)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateFlags(event.modifierFlags)
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateFlags(event.modifierFlags)
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func updateFlags(_ flags: NSEvent.ModifierFlags) {
        let isShift = flags.contains(.shift)
        if isShiftPressed != isShift {
            isShiftPressed = isShift
        }
        
        let isCommand = flags.contains(.command)
        if isCommandPressed != isCommand {
            isCommandPressed = isCommand
        }
    }
}
