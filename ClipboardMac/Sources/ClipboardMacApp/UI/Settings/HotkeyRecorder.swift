import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorder: View {
    let title: String
    let identifier: String
    @Binding var value: HotkeyPreference

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Text(isRecording ? "Type Shortcut…" : HotkeyDisplay.string(for: value))
                    .monospaced()
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                    .accessibilityIdentifier("\(identifier).display")
                    .accessibilityLabel("\(title) shortcut")
                    .accessibilityValue(isRecording ? "Recording" : HotkeyDisplay.string(for: value))

                Button(isRecording ? "Stop" : "Record") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .accessibilityIdentifier("\(identifier).recordButton")
                .accessibilityLabel(isRecording ? "Stop recording \(title) shortcut" : "Record \(title) shortcut")
            }
        }
        .accessibilityIdentifier(identifier)
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = event.keyCode
            if keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.intersection([.command, .option, .control, .shift]).isEmpty {
                NSSound.beep()
                return nil
            }
            value = HotkeyPreference(keyCode: keyCode, modifiers: flags)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
