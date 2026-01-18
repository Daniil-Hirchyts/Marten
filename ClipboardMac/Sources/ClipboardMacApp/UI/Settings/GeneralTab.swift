import ClipboardCore
import ServiceManagement
import SwiftUI

struct GeneralSettingsContent: View {
    @AppStorage("openAtLogin") private var openAtLogin = false
    @AppStorage("alwaysPastePlainText") private var alwaysPastePlainText = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("retentionPolicy") private var retentionPolicy = "month"

    @State private var showEraseConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Startup Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Startup", icon: "power")

                SettingsCard {
                    SettingsToggleRow(
                        "Open at login",
                        description: "Launch Paste automatically when you log in",
                        isOn: $openAtLogin,
                        identifier: "settings.toggle.openAtLogin"
                    )
                    .onChange(of: openAtLogin) { newValue, _ in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                }
            }

            // Behavior Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Behavior", icon: "hand.tap")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsToggleRow(
                            "Always paste as Plain Text",
                            description: "Remove formatting when pasting",
                            isOn: $alwaysPastePlainText,
                            identifier: "settings.toggle.alwaysPastePlainText"
                        )

                        Divider()
                            .background(Color.white.opacity(0.1))

                        SettingsToggleRow(
                            "Sound effects",
                            description: "Play sounds for actions",
                            isOn: $soundEffectsEnabled,
                            identifier: "settings.toggle.soundEffects"
                        )
                    }
                }
            }

            // History Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("History", icon: "clock.arrow.circlepath")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Keep history for")
                                .font(.system(size: 13, weight: .medium))

                            Picker("", selection: $retentionPolicy) {
                                Text("1 Day").tag("day")
                                Text("1 Week").tag("week")
                                Text("1 Month").tag("month")
                                Text("1 Year").tag("year")
                                Text("Forever").tag("forever")
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.picker.historyRetention")
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Erase all history")
                                    .font(.system(size: 13, weight: .medium))
                                Text("This cannot be undone")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                showEraseConfirmation = true
                            } label: {
                                Text("Erase...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .accessibilityIdentifier("settings.button.eraseHistory")
                        }
                    }
                }
            }
        }
        .alert("Erase History", isPresented: $showEraseConfirmation) {
            Button("Erase", role: .destructive) {
                ClipItemStore.deleteAll()
            }
            .accessibilityIdentifier("settings.button.eraseHistory.confirm")

            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.button.eraseHistory.cancel")
        } message: {
            Text("Are you sure you want to erase all history? This action cannot be undone.")
        }
    }
}

// Keep the old tab for compatibility
struct GeneralTab: View {
    var body: some View {
        GeneralSettingsContent()
            .padding()
    }
}
