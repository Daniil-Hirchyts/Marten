import Carbon.HIToolbox
import SwiftUI

struct ShortcutsSettingsContent: View {
    @StateObject private var model = HotkeyPreferencesStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Global Shortcuts Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Global Shortcuts", icon: "globe")

                SettingsCard {
                    SettingsHotkeyRow(
                        title: "Show Clipboard",
                        identifier: "settings.hotkey.showClipboard",
                        value: $model.showClipboard
                    )
                }
            }

            // Quick Paste Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Quick Paste", icon: "bolt")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(1...9, id: \.self) { index in
                            if index > 1 {
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }

                            SettingsHotkeyRow(
                                title: "Quick Paste \(index)",
                                identifier: "settings.hotkey.quickPaste\(index)",
                                value: quickPasteBinding(index)
                            )
                        }
                    }
                }
            }

            // Tips Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Tips", icon: "lightbulb")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "shift")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 20, height: 20)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text("Hold Shift while pasting to paste as Plain Text")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Reset Button
            HStack {
                Spacer()

                Button {
                    model.resetToDefaults()
                    model.save()
                } label: {
                    Text("Reset to Defaults")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.button.resetShortcuts")
            }
        }
        .onChange(of: model.showClipboard) { _ in model.save() }
        .onChange(of: model.quickPaste1) { _ in model.save() }
        .onChange(of: model.quickPaste2) { _ in model.save() }
        .onChange(of: model.quickPaste3) { _ in model.save() }
        .onChange(of: model.quickPaste4) { _ in model.save() }
        .onChange(of: model.quickPaste5) { _ in model.save() }
        .onChange(of: model.quickPaste6) { _ in model.save() }
        .onChange(of: model.quickPaste7) { _ in model.save() }
        .onChange(of: model.quickPaste8) { _ in model.save() }
        .onChange(of: model.quickPaste9) { _ in model.save() }
    }

    private func quickPasteBinding(_ index: Int) -> Binding<HotkeyPreference> {
        Binding(
            get: { model.quickPaste(index) },
            set: { model.setQuickPaste(index, $0) }
        )
    }
}

// MARK: - Hotkey Row Component

struct SettingsHotkeyRow: View {
    let title: String
    let identifier: String
    @Binding var value: HotkeyPreference

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            HStack(spacing: 8) {
                Text(isRecording ? "Type shortcut..." : HotkeyDisplay.string(for: value))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(isRecording ? .secondary : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(isRecording ? 0.15 : 0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(isRecording ? 0.3 : 0.1),
                                lineWidth: 1
                            )
                    )

                Button {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    Text(isRecording ? "Stop" : "Record")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("\(identifier).recordButton")

                Button {
                    value = value.cleared()
                    stopRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!value.isEnabled)
                .accessibilityIdentifier("\(identifier).clearButton")
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

// Keep the old tab for compatibility
struct ShortcutsTab: View {
    var body: some View {
        ShortcutsSettingsContent()
            .padding()
    }
}
