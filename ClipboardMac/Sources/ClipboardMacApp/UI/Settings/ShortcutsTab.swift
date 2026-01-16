import SwiftUI

struct ShortcutsTab: View {
    @StateObject private var model = HotkeyPreferencesStore()

    var body: some View {
        Form {
            Section("Global Shortcuts") {
                HotkeyRecorder(
                    title: "Show Clipboard",
                    identifier: "settings.hotkey.showClipboard",
                    value: $model.showClipboard
                )
            }

            Section("Quick Paste") {
                ForEach(1...9, id: \.self) { index in
                    HotkeyRecorder(
                        title: "Quick Paste \(index)",
                        identifier: "settings.hotkey.quickPaste\(index)",
                        value: quickPasteBinding(index)
                    )
                }
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
        .onChange(of: model.showClipboard) { _ in
            model.save()
        }
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
