import ClipboardCore
import ClipboardMacServices
import ServiceManagement
import SwiftUI

struct GeneralSettingsContent: View {
    @AppStorage("openAtLogin") private var openAtLogin = false
    @AppStorage("alwaysPastePlainText") private var alwaysPastePlainText = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false
    @AppStorage(OverlayLayoutSettings.Keys.overlayScreenEdge)
    private var overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue
    @AppStorage("retentionPolicy") private var retentionPolicy = "month"
    @AppStorage(PinboardSecuritySettings.unlockDurationSecondsKey)
    private var unlockDurationSeconds = PinboardSecuritySettings.defaultUnlockDurationSeconds
    @AppStorage(OCRSettingsKeys.defaultMode)
    private var ocrDefaultModeRawValue = OCRCaptureMode.staticSnapshot.rawValue
    @AppStorage(OCRSettingsKeys.preferredLanguage)
    private var ocrPreferredLanguageCode = OCRLanguage.auto.rawValue
    @AppStorage(OCRSettingsKeys.showCaptureNotification)
    private var ocrShowCaptureNotification = true

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
                            .background(Color.primary.opacity(0.1))

                        SettingsToggleRow(
                            "Sound effects",
                            description: "Play sounds for actions",
                            isOn: $soundEffectsEnabled,
                            identifier: "settings.toggle.soundEffects"
                        )

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        SettingsToggleRow(
                            "Hide menu bar icon",
                            description: "Use keyboard shortcuts to access Paste",
                            isOn: $hideMenuBarIcon,
                            identifier: "settings.toggle.hideMenuBarIcon"
                        )
                    }
                }
            }

            // Overlay Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Overlay", icon: "rectangle.3.group")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Overlay edge")
                            .font(.system(size: 13, weight: .medium))

                        HStack(spacing: 12) {
                            ForEach(OverlayScreenEdge.allCases) { edge in
                                OverlayEdgeOptionView(
                                    edge: edge,
                                    isSelected: overlayScreenEdgeRawValue == edge.rawValue
                                ) {
                                    overlayScreenEdgeRawValue = edge.rawValue
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("settings.picker.overlayScreenEdge")
                        .onAppear {
                            normalizeOverlayEdgeSelection()
                        }
                        .onChange(of: overlayScreenEdgeRawValue) { newValue, _ in
                            if OverlayScreenEdge(rawValue: newValue) == nil {
                                overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue
                            }
                        }

                        Text(
                            "Top and Bottom keep the current horizontal layout. Left and Right use a compact vertical layout."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    }
                }
            }

            // OCR Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("OCR", icon: "text.viewfinder")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Default capture mode")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $ocrDefaultModeRawValue) {
                                ForEach(OCRCaptureMode.allCases, id: \.rawValue) { mode in
                                    Text(mode.settingsTitle)
                                        .tag(mode.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .accessibilityIdentifier("settings.picker.ocrDefaultMode")
                        .onAppear {
                            normalizeOCRModeSelection()
                        }
                        .onChange(of: ocrDefaultModeRawValue) { newValue, _ in
                            if OCRCaptureMode(rawValue: newValue) == nil {
                                ocrDefaultModeRawValue = OCRCaptureMode.staticSnapshot.rawValue
                            }
                        }

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        HStack {
                            Text("Language")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $ocrPreferredLanguageCode) {
                                ForEach(OCRLanguage.allCases, id: \.rawValue) { language in
                                    Text(language.displayName)
                                        .tag(language.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                        .accessibilityIdentifier("settings.picker.ocrPreferredLanguage")

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        SettingsToggleRow(
                            "Show capture notification",
                            description: "Display a notification when text is captured",
                            isOn: $ocrShowCaptureNotification,
                            identifier: "settings.toggle.ocrShowCaptureNotification"
                        )
                    }
                }
            }

            // Security Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Security", icon: "lock.shield")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Locked pinboard unlock duration")
                            .font(.system(size: 13, weight: .medium))

                        HStack {
                            Picker("Duration", selection: $unlockDurationSeconds) {
                                ForEach(durationOptions, id: \.self) { seconds in
                                    Text(formattedDuration(seconds)).tag(seconds)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityIdentifier("settings.picker.pinboardUnlockDuration")
                        }
                        .onAppear {
                            normalizeUnlockDurationSelection()
                        }
                        .onChange(of: unlockDurationSeconds) { newValue, _ in
                            let clamped = PinboardSecuritySettings.clampedUnlockDuration(newValue)
                            let normalized = PinboardSecuritySettings.nearestQuickDuration(to: clamped)
                            if normalized != newValue {
                                unlockDurationSeconds = normalized
                            }
                        }

                        Text(
                            "After Touch ID or password authentication, locked pinboards stay unlocked for this preset duration."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
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
                            .background(Color.primary.opacity(0.1))

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

            // Application Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Application", icon: "macwindow")

                SettingsCard {
                    HStack {
                        Text("Quit Paste")
                            .font(.system(size: 13, weight: .medium))

                        Spacer()

                        Button(role: .destructive) {
                            NSApplication.shared.terminate(nil)
                        } label: {
                            Text("Quit")
                                .frame(width: 60)
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.button.quitApp")
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

    private var durationLabel: String {
        formattedDuration(unlockDurationSeconds)
    }

    private var durationOptions: [Int] {
        PinboardSecuritySettings.quickUnlockDurations
    }

    private func normalizeUnlockDurationSelection() {
        let normalized = PinboardSecuritySettings.nearestQuickDuration(to: unlockDurationSeconds)
        if normalized != unlockDurationSeconds {
            unlockDurationSeconds = normalized
        }
    }

    private func formattedDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds.isMultiple(of: 60) {
            let minutes = seconds / 60
            return minutes == 1 ? "1m" : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    private func normalizeOverlayEdgeSelection() {
        if OverlayScreenEdge(rawValue: overlayScreenEdgeRawValue) == nil {
            overlayScreenEdgeRawValue = OverlayLayoutSettings.defaultEdge.rawValue
        }
    }

    private func normalizeOCRModeSelection() {
        if OCRCaptureMode(rawValue: ocrDefaultModeRawValue) == nil {
            ocrDefaultModeRawValue = OCRCaptureMode.staticSnapshot.rawValue
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

// MARK: - Overlay Edge Option View

private struct OverlayEdgeOptionView: View {
    let edge: OverlayScreenEdge
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image(iconName)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(width: 60, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                Text(edge.settingsTitle)
                    .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch edge {
        case .bottom: return "OverlayEdgeBottom"
        case .top: return "OverlayEdgeTop"
        case .left: return "OverlayEdgeLeft"
        case .right: return "OverlayEdgeRight"
        }
    }
}
