import CoreData
import MartenCore
import SwiftUI

struct PinboardManagementSheet: View {
    @Bindable var container: MartenIOSAppContainer

    @Environment(\.dismiss) private var dismiss

    @FetchRequest(fetchRequest: pinboardFetchRequest())
    private var pinboards: FetchedResults<Pinboard>

    @State private var editorContext: EditorContext?
    @State private var shareContext: ShareContext?
    @State private var pendingStopSharingPinboardID: NSManagedObjectID?
    @State private var pendingLeaveSharedPinboardID: NSManagedObjectID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(pinboards, id: \.objectID) { pinboard in
                    row(for: pinboard)
                }
            }
            .navigationTitle("Pinboards")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        editorContext = .create
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editorContext) { context in
            switch context {
            case .create:
                PinboardEditorSheet(mode: .create) { name, colorHex, iconName in
                    Task {
                        await container.createPinboard(name: name, colorHex: colorHex, iconName: iconName)
                    }
                }
            case .edit(let objectIDURI, let name, let colorHex, let iconName):
                PinboardEditorSheet(
                    mode: .edit,
                    initialName: name,
                    initialColorHex: colorHex,
                    initialIconName: iconName
                ) { updatedName, updatedColorHex, updatedIconName in
                    guard let objectID = resolveObjectID(fromURIString: objectIDURI) else { return }
                    Task {
                        await container.updatePinboard(
                            objectID: objectID,
                            name: updatedName,
                            colorHex: updatedColorHex,
                            iconName: updatedIconName
                        )
                    }
                }
            }
        }
        .sheet(item: $shareContext) { context in
            if let sharingRepository = container.sharingRepository {
                ShareSettingsSheet(
                    pinboardID: context.pinboardID,
                    sharingRepository: sharingRepository,
                    initialAccessControl: context.initialAccessControl,
                    initialPermission: context.initialPermission,
                    initialShareURL: context.initialShareURL
                )
            }
        }
        .alert(
            "Stop sharing this pinboard?",
            isPresented: Binding(
                get: { pendingStopSharingPinboardID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingStopSharingPinboardID = nil
                    }
                }
            )
        ) {
            Button("Stop Sharing", role: .destructive) {
                guard let objectID = pendingStopSharingPinboardID else { return }
                Task {
                    await container.stopSharingPinboard(objectID: objectID)
                }
                pendingStopSharingPinboardID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingStopSharingPinboardID = nil
            }
        } message: {
            Text("All participants will immediately lose access.")
        }
        .alert(
            "Leave shared pinboard?",
            isPresented: Binding(
                get: { pendingLeaveSharedPinboardID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingLeaveSharedPinboardID = nil
                    }
                }
            )
        ) {
            Button("Leave", role: .destructive) {
                guard let objectID = pendingLeaveSharedPinboardID else { return }
                Task {
                    await container.leaveSharedPinboard(objectID: objectID)
                }
                pendingLeaveSharedPinboardID = nil
            }
            Button("Cancel", role: .cancel) {
                pendingLeaveSharedPinboardID = nil
            }
        } message: {
            Text("You will lose access to this shared pinboard.")
        }
    }

    private func row(for pinboard: Pinboard) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: pinboard.colorHex, fallback: .gray))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(pinboard.isSystemMarten ? "Clipboard History" : pinboard.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                if pinboard.isSystemMarten {
                    Text("System pinboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !pinboard.isSystemMarten {
                Toggle(
                    "Lock \(pinboard.name)",
                    isOn: Binding(
                        get: { container.lockStateStore.isLocked(pinboard.id) },
                        set: { isEnabled in
                            container.lockStateStore.setLock(isEnabled, for: pinboard.id)
                        }
                    )
                )
                .labelsHidden()
                .help("Lock Hook")
                .accessibilityLabel("Lock \(pinboard.name)")
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !pinboard.isSystemMarten {
                Button("Edit") {
                    editorContext = .edit(
                        objectIDURI: pinboard.objectID.uriRepresentation().absoluteString,
                        name: pinboard.name,
                        colorHex: pinboard.colorHex,
                        iconName: pinboard.iconName
                    )
                }
                .tint(.blue)

                Button("Delete", role: .destructive) {
                    Task {
                        await container.deletePinboard(pinboard)
                    }
                }
            }
        }
        .contextMenu {
            if !pinboard.isSystemMarten {
                Button("Edit") {
                    editorContext = .edit(
                        objectIDURI: pinboard.objectID.uriRepresentation().absoluteString,
                        name: pinboard.name,
                        colorHex: pinboard.colorHex,
                        iconName: pinboard.iconName
                    )
                }
                Divider()
            }

            if container.sharingRepository != nil, !pinboard.isSystemMarten {
                let metadata = pinboard.shareMetadata
                let initialShareURL = metadata?.shareURL.flatMap(URL.init(string:))
                let context = ShareContext(
                    pinboardID: pinboard.objectID,
                    initialAccessControl: metadata?.accessControl ?? .onlyInvited,
                    initialPermission: metadata?.defaultPermission ?? .canMakeChanges,
                    initialShareURL: initialShareURL
                )

                if pinboard.isShared {
                    if pinboard.shareRole == .owner {
                        Button("Manage Sharing") {
                            shareContext = context
                        }
                        Button("Stop Sharing", role: .destructive) {
                            pendingStopSharingPinboardID = pinboard.objectID
                        }
                    } else {
                        Button("View Sharing") {
                            shareContext = context
                        }
                        Button("Leave Shared Pinboard", role: .destructive) {
                            pendingLeaveSharedPinboardID = pinboard.objectID
                        }
                    }
                } else {
                    Button("Share Pinboard") {
                        shareContext = context
                    }
                }
                Divider()
            }

            if !pinboard.isSystemMarten {
                Button("Delete", role: .destructive) {
                    Task {
                        await container.deletePinboard(pinboard)
                    }
                }
            }
        }
    }

    private func resolveObjectID(fromURIString uriString: String) -> NSManagedObjectID? {
        guard let url = URL(string: uriString) else { return nil }
        return container.persistenceController.container.persistentStoreCoordinator
            .managedObjectID(forURIRepresentation: url)
    }
}

private struct ShareContext: Identifiable {
    let pinboardID: NSManagedObjectID
    let initialAccessControl: ShareAccessControl
    let initialPermission: SharePermission
    let initialShareURL: URL?

    var id: String { pinboardID.uriRepresentation().absoluteString }
}

private enum EditorContext: Identifiable {
    case create
    case edit(objectIDURI: String, name: String, colorHex: String, iconName: String?)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let objectIDURI, _, _, _):
            return objectIDURI
        }
    }
}

private func pinboardFetchRequest() -> NSFetchRequest<Pinboard> {
    let request = Pinboard.fetchRequest()
    request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    request.returnsObjectsAsFaults = false
    return request
}
