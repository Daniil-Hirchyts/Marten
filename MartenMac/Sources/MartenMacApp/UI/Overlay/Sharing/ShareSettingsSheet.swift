import AppKit
import CoreData
import MartenCore
import SwiftUI

/// Sheet for configuring share settings on a pinboard.
struct ShareSettingsSheet: View {
    @StateObject private var viewModel: ShareSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var accessTabNamespace
    @Namespace private var permissionTabNamespace

    init(
        pinboardID: NSManagedObjectID,
        sharingRepository: any PinboardSharingRepositoryProtocol,
        initialAccessControl: ShareAccessControl = .onlyInvited,
        initialPermission: SharePermission = .canMakeChanges,
        initialShareURL: URL? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ShareSettingsViewModel(
                pinboardID: pinboardID,
                sharingRepository: sharingRepository,
                initialAccessControl: initialAccessControl,
                initialDefaultPermission: initialPermission,
                initialShareURL: initialShareURL
            )
        )
    }

    var body: some View {
        VStack(spacing: 14) {
            headerSection

            ScrollView {
                VStack(spacing: 14) {
                    accessSection
                    permissionSection

                    if let url = viewModel.shareURL {
                        linkSection(url: url)
                        participantsSection
                    }

                    if let workflowMessage = viewModel.workflowMessage {
                        InlineMessage(text: workflowMessage, tint: .green)
                    }

                    if let error = viewModel.errorMessage {
                        InlineMessage(text: error, tint: .red)
                    }
                }
                .padding(.vertical, 2)
            }
                     .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 500) // Increased max height to better accommodate content
            .fixedSize(horizontal: false, vertical: true) // Allow resizing based on content

            footerSection
        }
        .padding(16)
        .frame(width: 430)
        .task {
            await viewModel.onAppear()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Share Pinboard")
                    .font(.system(size: 15, weight: .semibold))
                Text("Manage access and permissions")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isOwner && viewModel.hasShareLink {
                Button(role: .destructive) {
                    let alert = NSAlert()
                    alert.messageText = "Stop sharing this pinboard?"
                    alert.informativeText = "All participant access will be removed immediately."
                    alert.alertStyle = .warning
                    let stopButton = alert.addButton(withTitle: "Stop Sharing")
                    stopButton.hasDestructiveAction = true
                    alert.addButton(withTitle: "Cancel")

                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        Task {
                            if await viewModel.stopSharing() {
                                dismiss()
                            }
                        }
                    }
                } label: {
                    Text("Stop Sharing")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .buttonStyle(.plain)
                .disabled(viewModel.isStoppingShare)
            } else if !viewModel.hasShareLink {
                 Button {
                     Task {
                         await viewModel.createShare()
                     }
                 } label: {
                     Text("Share")
                         .font(.system(size: 11, weight: .semibold))
                         .foregroundStyle(.white)
                         .padding(.horizontal, 12)
                         .padding(.vertical, 4)
                         .background(
                            Capsule()
                                .fill(Color.accentColor)
                         )
                 }
                 .buttonStyle(.plain)
                 .disabled(viewModel.isCreatingShare || viewModel.isLoading)
                 .opacity(viewModel.isCreatingShare || viewModel.isLoading ? 0.6 : 1)
            }
        }
    }

    private var accessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ACCESS")

            HStack(spacing: 6) {
                ShareTabOption(
                    title: "Only Invited",
                    isSelected: viewModel.accessControl == .onlyInvited,
                    namespace: accessTabNamespace,
                    matchedId: "accessTab"
                ) {
                    withAnimation(OverlayAnimation.standardTransition) {
                        viewModel.accessControl = .onlyInvited
                    }
                }

                ShareTabOption(
                    title: "Anyone",
                    isSelected: viewModel.accessControl == .anyoneWithLink,
                    namespace: accessTabNamespace,
                    matchedId: "accessTab"
                ) {
                    withAnimation(OverlayAnimation.standardTransition) {
                        viewModel.accessControl = .anyoneWithLink
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
            )
            .overlay(
                Capsule()
                    .stroke(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle), lineWidth: 1)
            )
            .disabled(viewModel.hasShareLink && !viewModel.isOwner)
            .opacity(viewModel.hasShareLink && !viewModel.isOwner ? 0.55 : 1)

            Text(accessControlDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DEFAULT PERMISSION")

            HStack(spacing: 6) {
                ShareTabOption(
                    title: "Can Edit",
                    isSelected: viewModel.defaultPermission == .canMakeChanges,
                    namespace: permissionTabNamespace,
                    matchedId: "permissionTab"
                ) {
                    withAnimation(OverlayAnimation.standardTransition) {
                        viewModel.defaultPermission = .canMakeChanges
                    }
                }

                ShareTabOption(
                    title: "View Only",
                    isSelected: viewModel.defaultPermission == .viewOnly,
                    namespace: permissionTabNamespace,
                    matchedId: "permissionTab"
                ) {
                    withAnimation(OverlayAnimation.standardTransition) {
                        viewModel.defaultPermission = .viewOnly
                    }
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
            )
            .overlay(
                Capsule()
                    .stroke(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle), lineWidth: 1)
            )
            .disabled(viewModel.hasShareLink && !viewModel.isOwner)
            .opacity(viewModel.hasShareLink && !viewModel.isOwner ? 0.55 : 1)

            if viewModel.hasShareLink && !viewModel.isOwner {
                Text("Only the owner can change sharing settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }


    private func linkSection(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LINK")

            HStack(spacing: 0) {
                Text(url.absoluteString)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)

                // Separator (matches OverlaySearchBarView)
                Rectangle()
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle))
                    .frame(width: 1, height: 16)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                } label: {
                    ZStack {
                        Color.clear
                            .frame(width: 32, height: 32)
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Copy link")
                .help("Copy link to clipboard")

                // Separator (matches OverlaySearchBarView)
                Rectangle()
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle))
                    .frame(width: 1, height: 16)

                ShareLink(item: url) {
                    ZStack {
                        Color.clear
                            .frame(width: 32, height: 32)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Share link")
            }
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle), lineWidth: 1)
            )
        }
    }

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PARTICIPANTS")

            InlineMessage(
                text: sharingFlowDescription,
                tint: .secondary
            )

            if viewModel.shouldShowOnlyInvitedWarning {
                InlineMessage(
                    text: "Only Invited is enabled, but no participant has been invited yet.",
                    tint: .orange
                )
            }

            if viewModel.participants.isEmpty {
                Text("No participants yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    // Filter out the owner from the participants list
                    ForEach(viewModel.participants.filter { !$0.isOwner }) { participant in
                        participantRow(participant)
                    }
                }
            }

            if viewModel.canManageParticipants {
                inviteSection
            }
        }
    }

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ADD ACCESS BY EMAIL")

            HStack(spacing: 8) {
                TextField("name@example.com", text: $viewModel.inviteEmail)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(viewModel.isInvitingParticipant)

                Button {
                    Task {
                        let invited = await viewModel.inviteParticipant()
                        guard invited, let url = viewModel.shareURL else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        viewModel.markLinkCopiedForInviteFlow()
                    }
                } label: {
                    Text("Add Access")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    viewModel.shouldShowOnlyInvitedWarning
                                        ? Color.orange.opacity(0.9)
                                        : Color.accentColor
                                )
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isInvitingParticipant)
                .opacity(viewModel.isInvitingParticipant ? 0.6 : 1)
            }

            if let message = viewModel.inviteValidationMessage {
                InlineMessage(text: message, tint: .orange)
            }

            Text(inviteHintText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    viewModel.shouldShowOnlyInvitedWarning
                        ? Color.orange.opacity(0.6)
                        : adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle),
                    lineWidth: 1
                )
        )
    }

    private func participantRow(_ participant: ShareParticipantInfo) -> some View {
        let loading = viewModel.isParticipantActionInFlight(participant.id)

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(participantDisplayName(participant))
                        .font(.system(size: 12, weight: .semibold))
                    if let email = participant.email, !email.isEmpty, email != participant.displayName {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                StatusBadge(
                    text: participant.acceptanceStatus.statusLabel,
                    tint: participant.acceptanceStatus.statusColor
                )
            }

            if viewModel.canManageParticipants && !participant.isOwner {
                HStack(spacing: 8) {
                    Picker(
                        "Permission",
                        selection: Binding(
                            get: { participant.permission },
                            set: { newPermission in
                                Task {
                                    await viewModel.updateParticipantPermission(
                                        participantID: participant.id,
                                        permission: newPermission
                                    )
                                }
                            }
                        )
                    ) {
                        Text("Can Edit").tag(SharePermission.canMakeChanges)
                        Text("View Only").tag(SharePermission.viewOnly)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(loading)

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        let displayName = participant.displayName
                        let alert = NSAlert()
                        alert.messageText = "Remove participant?"
                        alert.informativeText = "This will revoke access for \(displayName)."
                        alert.alertStyle = .warning
                        let removeButton = alert.addButton(withTitle: "Remove")
                        removeButton.hasDestructiveAction = true
                        alert.addButton(withTitle: "Cancel")

                        let response = alert.runModal()
                        if response == .alertFirstButtonReturn {
                            viewModel.pendingParticipantRemoval = participant
                            Task {
                                await viewModel.removePendingParticipant()
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.minus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            } else {
                Text(participantPermissionLabel(participant.permission))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if participant.acceptanceStatus == .pending, viewModel.canManageParticipants {
                Text("Waiting for this person to open the share link.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(adaptiveFillColor(opacity: DesignTokens.Opacity.backgroundSubtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(adaptiveFillColor(opacity: DesignTokens.Opacity.borderSubtle), lineWidth: 1)
        )
        .opacity(loading ? 0.65 : 1)
    }

    private var footerSection: some View {
        VStack(spacing: 8) {
            if !viewModel.hasShareLink {
                 // "Generate Link" moved to header as "Share"
            } else if viewModel.isOwner {
                // Settings are auto-saved or managed via toggles now. 
                // "Update" button removed as per design.
            } else {
                Text("Sharing settings are managed by the owner.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func sectionLabel(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func participantDisplayName(_ participant: ShareParticipantInfo) -> String {
        participant.isCurrentUser ? "\(participant.displayName) (You)" : participant.displayName
    }

    private func participantPermissionLabel(_ permission: SharePermission) -> String {
        switch permission {
        case .owner:
            return "Owner"
        case .canMakeChanges:
            return "Can Edit"
        case .viewOnly:
            return "View Only"
        }
    }

    private func adaptiveFillColor(opacity: CGFloat) -> Color {
        colorScheme == .dark
            ? Color.white.opacity(opacity)
            : Color.black.opacity(opacity)
    }

    private var accessControlDescription: String {
        switch viewModel.accessControl {
        case .onlyInvited:
            return "Only people you explicitly invite can open this pinboard."
        case .anyoneWithLink:
            return "Anyone who has the link can access it with the selected permission."
        }
    }

    private var sharingFlowDescription: String {
        switch viewModel.accessControl {
        case .onlyInvited:
            return "Invite by email grants access. People join only after opening the link you send."
        case .anyoneWithLink:
            return "Anyone with the link can join. Email access is optional for tracking participants."
        }
    }

    private var inviteHintText: String {
        switch viewModel.accessControl {
        case .onlyInvited:
            return "After adding access, the link is copied automatically. Send it to complete the invite."
        case .anyoneWithLink:
            return "Link is copied automatically after adding access. You can also share the link directly above."
        }
    }
}

// MARK: - Components

private extension CGFloat {
    func color(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(self) : Color.black.opacity(self)
    }
}

/// Capsule tab option matching the picker language used across overlay sheets.
private struct ShareTabOption: View {
    let title: String
    let isSelected: Bool
    var namespace: Namespace.ID
    var matchedId: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: matchedId, in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct InlineMessage: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(adaptiveColor(opacity: DesignTokens.Opacity.backgroundSubtle))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(adaptiveColor(opacity: DesignTokens.Opacity.borderSubtle), lineWidth: 1)
            )
    }

    private func adaptiveColor(opacity: CGFloat) -> Color {
        colorScheme == .dark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
    }
}

private struct StatusBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
            )
    }
}

private extension ShareParticipantAcceptanceStatus {
    var statusLabel: String {
        switch self {
        case .pending:
            return "Waiting"
        case .accepted:
            return "Accepted"
        case .removed:
            return "Removed"
        case .unknown:
            return "Unknown"
        }
    }

    var statusColor: Color {
        switch self {
        case .pending:
            return .orange
        case .accepted:
            return .green
        case .removed:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
