import ClipboardCore
import ServiceManagement
import SwiftUI

struct GeneralTab: View {
    @AppStorage("openAtLogin") private var openAtLogin = false
    @AppStorage("pasteToActiveApp") private var pasteToActiveApp = true
    @AppStorage("alwaysPastePlainText") private var alwaysPastePlainText = false
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled = true
    @AppStorage("retentionPolicy") private var retentionPolicy = "month"

    @State private var showEraseConfirmation = false
    @State private var showDisableSyncWarning = false
    @State private var isSyncInProgress = false
    @State private var syncError: Error?

    // SyncCoordinator is optional - will be nil if not injected
    var syncCoordinator: SyncCoordinator?

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
                Picker("Paste items", selection: $pasteToActiveApp) {
                    Text("To active app").tag(true)
                    Text("To clipboard").tag(false)
                }
                .accessibilityIdentifier("settings.picker.pasteItems")
                .accessibilityLabel("Paste items")

                Toggle("Always paste as Plain Text", isOn: $alwaysPastePlainText)
                    .accessibilityIdentifier("settings.toggle.alwaysPastePlainText")
                    .accessibilityLabel("Always paste as plain text")

                Toggle("Sound effects", isOn: $soundEffectsEnabled)
                    .accessibilityIdentifier("settings.toggle.soundEffects")
                    .accessibilityLabel("Sound effects")
            }

            // iCloud Sync Section
            if let coordinator = syncCoordinator {
                Section {
                    iCloudSyncToggle(coordinator: coordinator)
                    
                    if coordinator.syncEnabled {
                        SyncStatusIndicator(coordinator: coordinator, displayMode: .expanded)
                        
                        syncNowButton(coordinator: coordinator)
                    }
                } header: {
                    Text("iCloud Sync")
                } footer: {
                    Text("Sync your clipboard history across all your devices signed into iCloud.")
                }
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
        .alert("Disable iCloud Sync?", isPresented: $showDisableSyncWarning) {
            Button("Disable Sync", role: .destructive) {
                syncCoordinator?.syncEnabled = false
            }
            .accessibilityIdentifier("settings.button.disableIcloudSync")
            .accessibilityLabel("Disable iCloud sync")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.button.disableIcloudSync.cancel")
                .accessibilityLabel("Cancel disable iCloud sync")
        } message: {
            Text("Your clipboard history will remain on this device but will no longer sync with other devices.")
        }
        .alert("Sync Error", isPresented: .constant(syncError != nil)) {
            Button("OK") {
                syncError = nil
            }
            .accessibilityIdentifier("settings.button.syncError.ok")
            .accessibilityLabel("Dismiss sync error")
            if case .notSignedIn = (syncError as? CloudKitSyncError) {
                Button("Open System Settings") {
                    openAppleIDSettings()
                    syncError = nil
                }
                .accessibilityIdentifier("settings.button.syncError.openSystemSettings")
                .accessibilityLabel("Open System Settings")
            }
        } message: {
            if let error = syncError {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - iCloud Sync Toggle

    @ViewBuilder
    private func iCloudSyncToggle(coordinator: SyncCoordinator) -> some View {
        Toggle("Enable iCloud Sync", isOn: Binding(
            get: { coordinator.syncEnabled },
            set: { newValue in
                if newValue {
                    coordinator.syncEnabled = true
                } else {
                    showDisableSyncWarning = true
                }
            }
        ))
        .accessibilityIdentifier("settings.toggle.icloudSync")
        .accessibilityLabel("Enable iCloud sync")

        // Show account status for errors
        if case .error(let error) = coordinator.status {
            if error.requiresUserAction {
                accountStatusRow(for: error)
            }
        }
    }

    @ViewBuilder
    private func accountStatusRow(for error: CloudKitSyncError) -> some View {
        HStack {
            Image(systemName: accountStatusIcon(for: error))
                .foregroundStyle(accountStatusColor(for: error))

            Text(accountStatusText(for: error))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if case .notSignedIn = error {
                Button("Sign In") {
                    openAppleIDSettings()
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("settings.button.icloudSignIn")
                .accessibilityLabel("Sign in to iCloud")
            }
        }
    }

    private func accountStatusIcon(for error: CloudKitSyncError) -> String {
        switch error {
        case .notSignedIn:
            return "person.crop.circle.badge.exclamationmark"
        case .accountRestricted:
            return "lock.circle"
        case .quotaExceeded:
            return "externaldrive.badge.exclamationmark"
        default:
            return "exclamationmark.circle"
        }
    }

    private func accountStatusColor(for error: CloudKitSyncError) -> Color {
        switch error {
        case .notSignedIn, .accountRestricted:
            return .orange
        case .quotaExceeded:
            return .red
        default:
            return .secondary
        }
    }

    private func accountStatusText(for error: CloudKitSyncError) -> String {
        switch error {
        case .notSignedIn:
            return "Not signed in to iCloud"
        case .accountRestricted:
            return "iCloud account is restricted"
        case .quotaExceeded:
            return "iCloud storage full"
        default:
            return error.localizedDescription
        }
    }

    // MARK: - Sync Now Button

    @ViewBuilder
    private func syncNowButton(coordinator: SyncCoordinator) -> some View {
        HStack {
            Button {
                performManualSync(coordinator: coordinator)
            } label: {
                HStack(spacing: 6) {
                    if isSyncInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isSyncInProgress ? "Syncing..." : "Sync Now")
                }
            }
            .accessibilityIdentifier("settings.button.syncNow")
            .accessibilityLabel(isSyncInProgress ? "Syncing" : "Sync now")
            .disabled(isSyncInProgress || coordinator.status == .syncing)

            Spacer()
        }
    }

    private func performManualSync(coordinator: SyncCoordinator) {
        isSyncInProgress = true

        Task {
            do {
                try await coordinator.triggerSyncNow()
            } catch {
                syncError = error
            }

            await MainActor.run {
                isSyncInProgress = false
            }
        }
    }

    // MARK: - Helpers

    private func openAppleIDSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }
}
