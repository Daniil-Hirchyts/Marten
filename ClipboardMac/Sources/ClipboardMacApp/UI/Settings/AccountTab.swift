import ClipboardCore
import SwiftUI

struct AccountSettingsContent: View {
    @State private var showDisableSyncWarning = false
    @State private var isSyncInProgress = false
    @State private var syncError: Error?
    @State private var authManager = AppleAuthManager()
    @State private var signInError: String?

    @ObservedObject var syncCoordinator: SyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // iCloud Sync Section
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader("iCloud Sync", icon: "icloud")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        if authManager.isSignedIn {
                            // Signed in - show sync controls
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
                                    .background(Color.primary.opacity(0.1))

                                AccountStatusRow(error: error, onSignIn: openAppleIDSettings)
                            }

                            if syncCoordinator.syncEnabled {
                                Divider()
                                    .background(Color.primary.opacity(0.1))

                                SyncStatusIndicator(coordinator: syncCoordinator, displayMode: .expanded)

                                Divider()
                                    .background(Color.primary.opacity(0.1))

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

                            Divider()
                                .background(Color.primary.opacity(0.1))

                            // Sign Out button
                            HStack {
                                Spacer()
                                Button("Sign Out") {
                                    // Disable sync before signing out
                                    syncCoordinator.syncEnabled = false
                                    authManager.signOut()
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("settings.button.signOut")
                            }
                        } else {
                            // Not signed in - show sign in button
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Sign in with your Apple ID to enable iCloud sync")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)

                                Button {
                                    Task {
                                        do {
                                            try await authManager.signIn()
                                            signInError = nil
                                        } catch is CancellationError {
                                            // User cancelled - ignore
                                        } catch {
                                            signInError = error.localizedDescription
                                        }
                                    }
                                } label: {
                                    if authManager.isAuthenticating {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text("Signing In...")
                                        }
                                    } else {
                                        Text("Sign In with Apple")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(authManager.isAuthenticating)
                                .accessibilityIdentifier("settings.button.signInWithApple")

                                if let error = signInError {
                                    Text(error)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                }
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
