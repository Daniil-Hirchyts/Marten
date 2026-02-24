import CoreData
import MartenCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShareSettingsSheet: View {
    @State private var viewModel: ShareSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        pinboardID: NSManagedObjectID,
        sharingRepository: any PinboardSharingRepositoryProtocol,
        initialAccessControl: ShareAccessControl = .onlyInvited,
        initialPermission: SharePermission = .canMakeChanges,
        initialShareURL: URL? = nil,
        isPinboardLocked: @escaping @MainActor () -> Bool = { false }
    ) {
        _viewModel = State(
            initialValue: ShareSettingsViewModel(
                pinboardID: pinboardID,
                sharingRepository: sharingRepository,
                initialAccessControl: initialAccessControl,
                initialDefaultPermission: initialPermission,
                initialShareURL: initialShareURL,
                isPinboardLocked: isPinboardLocked
            )
        )
    }

    var body: some View {
        @Bindable var model = viewModel

        NavigationStack {
            Form {
                if let workflowMessage = model.workflowMessage {
                    Section {
                        Text(workflowMessage)
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }

                if let errorMessage = model.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }

                if model.isLockedForSharing {
                    Section {
                        Text("Unlock this pinboard before creating a share link.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Access") {
                    Picker("Who Can Access", selection: $model.accessControl) {
                        Text("Only Invited").tag(ShareAccessControl.onlyInvited)
                        Text("Anyone With Link").tag(ShareAccessControl.anyoneWithLink)
                    }
                    .disabled(model.hasShareLink && !model.isOwner)

                    Picker("Default Permission", selection: $model.defaultPermission) {
                        Text("Can Edit").tag(SharePermission.canMakeChanges)
                        Text("View Only").tag(SharePermission.viewOnly)
                    }
                    .disabled(model.hasShareLink && !model.isOwner)
                }

                if let shareURL = model.shareURL {
                    Section("Link") {
                        HStack {
                            Text(shareURL.absoluteString)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button("Copy") {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = shareURL.absoluteString
                                #endif
                            }
                        }
                    }

                    Section("Participants") {
                        if model.participants.isEmpty {
                            Text("No participants yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.participants) { participant in
                                ShareParticipantRow(
                                    participant: participant,
                                    canManageParticipants: model.canManageParticipants,
                                    isActionInFlight: model.isParticipantActionInFlight(participant.id),
                                    onPermissionChange: { permission in
                                        Task {
                                            await model.updateParticipantPermission(
                                                participantID: participant.id,
                                                permission: permission
                                            )
                                        }
                                    },
                                    onRemove: {
                                        model.requestRemoveParticipant(participant)
                                    }
                                )
                            }
                        }
                    }

                    if model.canManageParticipants {
                        Section("Invite") {
                            #if canImport(UIKit)
                            TextField("Email address", text: $model.inviteEmail)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .accessibilityLabel("Participant email address")
                            #else
                            TextField("Email address", text: $model.inviteEmail)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Participant email address")
                            #endif

                            if let validation = model.inviteValidationMessage {
                                Text(validation)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button(model.isInvitingParticipant ? "Inviting…" : "Invite Participant") {
                                Task {
                                    _ = await model.inviteParticipant()
                                }
                            }
                            .disabled(model.isInvitingParticipant)
                        }
                    }
                }
            }
            .navigationTitle("Share Pinboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.hasShareLink {
                        Button(model.isUpdatingSettings ? "Saving…" : "Save") {
                            Task {
                                await model.updateShareSettingsIfNeeded()
                            }
                        }
                        .disabled(!model.hasPendingSettingsChanges || model.isUpdatingSettings)
                    } else {
                        Button(model.isCreatingShare ? "Creating…" : "Create Link") {
                            Task {
                                await model.createShare()
                            }
                        }
                        .disabled(model.isCreatingShare || model.isLoading || model.isLockedForSharing)
                    }
                }
                if model.hasShareLink && model.isOwner {
                    ToolbarItem(placement: stopSharingToolbarPlacement) {
                        Button("Stop Sharing", role: .destructive) {
                            Task {
                                let didStop = await model.stopSharing()
                                if didStop {
                                    dismiss()
                                }
                            }
                        }
                        .disabled(model.isStoppingShare)
                    }
                }
            }
            .alert(
                "Remove Participant?",
                isPresented: Binding(
                    get: { model.pendingParticipantRemoval != nil },
                    set: { isPresented in
                        if !isPresented {
                            model.pendingParticipantRemoval = nil
                        }
                    }
                )
            ) {
                Button("Remove", role: .destructive) {
                    Task {
                        await model.removePendingParticipant()
                    }
                }
                Button("Cancel", role: .cancel) {
                    model.pendingParticipantRemoval = nil
                }
            } message: {
                Text("This person will immediately lose access to this pinboard.")
            }
        }
        .task {
            await model.onAppear()
        }
    }

    private var stopSharingToolbarPlacement: ToolbarItemPlacement {
        #if canImport(UIKit)
        .bottomBar
        #else
        .automatic
        #endif
    }
}
