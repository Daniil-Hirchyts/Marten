import MartenCore
import SwiftUI

struct DangerZoneView: View {
    @State private var showingDeleteAllConfirmation = false
    @State private var showingDeleteDeviceDataConfirmation = false
    @State private var showingDeletePinboardsConfirmation = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Pinboards")
                                .font(.system(size: 13, weight: .medium))
                            Text("All pinboards will be removed. Your cards will stay in All Items.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingDeletePinboardsConfirmation = true
                        } label: {
                            Text("Delete Pinboards...")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Items from This Device")
                                .font(.system(size: 13, weight: .medium))
                            Text("Cards created on this device will be permanently deleted.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingDeleteDeviceDataConfirmation = true
                        } label: {
                            Text("Delete...")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete Everything")
                                .font(.system(size: 13, weight: .medium))
                            Text("All cards and pinboards will be permanently deleted. This cannot be undone.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showingDeleteAllConfirmation = true
                        } label: {
                            Text("Delete Everything...")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Danger Zone")
        .alert("Delete Pinboards?", isPresented: $showingDeletePinboardsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Pinboards", role: .destructive) {
                try? ClipItemStore().deleteUserPinboards()
            }
        } message: {
            Text("All pinboards will be removed. Your cards will stay in All Items.")
        }
        .alert("Delete Items from This Device?", isPresented: $showingDeleteDeviceDataConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                try? ClipItemStore().deleteItemsFromThisDevice()
            }
        } message: {
            Text("Cards created on this device will be permanently deleted.")
        }
        .alert("Delete Everything?", isPresented: $showingDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                try? ClipItemStore().deleteAllItems()
            }
        } message: {
            Text("All cards and pinboards will be permanently deleted. This cannot be undone.")
        }
    }
}
