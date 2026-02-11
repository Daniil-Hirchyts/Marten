import MartenCore
import SwiftUI

struct ShareParticipantRow: View {
    let participant: ShareParticipantInfo
    let canManageParticipants: Bool
    let isActionInFlight: Bool
    let onPermissionChange: (SharePermission) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(participant.displayName)
                        .font(.subheadline.weight(.semibold))
                    if participant.isOwner {
                        Text("Owner")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.16), in: Capsule())
                    }
                    if participant.isCurrentUser {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                    }
                }
                if let email = participant.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if isActionInFlight {
                ProgressView()
                    .controlSize(.small)
            }

            if canManageParticipants && !participant.isOwner && !participant.isCurrentUser {
                Menu(permissionTitle(participant.permission)) {
                    Button("Can Edit") {
                        onPermissionChange(.canMakeChanges)
                    }
                    Button("View Only") {
                        onPermissionChange(.viewOnly)
                    }
                    Divider()
                    Button("Remove", role: .destructive) {
                        onRemove()
                    }
                }
                .disabled(isActionInFlight)
            } else {
                Text(permissionTitle(participant.permission))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(participant.displayName), \(permissionTitle(participant.permission))"
                + (participant.isOwner ? ", owner" : "")
                + (participant.isCurrentUser ? ", you" : "")
        )
    }

    private func permissionTitle(_ permission: SharePermission) -> String {
        switch permission {
        case .owner:
            return "Owner"
        case .canMakeChanges:
            return "Can Edit"
        case .viewOnly:
            return "View Only"
        }
    }
}
