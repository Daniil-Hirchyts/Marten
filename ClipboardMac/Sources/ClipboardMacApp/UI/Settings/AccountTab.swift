import ClipboardCore
import SwiftUI

struct AccountSettingsContent: View {
    @State private var showDisableSyncWarning = false
    @State private var isSyncInProgress = false
    @State private var syncError: Error?

    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Apple ID Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("Apple ID", icon: "apple.logo")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                if case .error(let error) = syncCoordinator.status,
                                   case .notSignedIn = error {
                                    Text("Not Signed In")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Sign in to iCloud to sync your clipboard")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("iCloud Account")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Signed in")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Button("Open Settings...") {
                                openAppleIDSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.button.openAppleIdSettings")
                        }

                        Text("Your Apple ID is used to sync clipboard history across your devices.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // iCloud Sync Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("iCloud Sync", icon: "icloud")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SettingsToggleRow(
                            "Enable iCloud Sync",
                            description: "Sync clipboard history across all your devices",
                            isOn: Binding(
                                get: { syncCoordinator.syncEnabled },
                                set: { newValue in
                                    if newValue {
                                        syncCoordinator.syncEnabled = true
                                    } else {
                                        showDisableSyncWarning = true
                                    }
                                }
                            ),
                            identifier: "settings.toggle.icloudSync"
                        )

                        if case .error(let error) = syncCoordinator.status,
                           error.requiresUserAction {
                            Divider()
                                .background(Color.white.opacity(0.1))

                            AccountStatusRow(error: error, onSignIn: openAppleIDSettings)
                        }

                        if syncCoordinator.syncEnabled {
                            Divider()
                                .background(Color.white.opacity(0.1))

                            SyncStatusIndicator(coordinator: syncCoordinator, displayMode: .expanded)

                            Divider()
                                .background(Color.white.opacity(0.1))

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Manual Sync")
                                        .font(.system(size: 13, weight: .medium))
                                    Text("Force sync with iCloud")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()

                                Button {
                                    performManualSync()
                                } label: {
                                    HStack(spacing: 6) {
                                        if isSyncInProgress {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                        Text(isSyncInProgress ? "Syncing..." : "Sync Now")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isSyncInProgress || syncCoordinator.status == .syncing)
                                .accessibilityIdentifier("settings.button.syncNow")
                            }
                        }
                    }
                }
            }
        }
        .alert("Disable iCloud Sync?", isPresented: $showDisableSyncWarning) {
            Button("Disable Sync", role: .destructive) {
                syncCoordinator.syncEnabled = false
            }
            .accessibilityIdentifier("settings.button.disableIcloudSync")

            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.button.disableIcloudSync.cancel")
        } message: {
            Text("Your clipboard history will remain on this device but will no longer sync with other devices.")
        }
        .alert("Sync Error", isPresented: .constant(syncError != nil)) {
            Button("OK") {
                syncError = nil
            }
            .accessibilityIdentifier("settings.button.syncError.ok")

            if case .notSignedIn = (syncError as? CloudKitSyncError) {
                Button("Open System Settings") {
                    openAppleIDSettings()
                    syncError = nil
                }
                .accessibilityIdentifier("settings.button.syncError.openSystemSettings")
            }
        } message: {
            if let error = syncError {
                Text(error.localizedDescription)
            }
        }
    }

    private func performManualSync() {
        isSyncInProgress = true

        Task {
            do {
                try await syncCoordinator.triggerSyncNow()
            } catch {
                syncError = error
            }

            await MainActor.run {
                isSyncInProgress = false
            }
        }
    }

    private func openAppleIDSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Account Status Row

private struct AccountStatusRow: View {
    let error: CloudKitSyncError
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusColor)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer()

            if case .notSignedIn = error {
                Button("Sign In") {
                    onSignIn()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                .accessibilityIdentifier("settings.button.icloudSignIn")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statusColor.opacity(0.1))
        )
    }

    private var statusIcon: String {
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

    private var statusColor: Color {
        switch error {
        case .notSignedIn, .accountRestricted:
            return .orange
        case .quotaExceeded:
            return .red
        default:
            return .secondary
        }
    }

    private var statusText: String {
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
}

// Keep the old tab for compatibility
struct AccountTab: View {
    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        AccountSettingsContent(syncCoordinator: syncCoordinator)
            .padding()
    }
}
