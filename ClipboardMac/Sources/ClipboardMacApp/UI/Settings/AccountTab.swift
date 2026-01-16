import ClipboardCore
import SwiftUI

struct AccountTab: View {
    @State private var showDisableSyncWarning = false
    @State private var isSyncInProgress = false
    @State private var syncError: Error?

    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        Form {
            Section {
                appleIDRow
            } header: {
                Text("Apple ID")
            } footer: {
                Text("Your Apple ID is used to sync clipboard history across your devices.")
            }

            Section {
                iCloudSyncToggle

                if syncCoordinator.syncEnabled {
                    SyncStatusIndicator(coordinator: syncCoordinator, displayMode: .expanded)

                    syncNowButton
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Sync your clipboard history across all your devices signed into iCloud.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Disable iCloud Sync?", isPresented: $showDisableSyncWarning) {
            Button("Disable Sync", role: .destructive) {
                syncCoordinator.syncEnabled = false
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

    // MARK: - Apple ID Row

    @ViewBuilder
    private var appleIDRow: some View {
        HStack {
            Image(systemName: "person.crop.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                if case .error(let error) = syncCoordinator.status,
                   case .notSignedIn = error {
                    Text("Not Signed In")
                        .font(.headline)
                    Text("Sign in to iCloud to sync your clipboard.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("iCloud Account")
                        .font(.headline)
                    Text("Signed in")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Open Settings...") {
                openAppleIDSettings()
            }
            .accessibilityIdentifier("settings.button.openAppleIdSettings")
            .accessibilityLabel("Open Apple ID settings")
        }
        .padding(.vertical, 4)
    }

    // MARK: - iCloud Sync Toggle

    @ViewBuilder
    private var iCloudSyncToggle: some View {
        Toggle("Enable iCloud Sync", isOn: Binding(
            get: { syncCoordinator.syncEnabled },
            set: { newValue in
                if newValue {
                    syncCoordinator.syncEnabled = true
                } else {
                    showDisableSyncWarning = true
                }
            }
        ))
        .accessibilityIdentifier("settings.toggle.icloudSync")
        .accessibilityLabel("Enable iCloud sync")

        if case .error(let error) = syncCoordinator.status {
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
    private var syncNowButton: some View {
        HStack {
            Button {
                performManualSync()
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
            .disabled(isSyncInProgress || syncCoordinator.status == .syncing)

            Spacer()
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

    // MARK: - Helpers

    private func openAppleIDSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.AppleIDPrefPane") {
            NSWorkspace.shared.open(url)
        }
    }
}
