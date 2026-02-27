import MartenCore
import SwiftUI

/// Danger Zone settings view for macOS — provides destructive data management actions.
struct DangerZoneView: View {
    var syncCoordinator: SyncCoordinator? = nil

    @State private var showDeletePinboardsConfirmation = false
    @State private var showDeleteDeviceDataConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var deleteEverythingErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSectionHeader("Danger Zone", icon: "exclamationmark.triangle")

                SettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Delete Pinboards")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Remove pinboards. Cards will stay in All Items.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                showDeletePinboardsConfirmation = true
                            } label: {
                                Text("Delete...")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear Clipboard on This Device")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Permanently delete cards created locally.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                showDeleteDeviceDataConfirmation = true
                            } label: {
                                Text("Delete...")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }

                        Divider()
                            .background(Color.primary.opacity(0.1))

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Delete Everything")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Delete all cards and pinboards. Cannot be undone.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                showDeleteAllConfirmation = true
                            } label: {
                                Text("Delete...")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Danger Zone")
        .alert("Delete Pinboards?", isPresented: $showDeletePinboardsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Pinboards", role: .destructive) {
                try? ClipItemStore().deleteUserPinboards()
            }
        } message: {
            Text("All pinboards will be removed. Your cards will stay in All Items.")
        }
        .alert("Clear Clipboard on This Device?", isPresented: $showDeleteDeviceDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? ClipItemStore().deleteItemsFromThisDevice()
            }
        } message: {
            Text("Cards created on this device will be permanently deleted.")
        }
        .alert("Delete Everything?", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                Task { await performDeleteEverything() }
            }
        } message: {
            Text("All cards and pinboards will be permanently deleted. This cannot be undone.")
        }
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: { deleteEverythingErrorMessage != nil },
                set: { if !$0 { deleteEverythingErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteEverythingErrorMessage ?? "Unknown error.")
        }
    }

    private func performDeleteEverything() async {
        if let syncCoordinator {
            let result = await syncCoordinator.wipeEverything()
            if let summary = result.failureSummary {
                deleteEverythingErrorMessage = summary
            }
            return
        }

        do {
            try ClipItemStore().deleteAllItems()
        } catch {
            deleteEverythingErrorMessage = error.localizedDescription
        }
    }
}
