import MartenCore
import SwiftUI

struct WatchSyncStatusBanner: View {
    @ObservedObject var syncCoordinator: SyncCoordinator
    let isSyncActionRunning: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSyncActionRunning || syncCoordinator.status == .syncing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))

                if let detailText {
                    Text(detailText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let lastSync = syncCoordinator.lastSyncDate {
                    Text(lastSync.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text(statusShortLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .watchCard(prominence: isErrorStatus ? .critical : .subtle)
    }

    private var statusShortLabel: String {
        switch syncCoordinator.status {
        case .idle:
            return "Idle"
        case .syncing:
            return "Now"
        case .synced:
            return "Ready"
        case .error:
            return "Error"
        }
    }

    private var statusTitle: String {
        if isSyncActionRunning {
            return "Syncing iCloud"
        }

        switch syncCoordinator.status {
        case .idle:
            return "Sync idle"
        case .syncing:
            return "Syncing iCloud"
        case .synced:
            return "Synced"
        case .error:
            return "Sync error"
        }
    }

    private var statusSystemImage: String {
        switch syncCoordinator.status {
        case .idle:
            return "minus.circle"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .synced:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch syncCoordinator.status {
        case .idle:
            return .secondary
        case .syncing:
            return .blue
        case .synced:
            return .green
        case .error:
            return .red
        }
    }

    private var detailText: String? {
        switch syncCoordinator.status {
        case .error(let error):
            return error.errorDescription
        default:
            return nil
        }
    }

    private var isErrorStatus: Bool {
        if case .error = syncCoordinator.status {
            return true
        }

        return false
    }
}
