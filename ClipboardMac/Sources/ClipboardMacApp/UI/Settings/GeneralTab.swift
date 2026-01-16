import ClipboardCore
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @AppStorage("openAtLogin") private var openAtLogin = false
    @AppStorage("alwaysPastePlainText") private var alwaysPastePlainText = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("retentionPolicy") private var retentionPolicy = "month"

    @State private var showEraseConfirmation = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .accessibilityIdentifier("settings.toggle.openAtLogin")
                    .accessibilityLabel("Open at login")
                    .onChange(of: openAtLogin) { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }

            Section("Paste Behavior") {
                Toggle("Always paste as Plain Text", isOn: $alwaysPastePlainText)
                    .accessibilityIdentifier("settings.toggle.alwaysPastePlainText")
                    .accessibilityLabel("Always paste as plain text")

                Toggle("Sound effects", isOn: $soundEffectsEnabled)
                    .accessibilityIdentifier("settings.toggle.soundEffects")
                    .accessibilityLabel("Sound effects")
            }

            Section("History") {
                Picker("Keep History", selection: $retentionPolicy) {
                    Text("Day").tag("day")
                    Text("Week").tag("week")
                    Text("Month").tag("month")
                    Text("Year").tag("year")
                    Text("Forever").tag("forever")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.picker.historyRetention")
                .accessibilityLabel("Keep history")

                Button("Erase History...", role: .destructive) {
                    showEraseConfirmation = true
                }
                .accessibilityIdentifier("settings.button.eraseHistory")
                .accessibilityLabel("Erase history")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Erase History", isPresented: $showEraseConfirmation) {
            Button("Erase", role: .destructive) {
                ClipItemStore.deleteAll()
            }
            .accessibilityIdentifier("settings.button.eraseHistory.confirm")
            .accessibilityLabel("Confirm erase history")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.button.eraseHistory.cancel")
                .accessibilityLabel("Cancel erase history")
        } message: {
            Text("Are you sure you want to erase all history? This action cannot be undone.")
        }
    }
}
