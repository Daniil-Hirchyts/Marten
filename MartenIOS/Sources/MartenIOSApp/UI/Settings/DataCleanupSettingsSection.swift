import SwiftUI
import LocalAuthentication

struct DataCleanupSettingsSection: View {
    let container: MartenIOSAppContainer

    var body: some View {
        Section {
            NavigationLink {
                DangerZoneView(container: container)
            } label: {
                Text("Danger Zone")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Data & Storage")
        }
    }
}

struct DangerZoneView: View {
    let container: MartenIOSAppContainer

    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteDeviceDataConfirmation = false
    @State private var showingDeletePinboardsConfirmation = false

    var body: some View {
        List {
            Section {
                Button(role: .destructive) {
                    showingDeletePinboardsConfirmation = true
                } label: {
                    Text("Delete Pinboards")
                }
                .confirmationDialog(
                    "Delete Pinboards?",
                    isPresented: $showingDeletePinboardsConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Pinboards", role: .destructive) {
                        Task { await container.deleteOnlyPinboards() }
                    }
                } message: {
                    Text("All pinboards will be removed. Your cards will stay in All Items.")
                }

                Button(role: .destructive) {
                    showingDeleteDeviceDataConfirmation = true
                } label: {
                    Text("Clear Clipboard on This Device")
                }
                .confirmationDialog(
                    "Clear Clipboard on This Device?",
                    isPresented: $showingDeleteDeviceDataConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        Task { await container.deleteDataCreatedOnThisDevice() }
                    }
                } message: {
                    Text("Cards created on this device will be permanently deleted.")
                }

                Button(role: .destructive) {
                    showingDeleteAllConfirmation = true
                } label: {
                    Text("Delete Everything")
                }
                .confirmationDialog(
                    "Delete Everything?",
                    isPresented: $showingDeleteAllConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete Everything", role: .destructive) {
                        Task {
                            let context = LAContext()
                            var error: NSError?
                            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                                if let success = try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Delete all your data"), success {
                                    await container.nukeAllData()
                                }
                            } else {
                                await container.nukeAllData()
                            }
                        }
                    }
                } message: {
                    Text("All cards, pinboards, and iCloud data will be permanently deleted. This cannot be undone.")
                }
            } footer: {
                Text("These actions are permanent and cannot be undone.")
            }
        }
        .navigationTitle("Danger Zone")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}
