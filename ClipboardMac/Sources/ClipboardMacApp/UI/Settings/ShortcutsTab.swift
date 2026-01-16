import SwiftUI

struct ShortcutsTab: View {
    @StateObject private var model = HotkeyPreferencesStore()

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HotkeyRecorder(
                    title: "Toggle Overlay",
                    identifier: "settings.hotkey.toggleOverlay",
                    value: $model.toggleOverlay
                )
                HotkeyRecorder(
                    title: "Paste Stack",
                    identifier: "settings.hotkey.pasteStack",
                    value: $model.togglePasteStack
                )
            }

            Section("Quick Paste") {
                Text("Use Cmd+1 through Cmd+9 to quickly paste items from your history.")
                    .foregroundStyle(.secondary)
            }

            Section("Modifiers") {
                Text("Hold Shift while pasting to paste as Plain Text.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults") {
                    model.resetToDefaults()
                    model.save()
                }
                .accessibilityIdentifier("settings.button.resetShortcuts")
                .accessibilityLabel("Reset shortcuts to defaults")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: model.toggleOverlay) { _ in
            model.save()
        }
        .onChange(of: model.togglePasteStack) { _ in
            model.save()
        }
    }
}
