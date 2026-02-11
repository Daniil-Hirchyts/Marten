import CoreData
import Foundation
import MartenCore

/// View model for the share settings sheet.
///
/// Wraps PinboardSharingRepository calls and manages share details, participants, loading, and errors.
@MainActor
final class ShareSettingsViewModel: ObservableObject {
    @Published var accessControl: ShareAccessControl = .onlyInvited
    @Published var defaultPermission: SharePermission = .canMakeChanges
    @Published var inviteEmail: String = ""

    @Published private(set) var shareURL: URL?
    @Published private(set) var participants: [ShareParticipantInfo] = []
    @Published private(set) var isOwner: Bool = true

    @Published var isLoading = false
    @Published var isCreatingShare = false
    @Published var isUpdatingSettings = false
    @Published var isInvitingParticipant = false
    @Published var isStoppingShare = false

    @Published private(set) var participantActionIDs: Set<String> = []
    @Published var pendingParticipantRemoval: ShareParticipantInfo?
    @Published var showingStopSharingConfirmation = false
    @Published var errorMessage: String?
    @Published var inviteValidationMessage: String?
    @Published var workflowMessage: String?

    private let sharingRepository: any PinboardSharingRepositoryProtocol
    let pinboardID: NSManagedObjectID

    private var loadedAccessControl: ShareAccessControl
    private var loadedDefaultPermission: SharePermission
    private var didAttemptInitialLoad = false

    init(
        pinboardID: NSManagedObjectID,
        sharingRepository: any PinboardSharingRepositoryProtocol,
        initialAccessControl: ShareAccessControl = .onlyInvited,
        initialDefaultPermission: SharePermission = .canMakeChanges,
        initialShareURL: URL? = nil
    ) {
        self.pinboardID = pinboardID
        self.sharingRepository = sharingRepository
        self.accessControl = initialAccessControl
        self.defaultPermission = initialDefaultPermission
        self.shareURL = initialShareURL
        self.loadedAccessControl = initialAccessControl
        self.loadedDefaultPermission = initialDefaultPermission
    }

    var hasShareLink: Bool {
        shareURL != nil
    }

    var hasPendingSettingsChanges: Bool {
        guard hasShareLink else { return false }
        return accessControl != loadedAccessControl || defaultPermission != loadedDefaultPermission
    }

    var canManageShareSettings: Bool {
        hasShareLink && isOwner
    }

    var canManageParticipants: Bool {
        hasShareLink && isOwner
    }

    var nonOwnerParticipantCount: Int {
        participants.filter { !$0.isOwner }.count
    }

    var shouldShowOnlyInvitedWarning: Bool {
        hasShareLink && accessControl == .onlyInvited && nonOwnerParticipantCount == 0
    }

    func isParticipantActionInFlight(_ participantID: String) -> Bool {
        participantActionIDs.contains(participantID)
    }

    func onAppear() async {
        guard !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true
        guard hasShareLink else { return }
        await loadShareDetails()
    }

    func createShare() async {
        guard !isCreatingShare else { return }
        isCreatingShare = true
        errorMessage = nil
        workflowMessage = nil

        do {
            let url = try await sharingRepository.createShare(
                pinboardID: pinboardID,
                accessControl: accessControl,
                defaultPermission: defaultPermission
            )
            shareURL = url
            await loadShareDetails()
        } catch {
            present(error: error)
        }

        isCreatingShare = false
    }

    func loadShareDetails() async {
        guard hasShareLink else { return }
        isLoading = true
        errorMessage = nil

        do {
            let details = try await sharingRepository.fetchShareDetails(pinboardID: pinboardID)
            apply(details: details)
        } catch {
            present(error: error)
        }

        isLoading = false
    }

    func updateShareSettingsIfNeeded() async {
        guard hasPendingSettingsChanges else { return }
        guard canManageShareSettings else { return }

        isUpdatingSettings = true
        errorMessage = nil
        workflowMessage = nil

        do {
            let details = try await sharingRepository.updateShareSettings(
                pinboardID: pinboardID,
                accessControl: accessControl,
                defaultPermission: defaultPermission
            )
            apply(details: details)
        } catch {
            present(error: error)
        }

        isUpdatingSettings = false
    }

    func inviteParticipant() async -> Bool {
        guard canManageParticipants else { return false }

        let email = inviteEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(email) else {
            inviteValidationMessage = "Enter a valid email address."
            return false
        }

        isInvitingParticipant = true
        inviteValidationMessage = nil
        errorMessage = nil
        workflowMessage = nil

        let invitePermission: SharePermission = defaultPermission == .viewOnly ? .viewOnly : .canMakeChanges

        do {
            let details = try await sharingRepository.inviteParticipant(
                pinboardID: pinboardID,
                email: email,
                permission: invitePermission
            )
            apply(details: details)
            inviteEmail = ""
            workflowMessage = "Access added. Send the link so this person can open the shared pinboard."
            isInvitingParticipant = false
            return true
        } catch {
            present(error: error)
        }

        isInvitingParticipant = false
        return false
    }

    func markLinkCopiedForInviteFlow() {
        workflowMessage = "Access added and link copied. Send it to finish the invite."
    }

    func updateParticipantPermission(
        participantID: String,
        permission: SharePermission
    ) async {
        guard canManageParticipants else { return }

        participantActionIDs.insert(participantID)
        errorMessage = nil
        workflowMessage = nil

        do {
            let details = try await sharingRepository.updateParticipantPermission(
                pinboardID: pinboardID,
                participantID: participantID,
                permission: permission
            )
            apply(details: details)
        } catch {
            present(error: error)
        }

        participantActionIDs.remove(participantID)
    }

    func requestRemoveParticipant(_ participant: ShareParticipantInfo) {
        pendingParticipantRemoval = participant
    }

    func removePendingParticipant() async {
        guard let participant = pendingParticipantRemoval else { return }
        pendingParticipantRemoval = nil
        guard canManageParticipants else { return }

        participantActionIDs.insert(participant.id)
        errorMessage = nil
        workflowMessage = nil

        do {
            let details = try await sharingRepository.removeParticipant(
                pinboardID: pinboardID,
                participantID: participant.id
            )
            apply(details: details)
        } catch {
            present(error: error)
        }

        participantActionIDs.remove(participant.id)
    }

    func confirmStopSharing() {
        showingStopSharingConfirmation = true
    }

    func stopSharing() async -> Bool {
        guard hasShareLink else { return true }
        isStoppingShare = true
        errorMessage = nil
        workflowMessage = nil

        do {
            try await sharingRepository.stopSharing(pinboardID: pinboardID)
            shareURL = nil
            participants = []
            isOwner = true
            loadedAccessControl = accessControl
            loadedDefaultPermission = defaultPermission
            isStoppingShare = false
            return true
        } catch {
            present(error: error)
            isStoppingShare = false
            return false
        }
    }

    private func apply(details: ShareDetails) {
        shareURL = details.shareURL
        accessControl = details.accessControl
        defaultPermission = details.defaultPermission
        participants = details.participants
        isOwner = details.isOwner
        loadedAccessControl = details.accessControl
        loadedDefaultPermission = details.defaultPermission
    }

    private func isValidEmail(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        guard value.contains("@"), value.contains(".") else { return false }
        return !value.hasPrefix("@") && !value.hasSuffix("@")
    }

    private func present(error: Error) {
        if let sharingError = error as? PinboardSharingError {
            switch sharingError {
            case .featureDisabled:
                errorMessage = "Shared pinboards are disabled on this Mac. Enable the feature flag and restart the app."
            case .participantLookupFailed:
                errorMessage = "Couldn't resolve this email to an iCloud account in the current CloudKit environment."
            case .inviteParticipantFailed:
                errorMessage = "Invite failed. Verify the recipient iCloud account and CloudKit environment."
            case .invalidShareMetadata:
                errorMessage = "Share metadata is invalid or from a different CloudKit environment (Development vs Production). Recreate the share in this build."
            default:
                errorMessage = sharingError.localizedDescription
            }
            return
        }

        errorMessage = error.localizedDescription
    }
}
